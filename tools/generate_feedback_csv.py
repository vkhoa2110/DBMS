from __future__ import annotations

import argparse
import csv
import random
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from pathlib import Path


@dataclass(frozen=True)
class IssueGroup:
    name: str
    risk_weights: tuple[tuple[str, int], ...]
    products: tuple[str, ...]
    templates: tuple[str, ...]


ISSUES: tuple[IssueGroup, ...] = (
    IssueGroup(
        name="Failed transaction but debited",
        risk_weights=(("Critical", 35), ("High", 55), ("Medium", 10)),
        products=("Mobile Banking", "Internet Banking", "Debit Card", "E-Wallet"),
        templates=(
            "Tôi thanh toán không thành công nhưng tiền vẫn bị trừ khỏi tài khoản.",
            "App báo lỗi sau OTP, số dư tài khoản vẫn giảm.",
            "Đơn hàng fail nhưng ví điện tử đã bị ghi nợ.",
            "Giao dịch timeout, tiền bị giữ chưa hoàn lại.",
            "Thanh toán không thành công, chưa thấy hoàn tiền.",
            "Máy báo giao dịch lỗi nhưng tài khoản của tôi bị giảm tiền.",
            "Sau khi chuyển khoản thất bại, tiền vẫn bị treo trong tài khoản.",
            "Ứng dụng báo không xử lý được lệnh nhưng số dư đã bị trừ.",
        ),
    ),
    IssueGroup(
        name="OTP or authentication failure",
        risk_weights=(("High", 20), ("Medium", 65), ("Low", 15)),
        products=("Mobile Banking", "Internet Banking", "Credit Card"),
        templates=(
            "Tôi không nhận được OTP nên không thể xác nhận giao dịch.",
            "Mã OTP gửi quá chậm, hết hạn trước khi nhập.",
            "Ứng dụng yêu cầu xác thực lại liên tục dù tôi nhập đúng mật khẩu.",
            "Xác thực khuôn mặt thất bại nhiều lần khi chuyển tiền.",
            "Tin nhắn OTP không về điện thoại trong giờ cao điểm.",
            "Tôi nhập OTP đúng nhưng hệ thống báo sai mã.",
        ),
    ),
    IssueGroup(
        name="App slow or crash",
        risk_weights=(("Medium", 30), ("Low", 70)),
        products=("Mobile Banking", "E-Wallet", "Internet Banking"),
        templates=(
            "Ứng dụng mở rất chậm và thường bị treo ở màn hình đăng nhập.",
            "App tự thoát khi tôi kiểm tra lịch sử giao dịch.",
            "Màn hình chuyển tiền quay vòng rất lâu không có phản hồi.",
            "Sau bản cập nhật mới, ứng dụng bị crash liên tục.",
            "Tôi phải đăng nhập lại nhiều lần vì app đứng máy.",
            "Trang tra cứu số dư tải quá lâu vào buổi tối.",
        ),
    ),
    IssueGroup(
        name="Wrong or duplicated fee",
        risk_weights=(("High", 25), ("Medium", 65), ("Low", 10)),
        products=("Credit Card", "Debit Card", "Loan", "Current Account"),
        templates=(
            "Tài khoản bị tính phí hai lần cho cùng một giao dịch.",
            "Phí thường niên thẻ cao hơn mức nhân viên đã tư vấn.",
            "Tôi thấy khoản phí lạ trong sao kê nhưng không có giải thích.",
            "Hệ thống thu phí chuyển khoản dù gói tài khoản của tôi miễn phí.",
            "Khoản phí phạt trả chậm bị ghi nhận sai ngày.",
            "Sao kê có hai dòng phí giống nhau trong cùng một ngày.",
        ),
    ),
    IssueGroup(
        name="Loan rejected unclear reason",
        risk_weights=(("Medium", 70), ("Low", 30)),
        products=("Loan", "Credit Card"),
        templates=(
            "Hồ sơ vay bị từ chối nhưng tôi không biết thiếu giấy tờ gì.",
            "Ứng dụng báo khoản vay không được duyệt mà không nêu lý do.",
            "Tôi đã bổ sung thu nhập nhưng trạng thái hồ sơ vẫn bị từ chối.",
            "Nhân viên nói đủ điều kiện nhưng hệ thống lại từ chối hồ sơ.",
            "Kết quả phê duyệt thẻ tín dụng không có giải thích cụ thể.",
            "Tôi cần biết nguyên nhân hồ sơ vay bị đánh rớt.",
        ),
    ),
    IssueGroup(
        name="Card blocked or payment declined",
        risk_weights=(("High", 30), ("Medium", 60), ("Low", 10)),
        products=("Credit Card", "Debit Card"),
        templates=(
            "Thẻ của tôi bị khóa khi thanh toán ở cửa hàng.",
            "Giao dịch quẹt thẻ bị từ chối dù hạn mức vẫn còn.",
            "Tôi không thể thanh toán online bằng thẻ tín dụng.",
            "Thẻ báo không hợp lệ khi rút tiền tại ATM.",
            "Hệ thống chặn thẻ nhưng không gửi thông báo trước.",
            "Thanh toán quốc tế bị decline dù tôi đã bật tính năng này.",
        ),
    ),
    IssueGroup(
        name="Customer service complaint",
        risk_weights=(("Medium", 30), ("Low", 70)),
        products=("Mobile Banking", "Credit Card", "Loan", "Current Account"),
        templates=(
            "Tổng đài để tôi chờ quá lâu nhưng chưa giải quyết được vấn đề.",
            "Nhân viên hứa gọi lại nhưng tôi không nhận được phản hồi.",
            "Tôi phải lặp lại cùng một khiếu nại cho nhiều bộ phận.",
            "Email hỗ trợ trả lời chung chung, không đúng câu hỏi.",
            "Chi nhánh hướng dẫn khác với thông tin trên ứng dụng.",
            "Chatbot không chuyển tôi sang nhân viên khi sự cố nghiêm trọng.",
        ),
    ),
    IssueGroup(
        name="Suspicious or fraudulent transaction",
        risk_weights=(("Critical", 60), ("High", 35), ("Medium", 5)),
        products=("Credit Card", "Debit Card", "Internet Banking", "E-Wallet"),
        templates=(
            "Tôi thấy giao dịch lạ không phải do tôi thực hiện.",
            "Có khoản thanh toán online đáng ngờ xuất hiện trong sao kê.",
            "Tài khoản phát sinh chuyển tiền bất thường lúc nửa đêm.",
            "Tôi nghi ngờ thẻ bị đánh cắp thông tin sau giao dịch này.",
            "Ví điện tử bị trừ tiền cho đơn hàng tôi không đặt.",
            "Có nhiều giao dịch nhỏ liên tiếp mà tôi không nhận ra.",
        ),
    ),
)

