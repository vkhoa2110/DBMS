param(
    [int]$Rows = 10000,
    [string]$Output = "data\customer_feedback.csv",
    [int]$Seed = 20260515
)

$ErrorActionPreference = "Stop"

if ($Rows -lt 6) {
    throw "Rows must be at least 6."
}

$random = [System.Random]::new($Seed)

function Get-RandomItem {
    param([object[]]$Items)
    return $Items[$random.Next(0, $Items.Count)]
}

function Get-WeightedItem {
    param([object[]]$Items)

    $total = 0
    foreach ($item in $Items) {
        $total += [int]$item.Weight
    }

    $pick = $random.Next(1, $total + 1)
    $running = 0
    foreach ($item in $Items) {
        $running += [int]$item.Weight
        if ($pick -le $running) {
            return [string]$item.Value
        }
    }

    return [string]$Items[-1].Value
}

$issues = @(
    @{
        Name = "Failed transaction but debited"
        Risks = @(@{ Value = "Critical"; Weight = 35 }, @{ Value = "High"; Weight = 55 }, @{ Value = "Medium"; Weight = 10 })
        Products = @("Mobile Banking", "Internet Banking", "Debit Card", "E-Wallet")
        Templates = @(
            "Tôi thanh toán không thành công nhưng tiền vẫn bị trừ khỏi tài khoản.",
            "App báo lỗi sau OTP, số dư tài khoản vẫn giảm.",
            "Đơn hàng fail nhưng ví điện tử đã bị ghi nợ.",
            "Giao dịch timeout, tiền bị giữ chưa hoàn lại.",
            "Thanh toán không thành công, chưa thấy hoàn tiền.",
            "Máy báo giao dịch lỗi nhưng tài khoản của tôi bị giảm tiền.",
            "Sau khi chuyển khoản thất bại, tiền vẫn bị treo trong tài khoản.",
            "Ứng dụng báo không xử lý được lệnh nhưng số dư đã bị trừ."
        )
    },
    @{
        Name = "OTP or authentication failure"
        Risks = @(@{ Value = "High"; Weight = 20 }, @{ Value = "Medium"; Weight = 65 }, @{ Value = "Low"; Weight = 15 })
        Products = @("Mobile Banking", "Internet Banking", "Credit Card")
        Templates = @(
            "Tôi không nhận được OTP nên không thể xác nhận giao dịch.",
            "Mã OTP gửi quá chậm, hết hạn trước khi nhập.",
            "Ứng dụng yêu cầu xác thực lại liên tục dù tôi nhập đúng mật khẩu.",
            "Xác thực khuôn mặt thất bại nhiều lần khi chuyển tiền.",
            "Tin nhắn OTP không về điện thoại trong giờ cao điểm.",
            "Tôi nhập OTP đúng nhưng hệ thống báo sai mã."
        )
    },
    @{
        Name = "App slow or crash"
        Risks = @(@{ Value = "Medium"; Weight = 30 }, @{ Value = "Low"; Weight = 70 })
        Products = @("Mobile Banking", "E-Wallet", "Internet Banking")
        Templates = @(
            "Ứng dụng mở rất chậm và thường bị treo ở màn hình đăng nhập.",
            "App tự thoát khi tôi kiểm tra lịch sử giao dịch.",
            "Màn hình chuyển tiền quay vòng rất lâu không có phản hồi.",
            "Sau bản cập nhật mới, ứng dụng bị crash liên tục.",
            "Tôi phải đăng nhập lại nhiều lần vì app đứng máy.",
            "Trang tra cứu số dư tải quá lâu vào buổi tối."
        )
    },
    @{
        Name = "Wrong or duplicated fee"
        Risks = @(@{ Value = "High"; Weight = 25 }, @{ Value = "Medium"; Weight = 65 }, @{ Value = "Low"; Weight = 10 })
        Products = @("Credit Card", "Debit Card", "Loan", "Current Account")
        Templates = @(
            "Tài khoản bị tính phí hai lần cho cùng một giao dịch.",
            "Phí thường niên thẻ cao hơn mức nhân viên đã tư vấn.",
            "Tôi thấy khoản phí lạ trong sao kê nhưng không có giải thích.",
            "Hệ thống thu phí chuyển khoản dù gói tài khoản của tôi miễn phí.",
            "Khoản phí phạt trả chậm bị ghi nhận sai ngày.",
            "Sao kê có hai dòng phí giống nhau trong cùng một ngày."
        )
    },
    @{
        Name = "Loan rejected unclear reason"
        Risks = @(@{ Value = "Medium"; Weight = 70 }, @{ Value = "Low"; Weight = 30 })
        Products = @("Loan", "Credit Card")
        Templates = @(
            "Hồ sơ vay bị từ chối nhưng tôi không biết thiếu giấy tờ gì.",
            "Ứng dụng báo khoản vay không được duyệt mà không nêu lý do.",
            "Tôi đã bổ sung thu nhập nhưng trạng thái hồ sơ vẫn bị từ chối.",
            "Nhân viên nói đủ điều kiện nhưng hệ thống lại từ chối hồ sơ.",
            "Kết quả phê duyệt thẻ tín dụng không có giải thích cụ thể.",
            "Tôi cần biết nguyên nhân hồ sơ vay bị đánh rớt."
        )
    },
    @{
        Name = "Card blocked or payment declined"
        Risks = @(@{ Value = "High"; Weight = 30 }, @{ Value = "Medium"; Weight = 60 }, @{ Value = "Low"; Weight = 10 })
        Products = @("Credit Card", "Debit Card")
        Templates = @(
            "Thẻ của tôi bị khóa khi thanh toán ở cửa hàng.",
            "Giao dịch quẹt thẻ bị từ chối dù hạn mức vẫn còn.",
            "Tôi không thể thanh toán online bằng thẻ tín dụng.",
            "Thẻ báo không hợp lệ khi rút tiền tại ATM.",
            "Hệ thống chặn thẻ nhưng không gửi thông báo trước.",
            "Thanh toán quốc tế bị decline dù tôi đã bật tính năng này."
        )
    },
    @{
        Name = "Customer service complaint"
        Risks = @(@{ Value = "Medium"; Weight = 30 }, @{ Value = "Low"; Weight = 70 })
        Products = @("Mobile Banking", "Credit Card", "Loan", "Current Account")
        Templates = @(
            "Tổng đài để tôi chờ quá lâu nhưng chưa giải quyết được vấn đề.",
            "Nhân viên hứa gọi lại nhưng tôi không nhận được phản hồi.",
            "Tôi phải lặp lại cùng một khiếu nại cho nhiều bộ phận.",
            "Email hỗ trợ trả lời chung chung, không đúng câu hỏi.",
            "Chi nhánh hướng dẫn khác với thông tin trên ứng dụng.",
            "Chatbot không chuyển tôi sang nhân viên khi sự cố nghiêm trọng."
        )
    },
    @{
        Name = "Suspicious or fraudulent transaction"
        Risks = @(@{ Value = "Critical"; Weight = 60 }, @{ Value = "High"; Weight = 35 }, @{ Value = "Medium"; Weight = 5 })
        Products = @("Credit Card", "Debit Card", "Internet Banking", "E-Wallet")
        Templates = @(
            "Tôi thấy giao dịch lạ không phải do tôi thực hiện.",
            "Có khoản thanh toán online đáng ngờ xuất hiện trong sao kê.",
            "Tài khoản phát sinh chuyển tiền bất thường lúc nửa đêm.",
            "Tôi nghi ngờ thẻ bị đánh cắp thông tin sau giao dịch này.",
            "Ví điện tử bị trừ tiền cho đơn hàng tôi không đặt.",
            "Có nhiều giao dịch nhỏ liên tiếp mà tôi không nhận ra."
        )
    }
)

