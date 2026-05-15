from __future__ import annotations

import json
import os
import subprocess
import sys
import urllib.parse
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parent
STATIC_ROOT = ROOT / "static"

SQL_SERVER = os.environ.get("HELPDESK_SQL_SERVER", r".\SQLEXPRESS")
SQL_DATABASE = os.environ.get("HELPDESK_SQL_DATABASE", "CustomerAIDemo2022")
SQLCMD = os.environ.get("HELPDESK_SQLCMD", "sqlcmd")
EMBEDDING_MODE = os.environ.get("HELPDESK_EMBEDDING_MODE", "auto").lower()
OLLAMA_URL = os.environ.get("HELPDESK_OLLAMA_URL", "http://127.0.0.1:11434/api/embed")
OLLAMA_MODEL = os.environ.get("HELPDESK_OLLAMA_MODEL", "bge-m3")
_REAL_EMBEDDINGS_AVAILABLE: bool | None = None

QUERY_PROFILES = {
    "debited_failed_transaction",
    "vip_serious_payment_issue",
    "suspicious_money_movement",
}


def sql_literal(value: str | None) -> str:
    if value is None or value == "":
        return "NULL"
    return "N'" + value.replace("'", "''") + "'"


def sql_int(value: Any, default: int, minimum: int, maximum: int) -> int:
    try:
        parsed = int(value)
    except (TypeError, ValueError):
        return default
    return max(minimum, min(parsed, maximum))


def choose_query_profile(question: str) -> str:
    normalized = question.lower()
    if any(token in normalized for token in ("gian lận", "gian lan", "đáng ngờ", "dang ngo", "fraud", "lạ", "la")):
        return "suspicious_money_movement"
    if "vip" in normalized or "ưu tiên" in normalized or "uu tien" in normalized:
        return "vip_serious_payment_issue"
    return "debited_failed_transaction"


def ollama_embed(text: str) -> list[float]:
    payload = json.dumps({"model": OLLAMA_MODEL, "input": text}).encode("utf-8")
    request = urllib.request.Request(
        OLLAMA_URL,
        data=payload,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=120) as response:
            body = json.loads(response.read().decode("utf-8"))
    except urllib.error.URLError as exc:
        raise RuntimeError(
            f"Cannot connect to Ollama at {OLLAMA_URL}. Start Ollama and run: ollama pull {OLLAMA_MODEL}"
        ) from exc

    if "embeddings" in body:
        embeddings = body["embeddings"]
        if embeddings and isinstance(embeddings[0], list):
            return [float(value) for value in embeddings[0]]
    if "embedding" in body:
        return [float(value) for value in body["embedding"]]

    raise RuntimeError(f"Unexpected Ollama embedding response: {body}")


def run_sql(query: str) -> Any:
    command = [
        SQLCMD,
        "-S",
        SQL_SERVER,
        "-d",
        SQL_DATABASE,
        "-E",
        "-b",
        "-f",
        "i:65001,o:65001",
        "-w",
        "65535",
        "-y",
        "0",
        "-Q",
        "SET NOCOUNT ON;\n" + query,
    ]
    completed = subprocess.run(
        command,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        check=False,
    )

    if completed.returncode != 0:
        raise RuntimeError((completed.stderr or completed.stdout).strip())

    output = completed.stdout.strip()
    if not output:
        return []

    json_start = min((idx for idx in (output.find("["), output.find("{")) if idx != -1), default=-1)
    if json_start > 0:
        output = output[json_start:]

    # sqlcmd can insert physical line breaks into long FOR JSON output. Those
    # breaks are not part of SQL Server's JSON payload and can land inside JSON
    # strings, so remove them before parsing.
    output = output.replace("\r", "").replace("\n", "")

    return json.loads(output)


def real_embedding_status_query() -> str:
    return """
IF OBJECT_ID(N'dbo.RealFeedbackEmbedding', N'U') IS NULL
BEGIN
    SELECT
        CAST(0 AS INT) AS embedded_feedback_count,
        CAST(NULL AS NVARCHAR(200)) AS model_name,
        CAST(NULL AS INT) AS dimension_count
    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER, INCLUDE_NULL_VALUES;
END
ELSE
BEGIN
    SELECT
        COUNT(DISTINCT e.FeedbackId) AS embedded_feedback_count,
        MAX(m.ModelName) AS model_name,
        MAX(m.DimensionCount) AS dimension_count
    FROM dbo.RealFeedbackEmbedding AS e
    OUTER APPLY
    (
        SELECT TOP (1)
            ModelName,
            DimensionCount
        FROM dbo.RealEmbeddingMetadata
        ORDER BY CreatedAt DESC
    ) AS m
    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER, INCLUDE_NULL_VALUES;
END
"""


