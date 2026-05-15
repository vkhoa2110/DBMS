:setvar DemoDatabase "CustomerAIDemo"
:setvar EmbeddingModelName "LocalEmbeddingModel"

USE [$(DemoDatabase)];
GO

DECLARE @batchSize INT = 250;
DECLARE @rows INT = 1;

WHILE @rows > 0
BEGIN
    ;WITH Batch AS
    (
        SELECT TOP (@batchSize)
            FeedbackId,
            FeedbackText
        FROM dbo.CustomerFeedback
        WHERE Embedding IS NULL
        ORDER BY FeedbackId
    )
    UPDATE f
    SET Embedding = AI_GENERATE_EMBEDDINGS(f.FeedbackText USE MODEL $(EmbeddingModelName))
    FROM dbo.CustomerFeedback AS f
    INNER JOIN Batch AS b
        ON b.FeedbackId = f.FeedbackId;

    SET @rows = @@ROWCOUNT;

    RAISERROR('Generated embeddings for %d rows in this batch.', 0, 1, @rows) WITH NOWAIT;
END
GO

SELECT
    COUNT(*) AS total_rows,
    SUM(CASE WHEN Embedding IS NOT NULL THEN 1 ELSE 0 END) AS rows_with_embedding
FROM dbo.CustomerFeedback;
GO

