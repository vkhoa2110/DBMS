# SQL Server 2025 Native Vector Search Demo

Demo nay dung cau chuyen **AI helpdesk / risk triage cho du lieu khach hang nhay cam**. Muc tieu la cho thay keyword search bi sot, con SQL Server 2025 co the tim phan hoi tuong dong theo y nghia, van ket hop duoc filter nghiep vu quen thuoc nhu VIP, risk level, san pham, kenh va thoi gian.

## Kien truc demo

```text
Customer Feedback / CRM / Core Banking
                |
                v
        SQL Server 2025
  dbo.CustomerFeedback
  - FeedbackText
  - Product / Segment / RiskLevel
  - Embedding VECTOR(1024)
                ^
                |
   Local / Private Embedding Model
   Ollama bge-m3 / ONNX / internal endpoint

Analyst
   |
   v
T-SQL semantic search + business filters
```

Thong diep can nhan manh: du lieu goc, vector embedding, vector index va filter nghiep vu nam trong SQL Server. De dam bao "du lieu khong roi firewall", demo dang cau hinh SQL Server goi embedding model local/private qua `CREATE EXTERNAL MODEL`.

## Yeu cau

- SQL Server 2025 Preview hoac Azure SQL co ho tro vector search.
- `sqlcmd` de chay script.
- Ollama hoac mot internal embedding service chay trong mang noi bo/local neu demo embedding khep kin.
- SQL Server `CREATE EXTERNAL MODEL` yeu cau endpoint HTTPS/TLS. Script mac dinh dung `https://localhost:11435/api/embed`, nen voi Ollama local ban can expose qua TLS reverse proxy hoac dung mot internal HTTPS endpoint.
- Quyen admin tren SQL Server de bat `external rest endpoint enabled` lan dau.

```powershell
ollama pull bge-m3
ollama serve
```

`bge-m3` tra ve embedding 1024 chieu, nen schema dung `VECTOR(1024)`. Neu ban doi model, phai doi lai so chieu trong cac script SQL va code Python.

## Chay nhanh

1. Sinh du lieu demo bang generator:

```powershell
python .\tools\generate_feedback_csv.py --rows 10000 --output .\data\customer_feedback.csv
```

