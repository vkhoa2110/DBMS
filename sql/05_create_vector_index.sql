:setvar DemoDatabase "CustomerAIDemo"

USE [$(DemoDatabase)];
GO

ALTER DATABASE SCOPED CONFIGURATION
SET PREVIEW_FEATURES = ON;
GO

DECLARE @readyRows INT =
(
    SELECT COUNT(*)
    FROM dbo.CustomerFeedback
    WHERE Embedding IS NOT NULL
);

IF @readyRows < 100
BEGIN
    THROW 51000, 'Need at least 100 rows with non-null embeddings before creating the vector index.', 1;
END
GO

IF EXISTS
(
    SELECT 1
    FROM sys.indexes
    WHERE object_id = OBJECT_ID(N'dbo.CustomerFeedback')
      AND name = N'IX_CustomerFeedback_Embedding'
)
BEGIN
    DROP INDEX IX_CustomerFeedback_Embedding ON dbo.CustomerFeedback;
END
GO

CREATE VECTOR INDEX IX_CustomerFeedback_Embedding
ON dbo.CustomerFeedback (Embedding)
WITH
(
    METRIC = 'cosine',
    TYPE = 'DiskANN',
    MAXDOP = 4
);
GO

SELECT
    i.name AS index_name,
    i.type_desc,
    v.*
FROM sys.indexes AS i
LEFT JOIN sys.vector_indexes AS v
    ON v.object_id = i.object_id
   AND v.index_id = i.index_id
WHERE i.object_id = OBJECT_ID(N'dbo.CustomerFeedback')
  AND i.name = N'IX_CustomerFeedback_Embedding';
GO

