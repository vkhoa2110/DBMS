:setvar DemoDatabase "CustomerAIDemo2022"

USE [$(DemoDatabase)];
GO

IF OBJECT_ID(N'dbo.RealFeedbackEmbedding', N'U') IS NOT NULL
    DROP TABLE dbo.RealFeedbackEmbedding;
GO

IF OBJECT_ID(N'dbo.RealEmbeddingMetadata', N'U') IS NOT NULL
    DROP TABLE dbo.RealEmbeddingMetadata;
GO

CREATE TABLE dbo.RealEmbeddingMetadata
(
    ModelName      NVARCHAR(200) NOT NULL,
    DimensionCount INT NOT NULL,
    CreatedAt      DATETIME2(0) NOT NULL DEFAULT SYSUTCDATETIME(),
    EmbeddingRowCount INT NOT NULL,

    CONSTRAINT PK_RealEmbeddingMetadata
        PRIMARY KEY CLUSTERED (ModelName)
);
GO

CREATE TABLE dbo.RealFeedbackEmbedding
(
    FeedbackId     INT NOT NULL,
    DimensionIndex INT NOT NULL,
    Value          FLOAT NOT NULL,

    CONSTRAINT PK_RealFeedbackEmbedding
        PRIMARY KEY CLUSTERED (FeedbackId, DimensionIndex),
    CONSTRAINT FK_RealFeedbackEmbedding_CustomerFeedback
        FOREIGN KEY (FeedbackId)
        REFERENCES dbo.CustomerFeedback (FeedbackId)
);
GO

CREATE INDEX IX_RealFeedbackEmbedding_Dimension
ON dbo.RealFeedbackEmbedding (DimensionIndex, FeedbackId)
INCLUDE (Value);
GO