Neu Python tren may demo co van de, dung generator PowerShell:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\generate_feedback_csv.ps1 -Rows 10000 -Output .\data\customer_feedback.csv
```

2. Tao database, schema va import CSV. Duong dan CSV phai la duong dan SQL Server service account doc duoc:

```powershell
.\scripts\run_setup.ps1 -Server "localhost" -Database "CustomerAIDemo" -CsvPath "D:\DSA\Demo_DBMS\data\customer_feedback.csv"
```

Neu can cach chay nhanh khong phu thuoc CSV, dung seed T-SQL inline:

```powershell
.\scripts\run_setup_inline.ps1 -Server "localhost" -Database "CustomerAIDemo"
```

3. Dang ky local model, tao embeddings va vector index:

```powershell
sqlcmd -S localhost -d CustomerAIDemo -E -i .\sql\02_register_external_model_ollama.sql
sqlcmd -S localhost -d CustomerAIDemo -E -i .\sql\04_generate_embeddings.sql
sqlcmd -S localhost -d CustomerAIDemo -E -i .\sql\05_create_vector_index.sql
sqlcmd -S localhost -d CustomerAIDemo -E -i .\sql\07_stored_procedures.sql
```

4. Chay demo queries:

```powershell
sqlcmd -S localhost -d CustomerAIDemo -E -i .\sql\06_demo_queries.sql
```

Neu vector index hoac `VECTOR_SEARCH` bi loi do ban preview khac nhau, dung fallback exact search:

```powershell
sqlcmd -S localhost -d CustomerAIDemo -E -i .\sql\08_fallback_exact_search.sql
```

## Flow trinh dien 10-12 phut

1. **Keyword search bi sot**: chay phan A trong `sql/06_demo_queries.sql`.
2. **Semantic search**: nhap y tuong "khach hang bi tru tien du giao dich that bai"; SQL Server tra ve cac cau khac wording nhu "so du giam", "ghi no", "tien bi giu".
3. **AI search + filter nghiep vu**: loc `VIP`, `High/Critical`, 7 ngay gan day ngay trong T-SQL.
4. **Tu mot case nghiem trong tim case tuong tu**: lay embedding cua case da co va tim cum vu viec lien quan.
5. **Bao mat**: show `sys.external_models` de chung minh endpoint model la local/private.

## Tai lieu Microsoft da doi chieu

- Vector data type: `VECTOR(n)` luu embedding trong SQL Server va gioi han toi da 1998 dimensions.
- `CREATE VECTOR INDEX` tao approximate vector index tren cot vector, metric `cosine`, `dot`, `euclidean`, type `DiskANN`.
- `VECTOR_SEARCH` hien dung cu phap `SELECT TOP (N) WITH APPROXIMATE ... ORDER BY distance`.
- `VECTOR_DISTANCE` la exact search va khong dung vector index, phu hop lam fallback.
- `CREATE EXTERNAL MODEL` co vi du Ollama va ONNX Runtime local.

Tinh nang vector index / approximate search dang la preview, vi vay cu phap co the phu thuoc build SQL Server/Azure SQL ban dang dung.

## Fallback neu may chi co SQL Server 2022 Express

May local cua ban co the chi co `.\SQLEXPRESS`/`.\SQLEXPRESS01` tren SQL Server 2022. Ban van co the tap demo business flow bang fallback sau:

```powershell
.\scripts\run_compat_2022_demo.ps1 -Server ".\SQLEXPRESS" -Database "CustomerAIDemo2022"
```

Fallback nay khong dung `VECTOR`, `VECTOR_SEARCH`, `AI_GENERATE_EMBEDDINGS` hay `CREATE VECTOR INDEX`. No gia lap vector similarity bang bang quan he `dbo.FeedbackEmbedding` va cosine similarity trong T-SQL, de ban co ket qua keyword search bi sot, semantic-like search, filter VIP/risk va find similar cases tren SQL Server 2022.

Khi thuyet trinh, noi ro: "Ban local fallback nay chi de tap va minh hoa logic. Ban Native Vector Search dung cac script `00` den `08` va can SQL Server 2025/Azure SQL."

### Chay UI demo

Sau khi chay fallback seed o tren, mo UI:

```powershell
py -3 .\ui\server.py
```

Mac dinh UI ket noi `.\SQLEXPRESS` va database `CustomerAIDemo2022`. Neu dung instance/database khac:

```powershell
$env:HELPDESK_SQL_SERVER=".\SQLEXPRESS01"
$env:HELPDESK_SQL_DATABASE="CustomerAIDemo2022"
py -3 .\ui\server.py
```

Sau do mo: `http://127.0.0.1:8080`.

### Chay semantic embedding that bang Ollama tren SQL Server 2022

Neu muon test "that" tren may chi co SQL Server 2022, dung pipeline nay:

1. Cai Ollama:

```powershell
winget install Ollama.Ollama
```

Mo terminal moi sau khi cai xong, roi pull embedding model:

```powershell
ollama pull bge-m3
```

2. Reset du lieu demo:

```powershell
.\scripts\run_compat_2022_demo.ps1 -Server ".\SQLEXPRESS" -Database "CustomerAIDemo2022"
```

3. Sinh embedding that bang model local va luu vao SQL Server:

```powershell
.\scripts\build_real_embeddings_ollama.ps1 -Server ".\SQLEXPRESS" -Database "CustomerAIDemo2022" -Model "bge-m3"
```

Script nay goi Ollama local `http://127.0.0.1:11434/api/embed`, sinh vector `bge-m3` that cho tung feedback, va luu vao `dbo.RealFeedbackEmbedding` trong SQL Server 2022.

4. Chay UI o real mode:

```powershell
$env:HELPDESK_EMBEDDING_MODE="real"
$env:HELPDESK_OLLAMA_MODEL="bge-m3"
$env:HELPDESK_UI_PORT="8081"
py -3 .\ui\server.py
```

Mo: `http://127.0.0.1:8081`.

Gio UI se hien profile `real_ollama:bge-m3` khi search. Day la embedding that tu local model, nhung van chua phai Native Vector Search cua SQL Server 2025. SQL Server 2022 dang luu vector theo bang quan he `(FeedbackId, DimensionIndex, Value)` va tinh cosine bang T-SQL. Ban Native SQL Server 2025 se dung `VECTOR`, `CREATE VECTOR INDEX` va `VECTOR_SEARCH`.
