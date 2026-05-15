:setvar DemoDatabase "CustomerAIDemo"
:setvar EmbeddingModelName "LocalEmbeddingModel"

USE [$(DemoDatabase)];
GO

CREATE OR ALTER PROCEDURE dbo.usp_LegacyKeywordSearch
    @Keyword NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT TOP (20)
        FeedbackId,
        Product,
        CustomerSegment,
        RiskLevel,
        Channel,
        CreatedAt,
        FeedbackText
    FROM dbo.CustomerFeedback
    WHERE FeedbackText LIKE N'%' + @Keyword + N'%'
    ORDER BY CreatedAt DESC;
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_SemanticRiskSearch
    @Question NVARCHAR(MAX),
    @CustomerSegment NVARCHAR(50) = NULL,
    @RiskLevel NVARCHAR(20) = NULL,
    @DaysBack INT = 30
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @query VECTOR(1024) =
        AI_GENERATE_EMBEDDINGS(@Question USE MODEL $(EmbeddingModelName));

    SELECT TOP (20) WITH APPROXIMATE
        f.FeedbackId,
        f.Product,
        f.CustomerSegment,
        f.RiskLevel,
        f.Channel,
        f.CreatedAt,
        f.FeedbackText,
        r.distance
    FROM VECTOR_SEARCH(
            TABLE = dbo.CustomerFeedback AS f,
            COLUMN = Embedding,
            SIMILAR_TO = @query,
            METRIC = 'cosine'
         ) AS r
    WHERE (@CustomerSegment IS NULL OR f.CustomerSegment = @CustomerSegment)
      AND (@RiskLevel IS NULL OR f.RiskLevel = @RiskLevel)
      AND (@DaysBack IS NULL OR f.CreatedAt >= DATEADD(DAY, -@DaysBack, SYSUTCDATETIME()))
    ORDER BY r.distance;
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_FindSimilarCases
    @FeedbackId INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @caseVector VECTOR(1024);

    SELECT @caseVector = Embedding
    FROM dbo.CustomerFeedback
    WHERE FeedbackId = @FeedbackId;

    IF @caseVector IS NULL
    BEGIN
        THROW 51001, 'FeedbackId not found or embedding is null.', 1;
    END

    SELECT TOP (25) WITH APPROXIMATE
        f.FeedbackId,
        f.Product,
        f.CustomerSegment,
        f.RiskLevel,
        f.CreatedAt,
        f.FeedbackText,
        r.distance
    FROM VECTOR_SEARCH(
            TABLE = dbo.CustomerFeedback AS f,
            COLUMN = Embedding,
            SIMILAR_TO = @caseVector,
            METRIC = 'cosine'
         ) AS r
    WHERE f.FeedbackId <> @FeedbackId
    ORDER BY r.distance;
END
GO

