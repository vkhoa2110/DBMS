:setvar DemoDatabase "CustomerAIDemo2022"

IF DB_ID(N'$(DemoDatabase)') IS NULL
BEGIN
    EXEC(N'CREATE DATABASE [$(DemoDatabase)]');
END
GO

USE [$(DemoDatabase)];
GO

IF OBJECT_ID(N'dbo.RealFeedbackEmbedding', N'U') IS NOT NULL
    DROP TABLE dbo.RealFeedbackEmbedding;
GO

IF OBJECT_ID(N'dbo.RealEmbeddingMetadata', N'U') IS NOT NULL
    DROP TABLE dbo.RealEmbeddingMetadata;
GO

IF OBJECT_ID(N'dbo.FeedbackEmbedding', N'U') IS NOT NULL
    DROP TABLE dbo.FeedbackEmbedding;
GO

IF OBJECT_ID(N'dbo.CustomerFeedback', N'U') IS NOT NULL
    DROP TABLE dbo.CustomerFeedback;
GO

IF OBJECT_ID(N'dbo.QueryEmbedding', N'U') IS NOT NULL
    DROP TABLE dbo.QueryEmbedding;
GO

CREATE TABLE dbo.CustomerFeedback
(
    FeedbackId       INT IDENTITY(1,1) NOT NULL
        CONSTRAINT PK_CustomerFeedback PRIMARY KEY CLUSTERED,
    MaskedCustomerId NVARCHAR(30)  NOT NULL,
    Product          NVARCHAR(100) NOT NULL,
    CustomerSegment  NVARCHAR(50)  NOT NULL,
    Region           NVARCHAR(50)  NOT NULL,
    Channel          NVARCHAR(50)  NULL,
    RiskLevel        NVARCHAR(20)  NULL,
    CreatedAt        DATETIME2(0)  NOT NULL,
    SourceIssueGroup NVARCHAR(80)  NOT NULL,
    FeedbackText     NVARCHAR(MAX) NOT NULL
);
GO

CREATE TABLE dbo.FeedbackEmbedding
(
    FeedbackId     INT NOT NULL,
    DimensionName  NVARCHAR(40) NOT NULL,
    Value          FLOAT NOT NULL,

    CONSTRAINT PK_FeedbackEmbedding
        PRIMARY KEY CLUSTERED (FeedbackId, DimensionName),
    CONSTRAINT FK_FeedbackEmbedding_CustomerFeedback
        FOREIGN KEY (FeedbackId)
        REFERENCES dbo.CustomerFeedback (FeedbackId)
);
GO

CREATE TABLE dbo.QueryEmbedding
(
    QueryName      SYSNAME NOT NULL,
    DimensionName  NVARCHAR(40) NOT NULL,
    Value          FLOAT NOT NULL,

    CONSTRAINT PK_QueryEmbedding
        PRIMARY KEY CLUSTERED (QueryName, DimensionName)
);
GO

