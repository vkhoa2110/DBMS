:setvar DemoDatabase "CustomerAIDemo"
:setvar CsvPath "D:\DSA\Demo_DBMS\data\customer_feedback.csv"

USE [$(DemoDatabase)];
GO

TRUNCATE TABLE dbo.CustomerFeedbackStage;
GO

-- Run in SQLCMD mode. The file path is read by the SQL Server service account,
-- not by SSMS/Azure Data Studio on the client machine.
BULK INSERT dbo.CustomerFeedbackStage
FROM '$(CsvPath)'
WITH
(
    FORMAT = 'CSV',
    FIRSTROW = 2,
    FIELDQUOTE = '"',
    CODEPAGE = '65001',
    ROWTERMINATOR = '0x0a',
    TABLOCK
);
GO

INSERT INTO dbo.CustomerFeedback
(
    MaskedCustomerId,
    Product,
    CustomerSegment,
    Region,
    Channel,
    RiskLevel,
    CreatedAt,
    SourceIssueGroup,
    FeedbackText
)
SELECT
    MaskedCustomerId,
    Product,
    CustomerSegment,
    Region,
    Channel,
    RiskLevel,
    CONVERT(DATETIME2(0), CreatedAt, 126),
    SourceIssueGroup,
    FeedbackText
FROM dbo.CustomerFeedbackStage;
GO

SELECT
    COUNT(*) AS imported_rows,
    MIN(CreatedAt) AS min_created_at,
    MAX(CreatedAt) AS max_created_at
FROM dbo.CustomerFeedback;
GO