def real_embeddings_available() -> bool:
    global _REAL_EMBEDDINGS_AVAILABLE

    if EMBEDDING_MODE == "fallback":
        return False
    if _REAL_EMBEDDINGS_AVAILABLE is not None:
        return _REAL_EMBEDDINGS_AVAILABLE

    try:
        status = run_sql(real_embedding_status_query())
        _REAL_EMBEDDINGS_AVAILABLE = int(status.get("embedded_feedback_count") or 0) > 0
    except Exception:
        _REAL_EMBEDDINGS_AVAILABLE = False

    if EMBEDDING_MODE == "real" and not _REAL_EMBEDDINGS_AVAILABLE:
        raise RuntimeError(
            "Real embeddings are not built yet. Run scripts/build_real_embeddings_ollama.ps1 first."
        )

    return _REAL_EMBEDDINGS_AVAILABLE


def query_embedding_json(question: str) -> str:
    return json.dumps(ollama_embed(question), separators=(",", ":"))


def keyword_query(keyword: str, top: int) -> str:
    return f"""
DECLARE @Keyword NVARCHAR(100) = {sql_literal(keyword)};

SELECT TOP ({top})
    FeedbackId,
    Product,
    CustomerSegment,
    RiskLevel,
    Channel,
    Region,
    CreatedAt,
    FeedbackText
FROM dbo.CustomerFeedback
WHERE FeedbackText LIKE N'%' + @Keyword + N'%'
ORDER BY CreatedAt DESC
FOR JSON PATH, INCLUDE_NULL_VALUES;
"""


def semantic_query(query_name: str, segment: str | None, risk: str | None, days_back: int, top: int) -> str:
    if query_name not in QUERY_PROFILES:
        query_name = "debited_failed_transaction"

    return f"""
DECLARE @QueryName SYSNAME = {sql_literal(query_name)};
DECLARE @CustomerSegment NVARCHAR(50) = {sql_literal(segment)};
DECLARE @RiskLevel NVARCHAR(20) = {sql_literal(risk)};
DECLARE @DaysBack INT = {days_back};

;WITH QueryNorm AS
(
    SELECT SQRT(SUM(Value * Value)) AS Norm
    FROM dbo.QueryEmbedding
    WHERE QueryName = @QueryName
),
FeedbackNorm AS
(
    SELECT FeedbackId, SQRT(SUM(Value * Value)) AS Norm
    FROM dbo.FeedbackEmbedding
    GROUP BY FeedbackId
),
DotProduct AS
(
    SELECT fe.FeedbackId, SUM(fe.Value * qe.Value) AS DotValue
    FROM dbo.FeedbackEmbedding AS fe
    INNER JOIN dbo.QueryEmbedding AS qe
        ON qe.DimensionName = fe.DimensionName
       AND qe.QueryName = @QueryName
    GROUP BY fe.FeedbackId
),
Scored AS
(
    SELECT
        f.FeedbackId,
        f.Product,
        f.CustomerSegment,
        f.RiskLevel,
        f.Channel,
        f.Region,
        f.CreatedAt,
        f.FeedbackText,
        CAST(dp.DotValue / NULLIF(fn.Norm * qn.Norm, 0) AS DECIMAL(10, 4)) AS similarity
    FROM DotProduct AS dp
    INNER JOIN FeedbackNorm AS fn
        ON fn.FeedbackId = dp.FeedbackId
    CROSS JOIN QueryNorm AS qn
    INNER JOIN dbo.CustomerFeedback AS f
        ON f.FeedbackId = dp.FeedbackId
    WHERE (@CustomerSegment IS NULL OR f.CustomerSegment = @CustomerSegment)
      AND (@RiskLevel IS NULL OR f.RiskLevel = @RiskLevel)
      AND (@DaysBack IS NULL OR f.CreatedAt >= DATEADD(DAY, -@DaysBack, SYSUTCDATETIME()))
)
SELECT TOP ({top})
    FeedbackId,
    Product,
    CustomerSegment,
    RiskLevel,
    Channel,
    Region,
    CreatedAt,
    FeedbackText,
    similarity
FROM Scored
ORDER BY similarity DESC, CreatedAt DESC
FOR JSON PATH, INCLUDE_NULL_VALUES;
"""