;WITH Templates AS
(
    SELECT *
    FROM
    (
        VALUES
            (1,  N'Mobile Banking',   N'Failed transaction but debited',       N'Critical', N'App báo giao dịch thất bại sau OTP nhưng tài khoản vẫn bị trừ tiền.'),
            (2,  N'E-Wallet',         N'Failed transaction but debited',       N'High',     N'Thanh toán lỗi nhưng số dư trong ví vẫn giảm.'),
            (3,  N'Internet Banking', N'Failed transaction but debited',       N'Critical', N'Đơn hàng không thành công, tiền chưa được hoàn về tài khoản.'),
            (4,  N'Debit Card',       N'Failed transaction but debited',       N'High',     N'Giao dịch bị treo sau khi xác thực, tài khoản đã ghi nợ.'),
            (5,  N'Mobile Banking',   N'Failed transaction but debited',       N'High',     N'App báo timeout nhưng tiền trong tài khoản bị giữ.'),
            (6,  N'Internet Banking', N'Failed transaction but debited',       N'High',     N'Chuyển khoản thất bại nhưng số dư tài khoản của tôi bị giảm.'),

            (7,  N'Mobile Banking',   N'OTP or authentication failure',        N'Medium',   N'Tôi không nhận được OTP nên không thể xác nhận giao dịch.'),
            (8,  N'Internet Banking', N'OTP or authentication failure',        N'Medium',   N'Mã OTP gửi quá chậm, hết hạn trước khi nhập.'),
            (9,  N'Credit Card',      N'OTP or authentication failure',        N'High',     N'Tôi nhập OTP đúng nhưng hệ thống báo sai mã.'),

            (10, N'Mobile Banking',   N'App slow or crash',                    N'Low',      N'Ứng dụng mở rất chậm và thường bị treo ở màn hình đăng nhập.'),
            (11, N'E-Wallet',         N'App slow or crash',                    N'Medium',   N'App tự thoát khi tôi kiểm tra lịch sử giao dịch.'),
            (12, N'Internet Banking', N'App slow or crash',                    N'Low',      N'Màn hình chuyển tiền quay vòng rất lâu không có phản hồi.'),

            (13, N'Credit Card',      N'Wrong or duplicated fee',              N'High',     N'Tài khoản bị tính phí hai lần cho cùng một giao dịch.'),
            (14, N'Current Account',  N'Wrong or duplicated fee',              N'Medium',   N'Hệ thống thu phí chuyển khoản dù gói tài khoản của tôi miễn phí.'),
            (15, N'Loan',             N'Wrong or duplicated fee',              N'Medium',   N'Khoản phí phạt trả chậm bị ghi nhận sai ngày.'),

            (16, N'Loan',             N'Loan rejected unclear reason',         N'Medium',   N'Hồ sơ vay bị từ chối nhưng tôi không biết thiếu giấy tờ gì.'),
            (17, N'Credit Card',      N'Loan rejected unclear reason',         N'Low',      N'Kết quả phê duyệt thẻ tín dụng không có giải thích cụ thể.'),
            (18, N'Loan',             N'Loan rejected unclear reason',         N'Medium',   N'Ứng dụng báo khoản vay không được duyệt mà không nêu lý do.'),

            (19, N'Credit Card',      N'Card blocked or payment declined',     N'High',     N'Thẻ của tôi bị khóa khi thanh toán ở cửa hàng.'),
            (20, N'Debit Card',       N'Card blocked or payment declined',     N'Medium',   N'Giao dịch quẹt thẻ bị từ chối dù hạn mức vẫn còn.'),
            (21, N'Credit Card',      N'Card blocked or payment declined',     N'Medium',   N'Thanh toán quốc tế bị decline dù tôi đã bật tính năng này.'),

            (22, N'Current Account',  N'Customer service complaint',           N'Low',      N'Tổng đài để tôi chờ quá lâu nhưng chưa giải quyết được vấn đề.'),
            (23, N'Loan',             N'Customer service complaint',           N'Medium',   N'Nhân viên hứa gọi lại nhưng tôi không nhận được phản hồi.'),
            (24, N'Mobile Banking',   N'Customer service complaint',           N'Low',      N'Chatbot không chuyển tôi sang nhân viên khi sự cố nghiêm trọng.'),

            (25, N'Credit Card',      N'Suspicious or fraudulent transaction', N'Critical', N'Tôi thấy giao dịch lạ không phải do tôi thực hiện.'),
            (26, N'Debit Card',       N'Suspicious or fraudulent transaction', N'Critical', N'Có khoản thanh toán online đáng ngờ xuất hiện trong sao kê.'),
            (27, N'E-Wallet',         N'Suspicious or fraudulent transaction', N'High',     N'Ví điện tử bị trừ tiền cho đơn hàng tôi không đặt.')
    ) AS t(SortOrder, Product, SourceIssueGroup, RiskLevel, FeedbackText)
),
Copies AS
(
    SELECT *
    FROM (VALUES (1), (2), (3), (4), (5), (6)) AS c(CopyNo)
),
Expanded AS
(
    SELECT
        ROW_NUMBER() OVER (ORDER BY t.SortOrder, c.CopyNo) AS RowNo,
        t.Product,
        CASE c.CopyNo
            WHEN 1 THEN N'VIP'
            WHEN 2 THEN N'Premier'
            WHEN 3 THEN N'SME'
            WHEN 4 THEN N'Mass'
            WHEN 5 THEN N'VIP'
            ELSE N'Mass'
        END AS CustomerSegment,
        CHOOSE(((t.SortOrder + c.CopyNo) % 6) + 1,
            N'Ho Chi Minh', N'Ha Noi', N'Da Nang', N'Can Tho', N'Hai Phong', N'Binh Duong') AS Region,
        CHOOSE(((t.SortOrder * c.CopyNo) % 6) + 1,
            N'App', N'Web', N'Call Center', N'Branch', N'Email', N'Chatbot') AS Channel,
        CASE
            WHEN c.CopyNo IN (1, 5)
             AND t.SourceIssueGroup IN (N'Failed transaction but debited', N'Suspicious or fraudulent transaction')
                THEN N'Critical'
            ELSE t.RiskLevel
        END AS RiskLevel,
        DATEADD(HOUR, -(t.SortOrder * 7 + c.CopyNo), SYSUTCDATETIME()) AS CreatedAt,
        t.SourceIssueGroup,
        CONCAT(
            t.FeedbackText,
            CASE c.CopyNo
                WHEN 1 THEN N''
                WHEN 2 THEN N' Tôi đã gọi tổng đài nhưng chưa được xử lý.'
                WHEN 3 THEN N' Vấn đề xảy ra trong giờ cao điểm.'
                WHEN 4 THEN N' Mong ngân hàng kiểm tra lại giao dịch này.'
                WHEN 5 THEN N' Đây là khách hàng ưu tiên nên cần xử lý gấp.'
                ELSE N' Tôi cần phản hồi rõ ràng bằng văn bản.'
            END
        ) AS FeedbackText
    FROM Templates AS t
    CROSS JOIN Copies AS c
)
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
    CONCAT(N'CUST-', RIGHT(CONCAT(N'000000', RowNo), 6)),
    Product,
    CustomerSegment,
    Region,
    Channel,
    RiskLevel,
    CreatedAt,
    SourceIssueGroup,
    FeedbackText
