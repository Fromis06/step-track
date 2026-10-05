# Step Track

Ứng dụng đếm bước cá nhân cho iPhone, giao diện SwiftUI tối giản xanh lá và tự theo chế độ sáng/tối. Đổi Tiếng Việt / English / 日本語 ngay trong Cài đặt; lựa chọn được lưu cho app và widget.

- Số bước, mục tiêu tùy chỉnh, quãng đường, biểu đồ 7/30 ngày.
- Bản Health đọc Apple Health, lưu snapshot chung cho widget Home Screen/Lock Screen.
- Bản Sideload dùng cảm biến iPhone, lịch sử 7 ngày, không HealthKit/widget, để thử ký bằng Sideloadly.
- GitHub Actions dùng macOS runner xuất hai IPA để ký lại, không yêu cầu thông tin Apple ID trong CI.
- Không quảng cáo, đăng nhập, paywall hay gửi dữ liệu sức khỏe lên máy chủ.

Hai IPA ba ngôn ngữ đã build thành công trên GitHub macOS runner. Unit tests và kiểm thử giao diện đổi ngôn ngữ/lưu lựa chọn sau khi mở lại app đã qua trên iPhone 16 Pro simulator. [Build đã kiểm tra](https://github.com/Fromis06/step-track/actions/runs/37258982058). Chưa thử trên iPhone thật. HealthKit/widget còn phụ thuộc chữ ký và provisioning profile; không cam kết hoạt động với tài khoản ký miễn phí.

## Bắt đầu

Xem [hướng dẫn build và cài lên iPhone](BUILD-IPHONE.md).

Trên Mac:

```sh
brew install xcodegen
xcodegen generate --spec project.yml
open StepTrack.xcodeproj
```

Để tạo bản chỉ dùng cảm biến:

```sh
xcodegen generate --spec project-sideload.yml
open StepTrackSideload.xcodeproj
```

## Cấu trúc

| Đường dẫn | Vai trò |
|---|---|
| `StepTrack/App` | Giao diện và đọc HealthKit/Core Motion |
| `StepTrack/Shared` | Dữ liệu theo ngày, cache và mục tiêu |
| `StepTrack/Widget` | Widget đọc cache, xử lý qua ngày mới |
| `StepTrack/Tests` | Unit tests về ngày, mục tiêu và dữ liệu lưu |
| `project.yml` | Dự án Health + widget |
| `project-sideload.yml` | Dự án Core Motion không quyền HealthKit/App Groups |
| `.github/workflows/build-ios.yml` | Build, test và đóng gói IPA |

## Nguồn gốc

Được khởi tạo bằng clone [brittanyarima/Steps](https://github.com/brittanyarima/Steps), commit `e395cdd`, giấy phép MIT. Giữ nguyên [LICENSE](LICENSE) và [README gốc](README.upstream.md).

Bản tùy biến triển khai app trong `StepTrack/`, tham khảo SwiftUI/HealthKit/WidgetKit của dự án gốc. Các thư mục `Steps/`, `StepsWidget/`, `StepsTests/` và `Steps.xcodeproj` giữ làm nguồn tham khảo upstream, **không nằm trong build mới**. Mở dự án `StepTrack.xcodeproj` do XcodeGen sinh ra để làm việc với bản mới. Không có quan hệ phát hành với tác giả gốc.


## Sideload: lịch sử và điều hướng

Bản Motion hiện có thanh điều hướng nổi chỉ dùng icon: Trang chủ, Thống kê, Cài đặt. Thống kê có lịch tháng và 12 tháng xếp 4 hàng × 3 cột, tổng bước ở góc phải. Ngày đạt mục tiêu được tô xanh.

Mục tiêu thay đổi áp dụng cho hôm nay và các ngày tiếp theo; mục tiêu của ngày đã qua được giữ nguyên. Dữ liệu từ bản cũ chưa lưu mục tiêu lịch sử được đánh dấu chưa biết, không gán mục tiêu hiện tại ngược về quá khứ.

Lịch sử được lưu lâu dài trên iPhone, không tự xóa sau 7 ngày. Tuy nhiên Motion chỉ cho truy vấn khoảng 7 ngày gần nhất, nên cần mở app vài ngày một lần để bổ sung lịch sử. Khoảng trống quá cũ không thể khôi phục; tổng tháng/năm là tổng dữ liệu đã lưu. Gỡ app hoặc chọn xóa lịch sử sẽ mất dữ liệu cục bộ. Khi cập nhật bằng Sideloadly, giữ cùng Apple ID và bundle ID, không gỡ bản đang dùng trước.

Workflow hiện kiểm thử và xuất `StepTrack-sideload-unsigned.ipa` (không cần HealthKit hay widget).