def real_semantic_query(
    embedding_json: str,
    segment: str | None,
    risk: str | None,
    days_back: int,
    top: int,
) -> str:
    return f"""
DECLARE @QueryEmbedding NVARCHAR(MAX) = {sql_literal(embedding_json)};
DECLARE @CustomerSegment NVARCHAR(50) = {sql_literal(segment)};
DECLARE @RiskLevel NVARCHAR(20) = {sql_literal(risk)};
DECLARE @DaysBack INT = {days_back};

;WITH QueryVector AS
(
    SELECT
        CAST([key] AS INT) AS DimensionIndex,
        CAST([value] AS FLOAT) AS Value
    FROM OPENJSON(@QueryEmbedding)
),
QueryNorm AS
(
    SELECT SQRT(SUM(Value * Value)) AS Norm
    FROM QueryVector
),
FeedbackNorm AS
(
    SELECT
        FeedbackId,
        SQRT(SUM(Value * Value)) AS Norm
    FROM dbo.RealFeedbackEmbedding
    GROUP BY FeedbackId
),
DotProduct AS
(
    SELECT
        fe.FeedbackId,
        SUM(fe.Value * q.Value) AS DotValue
    FROM dbo.RealFeedbackEmbedding AS fe
    INNER JOIN QueryVector AS q
        ON q.DimensionIndex = fe.DimensionIndex
    GROUP BY fe.FeedbackId
),
Scored AS
(
    SELECT
        f.FeedbackId,
        f.Product,
        f.CustomerSegment,
        f.RiskLevel,
        f.Channel,
        f.Region,
        f.CreatedAt,
        f.FeedbackText,
        CAST(dp.DotValue / NULLIF(fn.Norm * qn.Norm, 0) AS DECIMAL(10, 4)) AS similarity
    FROM DotProduct AS dp
    INNER JOIN FeedbackNorm AS fn
        ON fn.FeedbackId = dp.FeedbackId
    CROSS JOIN QueryNorm AS qn
    INNER JOIN dbo.CustomerFeedback AS f
        ON f.FeedbackId = dp.FeedbackId
    WHERE (@CustomerSegment IS NULL OR f.CustomerSegment = @CustomerSegment)
      AND (@RiskLevel IS NULL OR f.RiskLevel = @RiskLevel)
      AND (@DaysBack IS NULL OR f.CreatedAt >= DATEADD(DAY, -@DaysBack, SYSUTCDATETIME()))
)
SELECT TOP ({top})
    FeedbackId,
    Product,
    CustomerSegment,
    RiskLevel,
    Channel,
    Region,
    CreatedAt,
    FeedbackText,
    similarity
FROM Scored
ORDER BY similarity DESC, CreatedAt DESC
FOR JSON PATH, INCLUDE_NULL_VALUES;
"""


def similar_query(feedback_id: int, top: int) -> str:
    return f"""
DECLARE @FeedbackId INT = {feedback_id};

;WITH SeedNorm AS
(
    SELECT SQRT(SUM(Value * Value)) AS Norm
    FROM dbo.FeedbackEmbedding
    WHERE FeedbackId = @FeedbackId
),
FeedbackNorm AS
(
    SELECT FeedbackId, SQRT(SUM(Value * Value)) AS Norm
    FROM dbo.FeedbackEmbedding
    GROUP BY FeedbackId
),
DotProduct AS
(
    SELECT fe.FeedbackId, SUM(fe.Value * seed.Value) AS DotValue
    FROM dbo.FeedbackEmbedding AS fe
    INNER JOIN dbo.FeedbackEmbedding AS seed
        ON seed.DimensionName = fe.DimensionName
       AND seed.FeedbackId = @FeedbackId
    WHERE fe.FeedbackId <> @FeedbackId
    GROUP BY fe.FeedbackId
)
SELECT TOP ({top})
    f.FeedbackId,
    f.Product,
    f.CustomerSegment,
    f.RiskLevel,
    f.Channel,
    f.Region,
    f.CreatedAt,
    f.FeedbackText,
    CAST(dp.DotValue / NULLIF(fn.Norm * sn.Norm, 0) AS DECIMAL(10, 4)) AS similarity
FROM DotProduct AS dp
INNER JOIN FeedbackNorm AS fn
    ON fn.FeedbackId = dp.FeedbackId
CROSS JOIN SeedNorm AS sn
INNER JOIN dbo.CustomerFeedback AS f
    ON f.FeedbackId = dp.FeedbackId
ORDER BY similarity DESC, f.CreatedAt DESC
FOR JSON PATH, INCLUDE_NULL_VALUES;
"""