$segments = @("Mass", "VIP", "Premier", "SME")
$channels = @("App", "Web", "Call Center", "Branch", "Email", "Chatbot")
$regions = @("Ho Chi Minh", "Ha Noi", "Da Nang", "Can Tho", "Hai Phong", "Binh Duong")
$base = [DateTimeOffset]::UtcNow

$demoRows = @(
    @{ Product = "Mobile Banking"; CustomerSegment = "VIP"; Region = "Ho Chi Minh"; Channel = "App"; RiskLevel = "Critical"; SourceIssueGroup = "Failed transaction but debited"; FeedbackText = "App báo giao dịch thất bại sau OTP nhưng tài khoản vẫn bị trừ tiền." },
    @{ Product = "E-Wallet"; CustomerSegment = "VIP"; Region = "Ha Noi"; Channel = "Chatbot"; RiskLevel = "High"; SourceIssueGroup = "Failed transaction but debited"; FeedbackText = "Thanh toán lỗi nhưng số dư trong ví vẫn giảm." },
    @{ Product = "Internet Banking"; CustomerSegment = "Premier"; Region = "Da Nang"; Channel = "Web"; RiskLevel = "Critical"; SourceIssueGroup = "Failed transaction but debited"; FeedbackText = "Đơn hàng không thành công, tiền chưa được hoàn về tài khoản." },
    @{ Product = "Debit Card"; CustomerSegment = "VIP"; Region = "Can Tho"; Channel = "Call Center"; RiskLevel = "High"; SourceIssueGroup = "Failed transaction but debited"; FeedbackText = "Giao dịch bị treo sau khi xác thực, tài khoản đã ghi nợ." },
    @{ Product = "Mobile Banking"; CustomerSegment = "Mass"; Region = "Hai Phong"; Channel = "App"; RiskLevel = "High"; SourceIssueGroup = "Failed transaction but debited"; FeedbackText = "App báo timeout nhưng tiền trong tài khoản bị giữ." },
    @{ Product = "Credit Card"; CustomerSegment = "VIP"; Region = "Ho Chi Minh"; Channel = "Email"; RiskLevel = "Critical"; SourceIssueGroup = "Suspicious or fraudulent transaction"; FeedbackText = "Có khoản thanh toán online đáng ngờ trên thẻ, tôi không thực hiện giao dịch này." }
)

