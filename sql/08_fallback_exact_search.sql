:setvar DemoDatabase "CustomerAIDemo"
:setvar EmbeddingModelName "LocalEmbeddingModel"

USE [$(DemoDatabase)];
GO

PRINT 'Exact vector search fallback. VECTOR_DISTANCE does not use vector index.';

DECLARE @query VECTOR(1024) =
    AI_GENERATE_EMBEDDINGS(
        N'app báo giao dịch thất bại nhưng tài khoản vẫn bị trừ tiền'
        USE MODEL $(EmbeddingModelName)
    );

SELECT TOP (10)
    FeedbackId,
    Product,
    CustomerSegment,
    RiskLevel,
    FeedbackText,
    VECTOR_DISTANCE('cosine', @query, Embedding) AS distance
FROM dbo.CustomerFeedback
WHERE Embedding IS NOT NULL
ORDER BY distance;
GO

DECLARE @vipQuery VECTOR(1024) =
    AI_GENERATE_EMBEDDINGS(
        N'khách hàng VIP gặp lỗi thanh toán nghiêm trọng'
        USE MODEL $(EmbeddingModelName)
    );

SELECT TOP (20)
    FeedbackId,
    Product,
    CustomerSegment,
    RiskLevel,
    Channel,
    CreatedAt,
    FeedbackText,
    VECTOR_DISTANCE('cosine', @vipQuery, Embedding) AS distance
FROM dbo.CustomerFeedback
WHERE Embedding IS NOT NULL
  AND CustomerSegment = N'VIP'
  AND RiskLevel IN (N'High', N'Critical')
ORDER BY distance;
GO