def real_similar_query(feedback_id: int, top: int) -> str:
    return f"""
DECLARE @FeedbackId INT = {feedback_id};

;WITH SeedNorm AS
(
    SELECT SQRT(SUM(Value * Value)) AS Norm
    FROM dbo.RealFeedbackEmbedding
    WHERE FeedbackId = @FeedbackId
),
FeedbackNorm AS
(
    SELECT
        FeedbackId,
        SQRT(SUM(Value * Value)) AS Norm
    FROM dbo.RealFeedbackEmbedding
    GROUP BY FeedbackId
),
DotProduct AS
(
    SELECT
        fe.FeedbackId,
        SUM(fe.Value * seed.Value) AS DotValue
    FROM dbo.RealFeedbackEmbedding AS fe
    INNER JOIN dbo.RealFeedbackEmbedding AS seed
        ON seed.DimensionIndex = fe.DimensionIndex
       AND seed.FeedbackId = @FeedbackId
    WHERE fe.FeedbackId <> @FeedbackId
    GROUP BY fe.FeedbackId
)
SELECT TOP ({top})
    f.FeedbackId,
    f.Product,
    f.CustomerSegment,
    f.RiskLevel,
    f.Channel,
    f.Region,
    f.CreatedAt,
    f.FeedbackText,
    CAST(dp.DotValue / NULLIF(fn.Norm * sn.Norm, 0) AS DECIMAL(10, 4)) AS similarity
FROM DotProduct AS dp
INNER JOIN FeedbackNorm AS fn
    ON fn.FeedbackId = dp.FeedbackId
CROSS JOIN SeedNorm AS sn
INNER JOIN dbo.CustomerFeedback AS f
    ON f.FeedbackId = dp.FeedbackId
ORDER BY similarity DESC, f.CreatedAt DESC
FOR JSON PATH, INCLUDE_NULL_VALUES;
"""


def triage_query(query_name: str) -> str:
    if query_name not in QUERY_PROFILES:
        query_name = "debited_failed_transaction"

    return f"""
DECLARE @QueryName SYSNAME = {sql_literal(query_name)};

;WITH TopHits AS
(
    SELECT TOP (40)
        f.FeedbackId,
        f.Product,
        f.RiskLevel,
        CAST(dp.DotValue / NULLIF(fn.Norm * qn.Norm, 0) AS DECIMAL(10, 4)) AS similarity
    FROM
    (
        SELECT fe.FeedbackId, SUM(fe.Value * qe.Value) AS DotValue
        FROM dbo.FeedbackEmbedding AS fe
        INNER JOIN dbo.QueryEmbedding AS qe
            ON qe.DimensionName = fe.DimensionName
           AND qe.QueryName = @QueryName
        GROUP BY fe.FeedbackId
    ) AS dp
    INNER JOIN
    (
        SELECT FeedbackId, SQRT(SUM(Value * Value)) AS Norm
        FROM dbo.FeedbackEmbedding
        GROUP BY FeedbackId
    ) AS fn
        ON fn.FeedbackId = dp.FeedbackId
    CROSS JOIN
    (
        SELECT SQRT(SUM(Value * Value)) AS Norm
        FROM dbo.QueryEmbedding
        WHERE QueryName = @QueryName
    ) AS qn
    INNER JOIN dbo.CustomerFeedback AS f
        ON f.FeedbackId = dp.FeedbackId
    ORDER BY similarity DESC
)
SELECT
    Product,
    RiskLevel,
    COUNT(*) AS hit_count,
    MAX(similarity) AS best_similarity,
    CAST(AVG(CAST(similarity AS FLOAT)) AS DECIMAL(10, 4)) AS avg_similarity
FROM TopHits
GROUP BY Product, RiskLevel
ORDER BY best_similarity DESC, hit_count DESC
FOR JSON PATH, INCLUDE_NULL_VALUES;
"""


