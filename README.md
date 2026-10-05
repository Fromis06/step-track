# Step Track

Ứng dụng đếm bước cá nhân cho iPhone, giao diện SwiftUI tối giản xanh lá, sáng/tối và Tiếng Việt / English / 日本語.

- Cảm biến iPhone: số bước, quãng đường, mục tiêu và biểu đồ 7 ngày.
- Thanh điều hướng nổi chỉ icon: Trang chủ, Thống kê, Cài đặt.
- Lịch hoạt động tháng/năm, mục tiêu riêng từng ngày và lịch sử lưu lâu dài.
- Không quảng cáo, tài khoản, paywall hay gửi dữ liệu lên máy chủ.
- GitHub Actions kiểm thử trên iPhone 11 simulator và xuất IPA để ký lại bằng Sideloadly.

## Build

Xem [hướng dẫn cài iPhone](BUILD-IPHONE.md). Trên Mac:

```sh
brew install xcodegen
xcodegen generate --spec project-sideload.yml
open StepTrackSideload.xcodeproj
```

Mã app nằm trong `StepTrack/App`, dữ liệu trong `StepTrack/Shared`, kiểm thử trong `StepTrack/Tests` và `StepTrack/UITests`.

Cấu hình Health/widget cũ (`project.yml`) vẫn được giữ để tham khảo, không nằm trong workflow hiện tại. Bản đang phát triển dùng Motion và không yêu cầu quyền HealthKit/App Groups.

## Nguồn gốc

Khởi tạo từ [brittanyarima/Steps](https://github.com/brittanyarima/Steps), commit `e395cdd`, giấy phép MIT. Giữ [LICENSE](LICENSE) và [README gốc](README.upstream.md). Các thư mục `Steps/`, `StepsWidget/`, `StepsTests/`, `Steps.xcodeproj` là nguồn tham khảo upstream, không nằm trong bản build mới. Đây là bản tùy biến độc lập.

## Sideload: lịch sử và điều hướng

Bản Motion hiện có thanh điều hướng nổi chỉ dùng icon: Trang chủ, Thống kê, Cài đặt. Thống kê có lịch tháng và 12 tháng xếp 4 hàng × 3 cột, tổng bước ở góc phải. Ngày đạt mục tiêu được tô xanh.

Mục tiêu thay đổi áp dụng cho hôm nay và các ngày tiếp theo; mục tiêu của ngày đã qua được giữ nguyên. Dữ liệu từ bản cũ chưa lưu mục tiêu lịch sử được đánh dấu chưa biết, không gán mục tiêu hiện tại ngược về quá khứ.

Lịch sử được lưu lâu dài trên iPhone, không tự xóa sau 7 ngày. Tuy nhiên Motion chỉ cho truy vấn khoảng 7 ngày gần nhất, nên cần mở app vài ngày một lần để bổ sung lịch sử. Khoảng trống quá cũ không thể khôi phục; tổng tháng/năm là tổng dữ liệu đã lưu. Gỡ app hoặc chọn xóa lịch sử sẽ mất dữ liệu cục bộ. Khi cập nhật bằng Sideloadly, giữ cùng Apple ID và bundle ID, không gỡ bản đang dùng trước.

Workflow hiện kiểm thử và xuất `StepTrack-sideload-unsigned.ipa` (không cần HealthKit hay widget).
