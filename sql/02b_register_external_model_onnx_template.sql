:setvar DemoDatabase "CustomerAIDemo"
:setvar EmbeddingModelName "LocalOnnxEmbeddingModel"

USE [$(DemoDatabase)];
GO

EXECUTE sp_configure 'show advanced options', 1;
RECONFIGURE WITH OVERRIDE;
EXECUTE sp_configure 'external AI runtimes enabled', 1;
RECONFIGURE WITH OVERRIDE;
GO

/*
Template neu giang vien/hoi dong yeu cau ONNX Runtime local thay vi Ollama.

Luu y:
- Vi du nay dung all-MiniLM-L6-v2, thuong tra ve 384 dimensions.
- Neu dung script nay, doi cot Embedding thanh VECTOR(384) trong sql/01_schema.sql,
  va doi cac bien VECTOR(1024) trong demo queries/procedures thanh VECTOR(384).
- Can SQL Server Machine Learning Services va duong dan runtime/model hop le.
*/

IF EXISTS (SELECT 1 FROM sys.external_models WHERE name = N'$(EmbeddingModelName)')
BEGIN
    DROP EXTERNAL MODEL $(EmbeddingModelName);
END
GO

CREATE EXTERNAL MODEL $(EmbeddingModelName)
WITH
(
    LOCATION = 'C:\onnx_runtime\model\all-MiniLM-L6-v2-onnx',
    API_FORMAT = 'ONNX Runtime',
    MODEL_TYPE = EMBEDDINGS,
    MODEL = 'allMiniLM',
    PARAMETERS = '{"valid":"JSON"}',
    LOCAL_RUNTIME_PATH = 'C:\onnx_runtime\'
);
GO

SELECT AI_GENERATE_EMBEDDINGS(N'Test Text' USE MODEL $(EmbeddingModelName)) AS sample_embedding;
GO