def real_triage_query(embedding_json: str) -> str:
    return f"""
DECLARE @QueryEmbedding NVARCHAR(MAX) = {sql_literal(embedding_json)};

;WITH QueryVector AS
(
    SELECT
        CAST([key] AS INT) AS DimensionIndex,
        CAST([value] AS FLOAT) AS Value
    FROM OPENJSON(@QueryEmbedding)
),
QueryNorm AS
(
    SELECT SQRT(SUM(Value * Value)) AS Norm
    FROM QueryVector
),
TopHits AS
(
    SELECT TOP (40)
        f.FeedbackId,
        f.Product,
        f.RiskLevel,
        CAST(dp.DotValue / NULLIF(fn.Norm * qn.Norm, 0) AS DECIMAL(10, 4)) AS similarity
    FROM
    (
        SELECT
            fe.FeedbackId,
            SUM(fe.Value * q.Value) AS DotValue
        FROM dbo.RealFeedbackEmbedding AS fe
        INNER JOIN QueryVector AS q
            ON q.DimensionIndex = fe.DimensionIndex
        GROUP BY fe.FeedbackId
    ) AS dp
    INNER JOIN
    (
        SELECT FeedbackId, SQRT(SUM(Value * Value)) AS Norm
        FROM dbo.RealFeedbackEmbedding
        GROUP BY FeedbackId
    ) AS fn
        ON fn.FeedbackId = dp.FeedbackId
    CROSS JOIN QueryNorm AS qn
    INNER JOIN dbo.CustomerFeedback AS f
        ON f.FeedbackId = dp.FeedbackId
    ORDER BY similarity DESC
)
SELECT
    Product,
    RiskLevel,
    COUNT(*) AS hit_count,
    MAX(similarity) AS best_similarity,
    CAST(AVG(CAST(similarity AS FLOAT)) AS DECIMAL(10, 4)) AS avg_similarity
FROM TopHits
GROUP BY Product, RiskLevel
ORDER BY best_similarity DESC, hit_count DESC
FOR JSON PATH, INCLUDE_NULL_VALUES;
"""


def real_feedback_embedding_query(feedback_id: int) -> str:
    return f"""
DECLARE @FeedbackId INT = {feedback_id};
DECLARE @FeedbackText NVARCHAR(MAX) =
    (SELECT FeedbackText FROM dbo.CustomerFeedback WHERE FeedbackId = @FeedbackId);
DECLARE @ModelName NVARCHAR(200) =
    (SELECT TOP (1) ModelName FROM dbo.RealEmbeddingMetadata ORDER BY CreatedAt DESC);
DECLARE @DimensionCount INT =
    (SELECT COUNT(*) FROM dbo.RealFeedbackEmbedding WHERE FeedbackId = @FeedbackId);
DECLARE @Norm FLOAT =
    (SELECT SQRT(SUM(Value * Value)) FROM dbo.RealFeedbackEmbedding WHERE FeedbackId = @FeedbackId);

SELECT
    @FeedbackId AS feedback_id,
    @FeedbackText AS feedback_text,
    @ModelName AS model_name,
    @DimensionCount AS dimension_count,
    CAST(@Norm AS DECIMAL(18, 6)) AS norm,
    (
        SELECT CAST(Value AS DECIMAL(18, 8)) AS v
        FROM dbo.RealFeedbackEmbedding
        WHERE FeedbackId = @FeedbackId
        ORDER BY DimensionIndex
        FOR JSON PATH
    ) AS vector_json
FOR JSON PATH, WITHOUT_ARRAY_WRAPPER, INCLUDE_NULL_VALUES;
"""


def fallback_feedback_embedding_query(feedback_id: int) -> str:
    return f"""
DECLARE @FeedbackId INT = {feedback_id};
DECLARE @FeedbackText NVARCHAR(MAX) =
    (SELECT FeedbackText FROM dbo.CustomerFeedback WHERE FeedbackId = @FeedbackId);
DECLARE @DimensionCount INT =
    (SELECT COUNT(*) FROM dbo.FeedbackEmbedding WHERE FeedbackId = @FeedbackId);
DECLARE @Norm FLOAT =
    (SELECT SQRT(SUM(Value * Value)) FROM dbo.FeedbackEmbedding WHERE FeedbackId = @FeedbackId);

SELECT
    @FeedbackId AS feedback_id,
    @FeedbackText AS feedback_text,
    N'fallback-pseudo' AS model_name,
    @DimensionCount AS dimension_count,
    CAST(@Norm AS DECIMAL(18, 6)) AS norm,
    (
        SELECT
            DimensionName AS k,
            CAST(Value AS DECIMAL(18, 8)) AS v
        FROM dbo.FeedbackEmbedding
        WHERE FeedbackId = @FeedbackId
        ORDER BY DimensionName
        FOR JSON PATH
    ) AS vector_json
FOR JSON PATH, WITHOUT_ARRAY_WRAPPER, INCLUDE_NULL_VALUES;
"""


