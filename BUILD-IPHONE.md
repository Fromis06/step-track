# Step Track · iPhone 11 / iOS 18.3.2

## Build bằng GitHub Actions

1. Mở repo → Actions → Build iPhone IPA → Run workflow. Workflow cũng chạy khi push mã app.
2. Đợi kiểm thử và build hoàn tất.
3. Tải artifact `StepTrack-sideload-unsigned`, giải nén ZIP để lấy IPA.

Workflow dùng macOS, XcodeGen và Xcode; không cần cung cấp Apple ID hay mật khẩu cho GitHub. IPA chưa được ký để cài trực tiếp. Bản hiện tại chỉ dùng cảm biến Motion, không có HealthKit/widget.

## Cài hoặc cập nhật

1. Mở Sideloadly, kết nối iPhone và kéo IPA vào.
2. Giữ cùng Apple ID và Bundle ID của bản sideload đang dùng để cập nhật đè. Không gỡ app trước, vì lịch sử lưu cục bộ sẽ mất.
3. Ký và cài như bản trước. Nếu iOS yêu cầu, bật Chế độ nhà phát triển và tin cậy nhà phát triển trong Cài đặt.
4. Lần đầu: mở Step Track → Kết nối → cho phép Chuyển động & thể chất. Mở lại app hoặc kéo xuống để cập nhật số bước.

## Giao diện

Thanh nổi chỉ có icon Nhà / Lịch / Bánh răng. Chọn ngôn ngữ và mục tiêu trong tab Cài đặt. Tab Thống kê có tháng/năm, 12 tháng xếp 4 hàng × 3 cột và tổng số bước ở góc phải. Chạm ngày để xem bước và mục tiêu ngày đó; chạm tháng trong bảng năm để mở tháng.

Mục tiêu thay đổi áp dụng từ hôm nay. Ngày đã qua giữ mục tiêu cũ. Những ngày từ bản trước chưa ghi lại mục tiêu sẽ hiển thị chưa lưu mục tiêu, không suy đoán bằng mục tiêu hiện tại.

## Lưu dữ liệu

Lịch sử được lưu lâu dài trên iPhone. Motion chỉ cho truy vấn khoảng 7 ngày gần nhất nên hãy mở app vài ngày một lần để bổ sung dữ liệu. Ngày quá cũ chưa được lưu không thể phục hồi; tổng tháng/năm phản ánh dữ liệu đã lưu. Không mang iPhone thì Motion không có bước đó; dữ liệu Watch không được nhập.

Xóa app hoặc chọn xóa lịch sử sẽ xóa bản lưu cục bộ. Không có đồng bộ tài khoản hay máy chủ.

## Kiểm thử

Workflow kiểm tra tổng theo ngày, qua nửa đêm, mục tiêu ngày cũ, lưu/đọc lịch sử, lịch năm nhuận, điều hướng, lịch tháng/năm và đổi ba ngôn ngữ. Ảnh chụp mô phỏng iPhone 11 được xuất ở artifact `interface-screenshots`. Cảm biến và ký bằng Sideloadly vẫn cần kiểm tra trên iPhone thật.