FROM Expanded;
GO

;WITH IssueVector AS
(
    SELECT *
    FROM
    (
        VALUES
            (N'Failed transaction but debited',       N'payment_failure', 0.72),
            (N'Failed transaction but debited',       N'debited_balance', 0.78),
            (N'Failed transaction but debited',       N'refund_pending',  0.46),
            (N'Failed transaction but debited',       N'urgent_risk',     0.52),

            (N'OTP or authentication failure',        N'authentication',  1.00),
            (N'OTP or authentication failure',        N'payment_failure', 0.25),
            (N'OTP or authentication failure',        N'urgent_risk',     0.35),

            (N'App slow or crash',                    N'app_stability',   1.00),
            (N'App slow or crash',                    N'payment_failure', 0.15),

            (N'Wrong or duplicated fee',              N'fee_dispute',     1.00),
            (N'Wrong or duplicated fee',              N'debited_balance', 0.40),
            (N'Wrong or duplicated fee',              N'refund_pending',  0.35),

            (N'Loan rejected unclear reason',         N'loan_rejection',  1.00),
            (N'Loan rejected unclear reason',         N'service_quality', 0.25),

            (N'Card blocked or payment declined',     N'card_blocked',    1.00),
            (N'Card blocked or payment declined',     N'payment_failure', 0.65),
            (N'Card blocked or payment declined',     N'urgent_risk',     0.45),

            (N'Customer service complaint',           N'service_quality', 1.00),
            (N'Customer service complaint',           N'urgent_risk',     0.20),

            (N'Suspicious or fraudulent transaction', N'fraud_suspicion', 1.00),
            (N'Suspicious or fraudulent transaction', N'debited_balance', 0.55),
            (N'Suspicious or fraudulent transaction', N'urgent_risk',     0.95)
    ) AS v(SourceIssueGroup, DimensionName, Value)
)
INSERT INTO dbo.FeedbackEmbedding
(
    FeedbackId,
    DimensionName,
    Value
)
SELECT
    f.FeedbackId,
    v.DimensionName,
    v.Value