def overview_query() -> str:
    return """
SELECT
    CAST(SERVERPROPERTY('ProductVersion') AS NVARCHAR(40)) AS product_version,
    CAST(SERVERPROPERTY('Edition') AS NVARCHAR(128)) AS edition,
    DB_NAME() AS database_name,
    (SELECT COUNT(*) FROM dbo.CustomerFeedback) AS feedback_count,
    (SELECT COUNT(*) FROM dbo.FeedbackEmbedding) AS embedding_rows,
    (SELECT COUNT(DISTINCT FeedbackId) FROM dbo.FeedbackEmbedding) AS embedded_feedback_count,
    (SELECT COUNT(*) FROM dbo.CustomerFeedback WHERE RiskLevel = N'Critical') AS critical_count,
    (SELECT COUNT(*) FROM dbo.CustomerFeedback WHERE CustomerSegment = N'VIP') AS vip_count
FOR JSON PATH, WITHOUT_ARRAY_WRAPPER, INCLUDE_NULL_VALUES;
"""


def issue_distribution_query() -> str:
    return """
SELECT
    SourceIssueGroup,
    COUNT(*) AS count
FROM dbo.CustomerFeedback
GROUP BY SourceIssueGroup
ORDER BY count DESC
FOR JSON PATH, INCLUDE_NULL_VALUES;
"""


def read_request_json(handler: BaseHTTPRequestHandler) -> dict[str, Any]:
    length = int(handler.headers.get("Content-Length", "0"))
    if length <= 0:
        return {}
    raw = handler.rfile.read(length).decode("utf-8")
    return json.loads(raw)


