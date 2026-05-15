from __future__ import annotations

import os
import re
from dataclasses import dataclass
from typing import Iterable

import pyodbc
from dotenv import load_dotenv


DEFAULT_QUESTION = "khách hàng bị trừ tiền dù giao dịch thất bại"


@dataclass(frozen=True)
class SearchFilters:
    segment: str | None = None
    risk: str | None = None
    days_back: int | None = 30


def checked_identifier(value: str) -> str:
    if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]{0,127}", value):
        raise ValueError(f"Unsafe SQL identifier: {value!r}")
    return f"[{value}]"


def connect() -> pyodbc.Connection:
    load_dotenv()
    dsn = os.getenv("SQLSERVER_DSN")
    if not dsn:
        raise RuntimeError("Set SQLSERVER_DSN in .env or environment variables.")
    return pyodbc.connect(dsn)


def print_rows(rows: Iterable[pyodbc.Row]) -> None:
    for row in rows:
        distance = getattr(row, "distance", None)
        score = "" if distance is None else f" | distance={distance:.4f}"
        print(
            f"[{row.FeedbackId}] {row.Product} | {row.CustomerSegment} | "
            f"{row.RiskLevel}{score}\n  {row.FeedbackText}\n"
        )


def keyword_search(conn: pyodbc.Connection, keyword: str) -> None:
    sql = """
    SELECT TOP (10)
        FeedbackId,
        Product,
        CustomerSegment,
        RiskLevel,
        FeedbackText
    FROM dbo.CustomerFeedback
    WHERE FeedbackText LIKE N'%' + ? + N'%'
    ORDER BY CreatedAt DESC;
    """
    print(f"\nKeyword search: {keyword!r}\n")
    print_rows(conn.execute(sql, keyword).fetchall())


def semantic_search(
    conn: pyodbc.Connection,
    question: str,
    filters: SearchFilters,
    top: int = 10,
) -> None:
    model = checked_identifier(os.getenv("SQLSERVER_EMBEDDING_MODEL", "LocalEmbeddingModel"))
    dimensions = int(os.getenv("SQLSERVER_VECTOR_DIMENSIONS", "1024"))
    mode = os.getenv("SQLSERVER_SEARCH_MODE", "approx").lower()
    top = max(1, min(top, 50))

    if mode == "exact":
        sql = f"""
        DECLARE @query VECTOR({dimensions}) =
            AI_GENERATE_EMBEDDINGS(CAST(? AS NVARCHAR(MAX)) USE MODEL {model});

        SELECT TOP ({top})
            FeedbackId,
            Product,
            CustomerSegment,
            RiskLevel,
            FeedbackText,
            VECTOR_DISTANCE('cosine', @query, Embedding) AS distance
        FROM dbo.CustomerFeedback
        WHERE Embedding IS NOT NULL
          AND (? IS NULL OR CustomerSegment = ?)
          AND (? IS NULL OR RiskLevel = ?)
          AND (? IS NULL OR CreatedAt >= DATEADD(DAY, -?, SYSUTCDATETIME()))
        ORDER BY distance;
        """
    else:
        sql = f"""
        DECLARE @query VECTOR({dimensions}) =
            AI_GENERATE_EMBEDDINGS(CAST(? AS NVARCHAR(MAX)) USE MODEL {model});

        SELECT TOP ({top}) WITH APPROXIMATE
            f.FeedbackId,
            f.Product,
            f.CustomerSegment,
            f.RiskLevel,
            f.FeedbackText,
            r.distance
        FROM VECTOR_SEARCH(
                TABLE = dbo.CustomerFeedback AS f,
                COLUMN = Embedding,
                SIMILAR_TO = @query,
                METRIC = 'cosine'
             ) AS r
        WHERE (? IS NULL OR f.CustomerSegment = ?)
          AND (? IS NULL OR f.RiskLevel = ?)
          AND (? IS NULL OR f.CreatedAt >= DATEADD(DAY, -?, SYSUTCDATETIME()))
        ORDER BY r.distance;
        """

    params = (
        question,
        filters.segment,
        filters.segment,
        filters.risk,
        filters.risk,
        filters.days_back,
        filters.days_back,
    )

    print(f"\nSemantic search ({mode}): {question!r}\n")
    print_rows(conn.execute(sql, *params).fetchall())


def similar_cases(conn: pyodbc.Connection, feedback_id: int, top: int = 10) -> None:
    dimensions = int(os.getenv("SQLSERVER_VECTOR_DIMENSIONS", "1024"))
    top = max(1, min(top, 50))
    sql = f"""
    DECLARE @caseVector VECTOR({dimensions});

    SELECT @caseVector = Embedding
    FROM dbo.CustomerFeedback
    WHERE FeedbackId = ?;

    SELECT TOP ({top}) WITH APPROXIMATE
        f.FeedbackId,
        f.Product,
        f.CustomerSegment,
        f.RiskLevel,
        f.FeedbackText,
        r.distance
    FROM VECTOR_SEARCH(
            TABLE = dbo.CustomerFeedback AS f,
            COLUMN = Embedding,
            SIMILAR_TO = @caseVector,
            METRIC = 'cosine'
         ) AS r
    WHERE f.FeedbackId <> ?
    ORDER BY r.distance;
    """

    print(f"\nSimilar cases for FeedbackId={feedback_id}\n")
    print_rows(conn.execute(sql, feedback_id, feedback_id).fetchall())


def main() -> None:
    with connect() as conn:
        keyword_search(conn, "trừ tiền")
        semantic_search(conn, DEFAULT_QUESTION, SearchFilters(), top=10)
        semantic_search(
            conn,
            "khách hàng VIP gặp lỗi thanh toán nghiêm trọng",
            SearchFilters(segment="VIP", risk="Critical", days_back=7),
            top=10,
        )

        seed = conn.execute(
            """
            SELECT TOP (1) FeedbackId
            FROM dbo.CustomerFeedback
            WHERE SourceIssueGroup = N'Failed transaction but debited'
              AND RiskLevel = N'Critical'
              AND Embedding IS NOT NULL
            ORDER BY FeedbackId;
            """
        ).fetchval()

        if seed is not None:
            similar_cases(conn, int(seed), top=10)


if __name__ == "__main__":
    main()