DEMO_ROWS: tuple[dict[str, str], ...] = (
    {
        "Product": "Mobile Banking",
        "CustomerSegment": "VIP",
        "Region": "Ho Chi Minh",
        "Channel": "App",
        "RiskLevel": "Critical",
        "SourceIssueGroup": "Failed transaction but debited",
        "FeedbackText": "App báo giao dịch thất bại sau OTP nhưng tài khoản vẫn bị trừ tiền.",
    },
    {
        "Product": "E-Wallet",
        "CustomerSegment": "VIP",
        "Region": "Ha Noi",
        "Channel": "Chatbot",
        "RiskLevel": "High",
        "SourceIssueGroup": "Failed transaction but debited",
        "FeedbackText": "Thanh toán lỗi nhưng số dư trong ví vẫn giảm.",
    },
    {
        "Product": "Internet Banking",
        "CustomerSegment": "Premier",
        "Region": "Da Nang",
        "Channel": "Web",
        "RiskLevel": "Critical",
        "SourceIssueGroup": "Failed transaction but debited",
        "FeedbackText": "Đơn hàng không thành công, tiền chưa được hoàn về tài khoản.",
    },
    {
        "Product": "Debit Card",
        "CustomerSegment": "VIP",
        "Region": "Can Tho",
        "Channel": "Call Center",
        "RiskLevel": "High",
        "SourceIssueGroup": "Failed transaction but debited",
        "FeedbackText": "Giao dịch bị treo sau khi xác thực, tài khoản đã ghi nợ.",
    },
    {
        "Product": "Mobile Banking",
        "CustomerSegment": "Mass",
        "Region": "Hai Phong",
        "Channel": "App",
        "RiskLevel": "High",
        "SourceIssueGroup": "Failed transaction but debited",
        "FeedbackText": "App báo timeout nhưng tiền trong tài khoản bị giữ.",
    },
    {
        "Product": "Credit Card",
        "CustomerSegment": "VIP",
        "Region": "Ho Chi Minh",
        "Channel": "Email",
        "RiskLevel": "Critical",
        "SourceIssueGroup": "Suspicious or fraudulent transaction",
        "FeedbackText": "Có khoản thanh toán online đáng ngờ trên thẻ, tôi không thực hiện giao dịch này.",
    },
)