class DemoHandler(BaseHTTPRequestHandler):
    server_version = "HelpdeskVectorDemo/1.0"

    def do_GET(self) -> None:
        parsed = urllib.parse.urlparse(self.path)
        if parsed.path == "/":
            self.send_static("index.html")
            return
        if parsed.path == "/api/overview":
            self.send_json(
                {
                    "overview": run_sql(overview_query()),
                    "issues": run_sql(issue_distribution_query()),
                    "realEmbedding": run_sql(real_embedding_status_query()),
                    "embeddingMode": EMBEDDING_MODE,
                    "ollamaModel": OLLAMA_MODEL,
                }
            )
            return
        if parsed.path.startswith("/static/"):
            self.send_static(parsed.path.removeprefix("/static/"))
            return
        self.send_error(404)

    def do_POST(self) -> None:
        try:
            parsed = urllib.parse.urlparse(self.path)
            payload = read_request_json(self)

            if parsed.path == "/api/search":
                mode = str(payload.get("mode") or "semantic")
                top = sql_int(payload.get("top"), 10, 1, 50)
                if mode == "keyword":
                    keyword = str(payload.get("keyword") or payload.get("question") or "trừ tiền")
                    rows = run_sql(keyword_query(keyword, top))
                    self.send_json({"mode": "keyword", "rows": rows})
                    return

                question = str(payload.get("question") or "khách hàng bị trừ tiền dù giao dịch thất bại")
                if real_embeddings_available():
                    rows = run_sql(
                        real_semantic_query(
                            embedding_json=query_embedding_json(question),
                            segment=payload.get("segment") or None,
                            risk=payload.get("risk") or None,
                            days_back=sql_int(payload.get("daysBack"), 30, 1, 365),
                            top=top,
                        )
                    )
                    self.send_json(
                        {
                            "mode": "semantic",
                            "queryProfile": f"real_ollama:{OLLAMA_MODEL}",
                            "rows": rows,
                        }
                    )
                    return

                query_name = choose_query_profile(question)
                rows = run_sql(
                    semantic_query(
                        query_name=query_name,
                        segment=payload.get("segment") or None,
                        risk=payload.get("risk") or None,
                        days_back=sql_int(payload.get("daysBack"), 30, 1, 365),
                        top=top,
                    )
                )
                self.send_json({"mode": "semantic", "queryProfile": f"fallback:{query_name}", "rows": rows})
                return

            if parsed.path == "/api/similar":
                feedback_id = sql_int(payload.get("feedbackId"), 1, 1, 2_147_483_647)
                top = sql_int(payload.get("top"), 15, 1, 50)
                if real_embeddings_available():
                    rows = run_sql(real_similar_query(feedback_id, top))
                    self.send_json(
                        {
                            "feedbackId": feedback_id,
                            "queryProfile": f"real_ollama:{OLLAMA_MODEL}",
                            "rows": rows,
                        }
                    )
                    return

                rows = run_sql(similar_query(feedback_id, top))
                self.send_json({"feedbackId": feedback_id, "queryProfile": "fallback", "rows": rows})
                return

            if parsed.path == "/api/embedding":
                feedback_id = sql_int(payload.get("feedbackId"), 1, 1, 2_147_483_647)
                if real_embeddings_available():
                    raw = run_sql(real_feedback_embedding_query(feedback_id))
                    vector_raw = raw.get("vector_json") if isinstance(raw, dict) else None
                    values = [item["v"] for item in json.loads(vector_raw)] if vector_raw else []
                    self.send_json(
                        {
                            "feedbackId": feedback_id,
                            "source": f"real_ollama:{OLLAMA_MODEL}",
                            "modelName": raw.get("model_name"),
                            "dimensionCount": raw.get("dimension_count"),
                            "norm": raw.get("norm"),
                            "feedbackText": raw.get("feedback_text"),
                            "values": values,
                        }
                    )
                    return

                raw = run_sql(fallback_feedback_embedding_query(feedback_id))
                vector_raw = raw.get("vector_json") if isinstance(raw, dict) else None
                items = json.loads(vector_raw) if vector_raw else []
                values = [item["v"] for item in items]
                labels = [item.get("k") for item in items]
                self.send_json(
                    {
                        "feedbackId": feedback_id,
                        "source": "fallback-pseudo",
                        "modelName": raw.get("model_name"),
                        "dimensionCount": raw.get("dimension_count"),
                        "norm": raw.get("norm"),
                        "feedbackText": raw.get("feedback_text"),
                        "values": values,
                        "labels": labels,
                    }
                )
                return

            if parsed.path == "/api/triage":
                question = str(payload.get("question") or "khách hàng bị trừ tiền dù giao dịch thất bại")
                if real_embeddings_available():
                    rows = run_sql(real_triage_query(query_embedding_json(question)))
                    self.send_json({"queryProfile": f"real_ollama:{OLLAMA_MODEL}", "rows": rows})
                    return

                query_name = choose_query_profile(question)
                rows = run_sql(triage_query(query_name))
                self.send_json({"queryProfile": f"fallback:{query_name}", "rows": rows})
                return

            self.send_error(404)
        except Exception as exc:
            self.send_json({"error": str(exc)}, status=500)

    def send_json(self, value: Any, status: int = 200) -> None:
        body = json.dumps(value, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def send_static(self, name: str) -> None:
        safe_name = name.strip("/") or "index.html"
        path = (STATIC_ROOT / safe_name).resolve()
        if not str(path).startswith(str(STATIC_ROOT.resolve())) or not path.exists() or not path.is_file():
            self.send_error(404)
            return

        content_type = "text/plain; charset=utf-8"
        if path.suffix == ".html":
            content_type = "text/html; charset=utf-8"
        elif path.suffix == ".css":
            content_type = "text/css; charset=utf-8"
        elif path.suffix == ".js":
            content_type = "application/javascript; charset=utf-8"

        body = path.read_bytes()
        self.send_response(200)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format: str, *args: Any) -> None:
        sys.stderr.write("%s - %s\n" % (self.address_string(), format % args))


def main() -> None:
    port = sql_int(os.environ.get("HELPDESK_UI_PORT"), 8080, 1024, 65535)
    host = os.environ.get("HELPDESK_UI_HOST", "127.0.0.1")
    server = ThreadingHTTPServer((host, port), DemoHandler)
    print(f"AI Helpdesk demo UI: http://{host}:{port}")
    print(f"SQL Server: {SQL_SERVER} | Database: {SQL_DATABASE}")
    server.serve_forever()


if __name__ == "__main__":
    main()