FROM dbo.CustomerFeedback AS f
INNER JOIN IssueVector AS v
    ON v.SourceIssueGroup = f.SourceIssueGroup;
GO

-- Fine-grained text features make the fallback behave more like real
-- embeddings: same issue group stays close, but different wording no longer
-- receives exactly the same score.
;WITH FeatureVector AS
(
    SELECT
        f.FeedbackId,
        features.DimensionName,
        features.Value
    FROM dbo.CustomerFeedback AS f
    CROSS APPLY
    (
        VALUES
            (N'account_debited',
                CASE WHEN f.FeedbackText LIKE N'%trừ tiền%'
                       OR f.FeedbackText LIKE N'%ghi nợ%'
                       OR f.FeedbackText LIKE N'%bị giảm%'
                     THEN 0.88 END),
            (N'balance_drop',
                CASE WHEN f.FeedbackText LIKE N'%số dư%'
                       OR f.FeedbackText LIKE N'%vẫn giảm%'
                     THEN 0.82 END),
            (N'refund_mention',
                CASE WHEN f.FeedbackText LIKE N'%hoàn%'
                     THEN 0.74 END),
            (N'held_money',
                CASE WHEN f.FeedbackText LIKE N'%bị giữ%'
                       OR f.FeedbackText LIKE N'%bị treo%'
                     THEN 0.68 END),
            (N'order_failed',
                CASE WHEN f.FeedbackText LIKE N'%Đơn hàng%'
                       OR f.FeedbackText LIKE N'%đơn hàng%'
                     THEN 0.58 END),
            (N'auth_after_otp',
                CASE WHEN f.FeedbackText LIKE N'%OTP%'
                       OR f.FeedbackText LIKE N'%xác thực%'
                     THEN 0.48 END),
            (N'vip_priority',
                CASE WHEN f.CustomerSegment = N'VIP'
                       OR f.FeedbackText LIKE N'%ưu tiên%'
                     THEN 0.45 END),
            (N'customer_followup',
                CASE WHEN f.FeedbackText LIKE N'%tổng đài%'
                       OR f.FeedbackText LIKE N'%phản hồi rõ ràng%'
                     THEN 0.30 END),
            (N'peak_time',
                CASE WHEN f.FeedbackText LIKE N'%giờ cao điểm%'
                     THEN 0.24 END)
    ) AS features(DimensionName, Value)
    WHERE features.Value IS NOT NULL
)
INSERT INTO dbo.FeedbackEmbedding
(
    FeedbackId,
    DimensionName,
    Value
)
SELECT
    FeedbackId,
    DimensionName,
    Value
FROM FeatureVector;
GO

INSERT INTO dbo.QueryEmbedding
(
    QueryName,
    DimensionName,
    Value
)
VALUES
    (N'debited_failed_transaction', N'payment_failure', 0.92),
    (N'debited_failed_transaction', N'debited_balance', 0.96),
    (N'debited_failed_transaction', N'refund_pending',  0.52),
    (N'debited_failed_transaction', N'urgent_risk',     0.58),
    (N'debited_failed_transaction', N'account_debited', 0.86),
    (N'debited_failed_transaction', N'balance_drop',    0.76),
    (N'debited_failed_transaction', N'refund_mention',  0.62),
    (N'debited_failed_transaction', N'held_money',      0.55),
    (N'debited_failed_transaction', N'order_failed',    0.42),
    (N'debited_failed_transaction', N'auth_after_otp',  0.35),

    (N'vip_serious_payment_issue', N'payment_failure', 0.95),
    (N'vip_serious_payment_issue', N'debited_balance', 0.85),
    (N'vip_serious_payment_issue', N'urgent_risk',     1.00),
    (N'vip_serious_payment_issue', N'account_debited', 0.70),
    (N'vip_serious_payment_issue', N'balance_drop',    0.55),
    (N'vip_serious_payment_issue', N'vip_priority',    0.80),

    (N'suspicious_money_movement', N'fraud_suspicion', 1.00),
    (N'suspicious_money_movement', N'debited_balance', 0.65),
    (N'suspicious_money_movement', N'urgent_risk',     0.90),
    (N'suspicious_money_movement', N'account_debited', 0.35);
