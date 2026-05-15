:setvar DemoDatabase "CustomerAIDemo"

USE [$(DemoDatabase)];
GO

DELETE FROM dbo.CustomerFeedback;
GO

DBCC CHECKIDENT (N'dbo.CustomerFeedback', RESEED, 0);
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

SELECT
    COUNT(*) AS seeded_rows,
    SUM(CASE WHEN SourceIssueGroup = N'Failed transaction but debited' THEN 1 ELSE 0 END) AS debited_issue_rows,
    SUM(CASE WHEN RiskLevel = N'Critical' THEN 1 ELSE 0 END) AS critical_rows
FROM dbo.CustomerFeedback;
GO

