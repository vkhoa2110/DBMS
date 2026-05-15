:setvar DemoDatabase "CustomerAIDemo"

USE [$(DemoDatabase)];
GO

IF OBJECT_ID(N'dbo.CustomerFeedbackStage', N'U') IS NOT NULL
    DROP TABLE dbo.CustomerFeedbackStage;
GO

IF OBJECT_ID(N'dbo.CustomerFeedback', N'U') IS NOT NULL
    DROP TABLE dbo.CustomerFeedback;
GO

CREATE TABLE dbo.CustomerFeedback
(
    FeedbackId       INT IDENTITY(1,1) NOT NULL,
    MaskedCustomerId NVARCHAR(30)  NOT NULL,
    Product          NVARCHAR(100) NOT NULL,
    CustomerSegment  NVARCHAR(50)  NOT NULL,
    Region           NVARCHAR(50)  NOT NULL,
    Channel          NVARCHAR(50)  NULL,
    RiskLevel        NVARCHAR(20)  NULL,
    CreatedAt        DATETIME2(0)  NOT NULL,
    SourceIssueGroup NVARCHAR(80)  NOT NULL,
    FeedbackText     NVARCHAR(MAX) NOT NULL,
    Embedding        VECTOR(1024)  NULL,

    CONSTRAINT PK_CustomerFeedback
        PRIMARY KEY CLUSTERED (FeedbackId)
);
GO

CREATE INDEX IX_CustomerFeedback_BusinessFilters
ON dbo.CustomerFeedback
(
    CustomerSegment,
    RiskLevel,
    Product,
    CreatedAt
)
INCLUDE (Channel, Region, SourceIssueGroup);
GO

CREATE TABLE dbo.CustomerFeedbackStage
(
    MaskedCustomerId NVARCHAR(30)  NOT NULL,
    Product          NVARCHAR(100) NOT NULL,
    CustomerSegment  NVARCHAR(50)  NOT NULL,
    Region           NVARCHAR(50)  NOT NULL,
    Channel          NVARCHAR(50)  NULL,
    RiskLevel        NVARCHAR(20)  NULL,
    CreatedAt        NVARCHAR(40)  NOT NULL,
    SourceIssueGroup NVARCHAR(80)  NOT NULL,
    FeedbackText     NVARCHAR(MAX) NOT NULL
);
GO

