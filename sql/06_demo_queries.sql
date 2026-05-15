:setvar DemoDatabase "CustomerAIDemo"
:setvar EmbeddingModelName "LocalEmbeddingModel"

USE [$(DemoDatabase)];
GO

PRINT 'A1. Latest customer feedback rows';
SELECT TOP (10)
    FeedbackId,
    Product,
    CustomerSegment,
    RiskLevel,
    FeedbackText,
    CreatedAt
FROM dbo.CustomerFeedback
ORDER BY CreatedAt DESC;
GO

PRINT 'A2. Legacy keyword search: this misses "ghi no", "so du giam", "tien bi giu"';
SELECT TOP (10)
    FeedbackId,
    Product,
    RiskLevel,
    FeedbackText
FROM dbo.CustomerFeedback
WHERE FeedbackText LIKE N'%trừ tiền%'
   OR FeedbackText LIKE N'%hoàn tiền%'
   OR FeedbackText LIKE N'%giao dịch lỗi%'
ORDER BY CreatedAt DESC;
GO

PRINT 'B. Semantic search: same intent, different wording';
DECLARE @query VECTOR(1024) =
    AI_GENERATE_EMBEDDINGS(
        N'app báo giao dịch thất bại nhưng tài khoản vẫn bị trừ tiền'
        USE MODEL $(EmbeddingModelName)
    );

SELECT TOP (10) WITH APPROXIMATE
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
ORDER BY r.distance;
GO

PRINT 'C. Semantic search plus business filters: VIP + High/Critical + last 7 days';
DECLARE @query VECTOR(1024) =
    AI_GENERATE_EMBEDDINGS(
        N'khách hàng VIP gặp lỗi thanh toán nghiêm trọng'
        USE MODEL $(EmbeddingModelName)
    );

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
WHERE f.CustomerSegment = N'VIP'
  AND f.RiskLevel IN (N'High', N'Critical')
  AND f.CreatedAt >= DATEADD(DAY, -7, SYSUTCDATETIME())
ORDER BY r.distance;
GO

PRINT 'D. From one serious case, find similar cases';
DECLARE @caseId INT =
(
    SELECT TOP (1) FeedbackId
    FROM dbo.CustomerFeedback
    WHERE SourceIssueGroup = N'Failed transaction but debited'
      AND RiskLevel = N'Critical'
      AND Embedding IS NOT NULL
    ORDER BY FeedbackId
);

DECLARE @caseVector VECTOR(1024);

SELECT @caseVector = Embedding
FROM dbo.CustomerFeedback
WHERE FeedbackId = @caseId;

SELECT
    @caseId AS seed_feedback_id,
    FeedbackText AS seed_feedback_text
FROM dbo.CustomerFeedback
WHERE FeedbackId = @caseId;

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
WHERE f.FeedbackId <> @caseId
ORDER BY r.distance;
GO

PRINT 'E. Risk triage summary from top semantic hits';
DECLARE @query VECTOR(1024) =
    AI_GENERATE_EMBEDDINGS(
        N'giao dịch thanh toán bị lỗi nhưng tiền của khách hàng bị giữ hoặc bị ghi nợ'
        USE MODEL $(EmbeddingModelName)
    );

SELECT
    Product,
    RiskLevel,
    COUNT(*) AS hit_count,
    MIN(distance) AS closest_distance,
    AVG(distance) AS avg_distance
FROM
(
    SELECT TOP (100) WITH APPROXIMATE
        f.FeedbackId,
        f.Product,
        f.RiskLevel,
        r.distance
    FROM VECTOR_SEARCH(
            TABLE = dbo.CustomerFeedback AS f,
            COLUMN = Embedding,
            SIMILAR_TO = @query,
            METRIC = 'cosine'
         ) AS r
    ORDER BY r.distance
) AS hits
GROUP BY Product, RiskLevel
ORDER BY closest_distance;
GO

PRINT 'F. Security check: embedding model registered inside SQL Server';
SELECT
    name,
    location,
    api_format,
    model_type,
    model
FROM sys.external_models;
GO