GO

CREATE OR ALTER PROCEDURE dbo.usp_KeywordSearch
    @Keyword NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT TOP (10)
        FeedbackId,
        Product,
        CustomerSegment,
        RiskLevel,
        FeedbackText
    FROM dbo.CustomerFeedback
    WHERE FeedbackText LIKE N'%' + @Keyword + N'%'
    ORDER BY CreatedAt DESC;
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_SemanticSearch2022
    @QueryName SYSNAME,
    @CustomerSegment NVARCHAR(50) = NULL,
    @RiskLevel NVARCHAR(20) = NULL,
    @DaysBack INT = 30,
    @Top INT = 10
AS
BEGIN
    SET NOCOUNT ON;

    ;WITH QueryNorm AS
    (
        SELECT SQRT(SUM(Value * Value)) AS Norm
        FROM dbo.QueryEmbedding
        WHERE QueryName = @QueryName
    ),
    FeedbackNorm AS
    (
        SELECT
            FeedbackId,
            SQRT(SUM(Value * Value)) AS Norm
        FROM dbo.FeedbackEmbedding
        GROUP BY FeedbackId
    ),
    DotProduct AS
    (
        SELECT
            fe.FeedbackId,
            SUM(fe.Value * qe.Value) AS DotValue
        FROM dbo.FeedbackEmbedding AS fe
        INNER JOIN dbo.QueryEmbedding AS qe
            ON qe.DimensionName = fe.DimensionName
           AND qe.QueryName = @QueryName
        GROUP BY fe.FeedbackId
    ),
    Scored AS
    (
        SELECT
            f.FeedbackId,
            f.Product,
            f.CustomerSegment,
            f.RiskLevel,
            f.Channel,
            f.CreatedAt,
            f.FeedbackText,
            CAST(dp.DotValue / NULLIF(fn.Norm * qn.Norm, 0) AS DECIMAL(10, 4)) AS similarity
        FROM DotProduct AS dp
        INNER JOIN FeedbackNorm AS fn
            ON fn.FeedbackId = dp.FeedbackId
        CROSS JOIN QueryNorm AS qn
        INNER JOIN dbo.CustomerFeedback AS f
            ON f.FeedbackId = dp.FeedbackId
        WHERE (@CustomerSegment IS NULL OR f.CustomerSegment = @CustomerSegment)
          AND (@RiskLevel IS NULL OR f.RiskLevel = @RiskLevel)
          AND (@DaysBack IS NULL OR f.CreatedAt >= DATEADD(DAY, -@DaysBack, SYSUTCDATETIME()))
    )
    SELECT TOP (@Top)
        FeedbackId,
        Product,
        CustomerSegment,
        RiskLevel,
        Channel,
        CreatedAt,
        FeedbackText,
        similarity
    FROM Scored
    ORDER BY similarity DESC, CreatedAt DESC;
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_FindSimilarCases2022
    @FeedbackId INT,
    @Top INT = 10
AS
BEGIN
    SET NOCOUNT ON;

    ;WITH SeedNorm AS
    (
        SELECT SQRT(SUM(Value * Value)) AS Norm
        FROM dbo.FeedbackEmbedding
        WHERE FeedbackId = @FeedbackId
    ),
    FeedbackNorm AS
    (
        SELECT
            FeedbackId,
            SQRT(SUM(Value * Value)) AS Norm
        FROM dbo.FeedbackEmbedding
        GROUP BY FeedbackId
    ),
    DotProduct AS
    (
        SELECT
            fe.FeedbackId,
            SUM(fe.Value * seed.Value) AS DotValue
        FROM dbo.FeedbackEmbedding AS fe
        INNER JOIN dbo.FeedbackEmbedding AS seed
            ON seed.DimensionName = fe.DimensionName
           AND seed.FeedbackId = @FeedbackId
        WHERE fe.FeedbackId <> @FeedbackId
        GROUP BY fe.FeedbackId
    )
    SELECT TOP (@Top)
        f.FeedbackId,
        f.Product,
        f.CustomerSegment,
        f.RiskLevel,
        f.CreatedAt,
        f.FeedbackText,
        CAST(dp.DotValue / NULLIF(fn.Norm * sn.Norm, 0) AS DECIMAL(10, 4)) AS similarity
    FROM DotProduct AS dp
    INNER JOIN FeedbackNorm AS fn
        ON fn.FeedbackId = dp.FeedbackId
    CROSS JOIN SeedNorm AS sn
    INNER JOIN dbo.CustomerFeedback AS f
        ON f.FeedbackId = dp.FeedbackId
    ORDER BY similarity DESC, f.CreatedAt DESC;