SEGMENTS = ("Mass", "VIP", "Premier", "SME")
CHANNELS = ("App", "Web", "Call Center", "Branch", "Email", "Chatbot")
REGIONS = ("Ho Chi Minh", "Ha Noi", "Da Nang", "Can Tho", "Hai Phong", "Binh Duong")


def weighted_choice(items: tuple[tuple[str, int], ...]) -> str:
    values, weights = zip(*items)
    return random.choices(values, weights=weights, k=1)[0]


def random_created_at(base: datetime) -> str:
    minutes_back = random.randint(0, 60 * 24 * 60)
    created = base - timedelta(minutes=minutes_back)
    return created.replace(microsecond=0).isoformat()


def generate_rows(count: int, seed: int) -> list[dict[str, str]]:
    random.seed(seed)
    base = datetime.now(timezone.utc)
    rows: list[dict[str, str]] = []

    for idx, demo in enumerate(DEMO_ROWS, start=1):
        row = {
            "MaskedCustomerId": f"CUST-{idx:06d}",
            "CreatedAt": (base - timedelta(hours=idx)).replace(microsecond=0).isoformat(),
            **demo,
        }
        rows.append(row)

    for idx in range(len(rows) + 1, count + 1):
        issue = random.choice(ISSUES)
        product = random.choice(issue.products)
        segment = random.choices(SEGMENTS, weights=(65, 12, 13, 10), k=1)[0]
        risk = weighted_choice(issue.risk_weights)

        if segment == "VIP" and issue.name in {
            "Failed transaction but debited",
            "Suspicious or fraudulent transaction",
        }:
            risk = random.choices(("Critical", "High"), weights=(55, 45), k=1)[0]

        rows.append(
            {
                "MaskedCustomerId": f"CUST-{idx:06d}",
                "Product": product,
                "CustomerSegment": segment,
                "Region": random.choice(REGIONS),
                "Channel": random.choice(CHANNELS),
                "RiskLevel": risk,
                "CreatedAt": random_created_at(base),
                "SourceIssueGroup": issue.name,
                "FeedbackText": random.choice(issue.templates),
            }
        )

    random.shuffle(rows)
    return rows


def write_csv(rows: list[dict[str, str]], output: Path) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    fieldnames = [
        "MaskedCustomerId",
        "Product",
        "CustomerSegment",
        "Region",
        "Channel",
        "RiskLevel",
        "CreatedAt",
        "SourceIssueGroup",
        "FeedbackText",
    ]

    with output.open("w", encoding="utf-8-sig", newline="") as file:
        writer = csv.DictWriter(file, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Generate Vietnamese customer feedback data for the SQL Server vector search demo."
    )
    parser.add_argument("--rows", type=int, default=10000, help="Number of rows to generate.")
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("data/customer_feedback.csv"),
        help="Output CSV path.",
    )
    parser.add_argument("--seed", type=int, default=20260515, help="Random seed.")
    args = parser.parse_args()

    if args.rows < len(DEMO_ROWS):
        raise SystemExit(f"--rows must be at least {len(DEMO_ROWS)}")

    rows = generate_rows(args.rows, args.seed)
    write_csv(rows, args.output)
    print(f"Wrote {len(rows):,} rows to {args.output}")


if __name__ == "__main__":
    main()