$rowsOut = New-Object "System.Collections.Generic.List[object]"

for ($i = 0; $i -lt $demoRows.Count; $i++) {
    $demo = $demoRows[$i]
    $rowsOut.Add([pscustomobject]@{
        MaskedCustomerId = "CUST-{0:D6}" -f ($i + 1)
        Product = $demo.Product
        CustomerSegment = $demo.CustomerSegment
        Region = $demo.Region
        Channel = $demo.Channel
        RiskLevel = $demo.RiskLevel
        CreatedAt = $base.AddHours(-($i + 1)).ToString("yyyy-MM-ddTHH:mm:ssK")
        SourceIssueGroup = $demo.SourceIssueGroup
        FeedbackText = $demo.FeedbackText
    })
}

for ($i = $demoRows.Count + 1; $i -le $Rows; $i++) {
    $issue = Get-RandomItem $issues
    $segment = Get-RandomItem $segments
    $risk = Get-WeightedItem $issue.Risks

    if ($segment -eq "VIP" -and ($issue.Name -eq "Failed transaction but debited" -or $issue.Name -eq "Suspicious or fraudulent transaction")) {
        $risk = Get-WeightedItem @(@{ Value = "Critical"; Weight = 55 }, @{ Value = "High"; Weight = 45 })
    }

    $rowsOut.Add([pscustomobject]@{
        MaskedCustomerId = "CUST-{0:D6}" -f $i
        Product = Get-RandomItem $issue.Products
        CustomerSegment = $segment
        Region = Get-RandomItem $regions
        Channel = Get-RandomItem $channels
        RiskLevel = $risk
        CreatedAt = $base.AddMinutes(-$random.Next(0, 60 * 24 * 60)).ToString("yyyy-MM-ddTHH:mm:ssK")
        SourceIssueGroup = $issue.Name
        FeedbackText = Get-RandomItem $issue.Templates
    })
}

$outputPath = if ([System.IO.Path]::IsPathRooted($Output)) {
    $Output
}
else {
    Join-Path (Get-Location) $Output
}

$outputDir = Split-Path -Parent $outputPath
if (-not [string]::IsNullOrWhiteSpace($outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

$rowsOut | Export-Csv -LiteralPath $outputPath -NoTypeInformation -Encoding UTF8
Write-Host "Wrote $($rowsOut.Count) rows to $outputPath"