END
GO

PRINT 'A. Keyword search: only exact wording';
EXEC dbo.usp_KeywordSearch @Keyword = N'trừ tiền';
GO

PRINT 'B. Semantic-like search: failed transaction but customer was debited';
EXEC dbo.usp_SemanticSearch2022
    @QueryName = N'debited_failed_transaction',
    @Top = 10;
GO

PRINT 'C. Semantic-like search plus business filters: VIP + Critical';
EXEC dbo.usp_SemanticSearch2022
    @QueryName = N'vip_serious_payment_issue',
    @CustomerSegment = N'VIP',
    @RiskLevel = N'Critical',
    @DaysBack = 30,
    @Top = 20;
GO

PRINT 'D. From one critical case, find similar cases';
DECLARE @caseId INT =
(
    SELECT TOP (1) FeedbackId
    FROM dbo.CustomerFeedback
    WHERE SourceIssueGroup = N'Failed transaction but debited'
      AND RiskLevel = N'Critical'
    ORDER BY FeedbackId
);

SELECT @caseId AS seed_feedback_id;
EXEC dbo.usp_FindSimilarCases2022
    @FeedbackId = @caseId,
    @Top = 15;
GO

PRINT 'E. Risk triage summary from top semantic-like hits';
;WITH TopHits AS
(
    SELECT TOP (40)
        f.FeedbackId,
        f.Product,
        f.RiskLevel,
        CAST(dp.DotValue / NULLIF(fn.Norm * qn.Norm, 0) AS DECIMAL(10, 4)) AS similarity
    FROM
    (
        SELECT
            fe.FeedbackId,
            SUM(fe.Value * qe.Value) AS DotValue
        FROM dbo.FeedbackEmbedding AS fe
        INNER JOIN dbo.QueryEmbedding AS qe
            ON qe.DimensionName = fe.DimensionName
           AND qe.QueryName = N'debited_failed_transaction'
        GROUP BY fe.FeedbackId
    ) AS dp
    INNER JOIN
    (
        SELECT FeedbackId, SQRT(SUM(Value * Value)) AS Norm
        FROM dbo.FeedbackEmbedding
        GROUP BY FeedbackId
    ) AS fn
        ON fn.FeedbackId = dp.FeedbackId
    CROSS JOIN
    (
        SELECT SQRT(SUM(Value * Value)) AS Norm
        FROM dbo.QueryEmbedding
        WHERE QueryName = N'debited_failed_transaction'
    ) AS qn
    INNER JOIN dbo.CustomerFeedback AS f
        ON f.FeedbackId = dp.FeedbackId
    ORDER BY similarity DESC
)
SELECT
    Product,
    RiskLevel,
    COUNT(*) AS hit_count,
    MAX(similarity) AS best_similarity,
    AVG(CAST(similarity AS FLOAT)) AS avg_similarity
FROM TopHits
GROUP BY Product, RiskLevel
ORDER BY best_similarity DESC;
GO

PRINT 'NOTE: This is a SQL Server 2022-compatible fallback. It emulates vector similarity with relational tables. Native VECTOR, VECTOR_SEARCH, AI_GENERATE_EMBEDDINGS, and CREATE VECTOR INDEX require SQL Server 2025 or Azure SQL.';
GO
