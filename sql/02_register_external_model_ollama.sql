:setvar DemoDatabase "CustomerAIDemo"
:setvar EmbeddingModelName "LocalEmbeddingModel"
:setvar OllamaEndpoint "https://localhost:11435/api/embed"
:setvar OllamaModel "bge-m3"

USE [$(DemoDatabase)];
GO

EXECUTE sp_configure 'show advanced options', 1;
RECONFIGURE WITH OVERRIDE;
EXECUTE sp_configure 'external rest endpoint enabled', 1;
RECONFIGURE WITH OVERRIDE;
GO

IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'AI_User')
BEGIN
    CREATE USER AI_User WITHOUT LOGIN;
END
GO

IF EXISTS (SELECT 1 FROM sys.external_models WHERE name = N'$(EmbeddingModelName)')
BEGIN
    DROP EXTERNAL MODEL $(EmbeddingModelName);
END
GO

-- Local/private embedding endpoint. Keep this inside the enterprise network for
-- the "data does not leave the firewall" security message.
CREATE EXTERNAL MODEL $(EmbeddingModelName)
AUTHORIZATION AI_User
WITH
(
    LOCATION = '$(OllamaEndpoint)',
    API_FORMAT = 'Ollama',
    MODEL_TYPE = EMBEDDINGS,
    MODEL = '$(OllamaModel)'
);
GO

-- Demo convenience only. In production, grant this to a least-privilege
-- analyst/app role instead of PUBLIC.
GRANT EXECUTE ON EXTERNAL MODEL::$(EmbeddingModelName) TO PUBLIC;
GO

SELECT
    name,
    location,
    api_format,
    model_type,
    model
FROM sys.external_models
WHERE name = N'$(EmbeddingModelName)';
GO

SELECT AI_GENERATE_EMBEDDINGS(N'kiem tra model embedding noi bo' USE MODEL $(EmbeddingModelName)) AS sample_embedding;
GO
