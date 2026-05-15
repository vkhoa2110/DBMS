from __future__ import annotations

import argparse
import json
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any


DEFAULT_SERVER = r".\SQLEXPRESS"
DEFAULT_DATABASE = "CustomerAIDemo2022"
DEFAULT_MODEL = "bge-m3"
DEFAULT_OLLAMA_URL = "http://127.0.0.1:11434/api/embed"


def run_sql(
    query: str | None = None,
    input_file: Path | None = None,
    *,
    server: str,
    database: str | None = None,
    variables: dict[str, str] | None = None,
) -> str:
    command = [
        "sqlcmd",
        "-S",
        server,
        "-E",
        "-b",
        "-f",
        "i:65001,o:65001",
        "-w",
        "65535",
        "-y",
        "0",
    ]
    if database:
        command += ["-d", database]
    if input_file:
        command += ["-i", str(input_file)]
    if query:
        command += ["-Q", "SET NOCOUNT ON;\n" + query]
    for key, value in (variables or {}).items():
        command += ["-v", f"{key}={value}"]

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
    return completed.stdout.strip()


def parse_sql_json(output: str) -> Any:
    output = output.strip()
    start = min((idx for idx in (output.find("["), output.find("{")) if idx != -1), default=-1)
    if start > 0:
        output = output[start:]
    output = output.replace("\r", "").replace("\n", "")
    return json.loads(output)


def fetch_feedback(server: str, database: str) -> list[dict[str, Any]]:
    output = run_sql(
        """
SELECT
    FeedbackId,
    FeedbackText
FROM dbo.CustomerFeedback
ORDER BY FeedbackId
FOR JSON PATH, INCLUDE_NULL_VALUES;
""",
        server=server,
        database=database,
    )
    return parse_sql_json(output)


def ollama_embed(texts: list[str], *, model: str, url: str) -> list[list[float]]:
    payload = json.dumps({"model": model, "input": texts}).encode("utf-8")
    request = urllib.request.Request(
        url,
        data=payload,
        headers={"Content-Type": "application/json"},
        method="POST",
    )

    try:
        with urllib.request.urlopen(request, timeout=300) as response:
            body = json.loads(response.read().decode("utf-8"))
    except urllib.error.URLError as exc:
        raise RuntimeError(
            f"Cannot connect to Ollama at {url}. Start Ollama and run: ollama pull {model}"
        ) from exc

    if "embeddings" in body:
        return body["embeddings"]
    if "embedding" in body:
        return [body["embedding"]]

    raise RuntimeError(f"Unexpected Ollama embedding response: {body}")


def sql_string(value: str) -> str:
    return "N'" + value.replace("'", "''") + "'"


def insert_embeddings(
    rows: list[dict[str, Any]],
    embeddings: list[list[float]],
    *,
    server: str,
    database: str,
    model: str,
    chunk_size: int,
) -> None:
    if not rows or not embeddings:
        raise RuntimeError("No embeddings to insert.")
    if len(rows) != len(embeddings):
        raise RuntimeError(f"Row count {len(rows)} does not match embedding count {len(embeddings)}.")

    dimension_count = len(embeddings[0])
    values: list[str] = []
    inserted = 0

    def flush() -> None:
        nonlocal values, inserted
        if not values:
            return
        query = "INSERT INTO dbo.RealFeedbackEmbedding (FeedbackId, DimensionIndex, Value) VALUES\n"
        query += ",\n".join(values) + ";"
        run_sql(query, server=server, database=database)
        inserted += len(values)
        print(f"Inserted {inserted:,} dimension rows", flush=True)
        values = []

    for row, embedding in zip(rows, embeddings):
        if len(embedding) != dimension_count:
            raise RuntimeError("Embedding dimension count changed between rows.")
        feedback_id = int(row["FeedbackId"])
        for index, value in enumerate(embedding):
            values.append(f"({feedback_id},{index},{float(value):.10g})")
            if len(values) >= chunk_size:
                flush()
    flush()

    metadata_query = f"""
INSERT INTO dbo.RealEmbeddingMetadata
(
    ModelName,
    DimensionCount,
    EmbeddingRowCount
)
VALUES
(
    {sql_string(model)},
    {dimension_count},
    {len(rows)}
);
"""
    run_sql(metadata_query, server=server, database=database)


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Generate real local embeddings with Ollama and store them in SQL Server 2022."
    )
    parser.add_argument("--server", default=DEFAULT_SERVER)
    parser.add_argument("--database", default=DEFAULT_DATABASE)
    parser.add_argument("--model", default=DEFAULT_MODEL)
    parser.add_argument("--ollama-url", default=DEFAULT_OLLAMA_URL)
    parser.add_argument("--batch-size", type=int, default=8)
    parser.add_argument("--insert-chunk-size", type=int, default=900)
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parents[1]
    schema_file = repo_root / "sql" / "real_embeddings_2022_schema.sql"

    print("Preparing SQL schema for real embeddings...")
    run_sql(
        input_file=schema_file,
        server=args.server,
        variables={"DemoDatabase": args.database},
    )

    feedback_rows = fetch_feedback(args.server, args.database)
    if not feedback_rows:
        raise RuntimeError("No feedback rows found. Run scripts/run_compat_2022_demo.ps1 first.")

    print(f"Embedding {len(feedback_rows)} feedback rows with Ollama model '{args.model}'...")
    all_embeddings: list[list[float]] = []
    start = time.time()

    for offset in range(0, len(feedback_rows), args.batch_size):
        batch = feedback_rows[offset : offset + args.batch_size]
        texts = [str(row["FeedbackText"]) for row in batch]
        batch_embeddings = ollama_embed(texts, model=args.model, url=args.ollama_url)
        all_embeddings.extend(batch_embeddings)
        print(f"Embedded {len(all_embeddings):,}/{len(feedback_rows):,} rows", flush=True)

    print("Writing embeddings to SQL Server...")
    insert_embeddings(
        feedback_rows,
        all_embeddings,
        server=args.server,
        database=args.database,
        model=args.model,
        chunk_size=args.insert_chunk_size,
    )

    elapsed = time.time() - start
    print(f"Done. Stored {len(all_embeddings):,} real embeddings in {elapsed:.1f}s.")


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        raise SystemExit(1)
