# Step Track · iPhone 11 / iOS 18.3.2

## Trạng thái

Mã nguồn và workflow đã được chuẩn bị trên Windows. Chưa có kết quả biên dịch Xcode hay kiểm thử trên iPhone. IPA chỉ xuất hiện sau khi workflow GitHub chạy thành công.

## Hai bản build

| Artifact | Dữ liệu | Widget | Cài đặt |
|---|---|---|---|
| `StepTrack-sideload-unsigned` | Core Motion của iPhone, 7 ngày | Không | Dành để thử ký bằng Sideloadly / Apple ID miễn phí |
| `StepTrack-health-unsigned` | Apple Health, 30 ngày | Home Screen nhỏ/vừa + Lock Screen | Cần chữ ký và provisioning hỗ trợ HealthKit, Background Delivery và App Groups |

Bản cảm biến không thay thế kết nối Apple Health. Bản Health cần cấp quyền đọc một lần trên iPhone. Cả hai chỉ lưu dữ liệu trên thiết bị, không có tài khoản hay máy chủ.

Sideloadly không tự cấp các entitlement mà provisioning profile không cho phép. Ký lại có thể thay Bundle ID, bỏ quyền hoặc extension; vì vậy **chưa thể hứa bản Health và widget hoạt động với Apple ID miễn phí**. Nếu bản Health không ký/cài được, dùng bản `sideload` để thử giao diện và bước chân từ cảm biến. Để dùng trọn bộ, cần signing có các capability tương ứng; thường dùng Apple Developer Program và đăng ký App IDs/App Group riêng.

## Build bằng GitHub Actions

1. Tạo repo của bạn trên GitHub, đưa toàn bộ thư mục dự án vào repo, gồm thư mục ẩn `.github`. Không push vào repository gốc của Brittany Rima.
2. Nếu fork: thêm các thay đổi của bản tùy biến này vào fork. Chỉ fork repo gốc sẽ chưa có giao diện/workflow mới.
3. Vào **Actions → Build iPhone IPA → Run workflow**. Workflow cũng chạy khi thay đổi mã app được push.
4. Đợi hai nhánh `health` và `sideload` hoàn tất. Bản Health chạy unit tests trên simulator trước khi build thiết bị.
5. Mở run → **Artifacts** → tải `StepTrack-sideload-unsigned` hoặc `StepTrack-health-unsigned` → giải nén ZIP để lấy IPA.

Không cần đưa Apple ID, mật khẩu hay certificate lên GitHub cho workflow này. Nó build không ký; bản Health có chữ ký ad-hoc cục bộ chỉ để giữ danh sách entitlement cho công cụ ký lại, không phải chữ ký có thể cài lên iPhone.

Runner: `macos-15`, Xcode mặc định của runner, iOS deployment target 17.0, Swift 5, không có thư viện app bên thứ ba. XcodeGen tạo dự án từ `project.yml` / `project-sideload.yml`. IPA build cho thiết bị thật, không phải simulator. Khi GitHub thay Xcode mặc định, xem log để biết phiên bản thực tế.

## Cài bằng Sideloadly trên Windows

1. Dùng Sideloadly từ [sideloadly.io](https://sideloadly.io/), kết nối iPhone qua USB, chọn Trust trên iPhone.
2. Kéo `StepTrack-sideload-unsigned.ipa` vào Sideloadly, chọn iPhone và Apple ID, bấm Start. Giữ cùng Apple ID/Bundle ID khi cập nhật để tránh cài thành app mới.
3. Nếu iOS yêu cầu: bật **Cài đặt → Quyền riêng tư & Bảo mật → Chế độ nhà phát triển**, rồi khởi động lại và xác nhận. Tin cậy nhà phát triển ở **Cài đặt → Cài đặt chung → VPN & Quản lý thiết bị** khi được yêu cầu.
4. Mở Step Track → **Kết nối** → cho phép Chuyển động & thể chất. Mang iPhone đi bộ rồi mở lại app hoặc kéo xuống để cập nhật.
5. Apple ID miễn phí thường cần ký lại sau 7 ngày. Bật tự gia hạn của Sideloadly nếu muốn; máy tính cần thấy điện thoại qua USB/Wi-Fi.

## Cấu hình bản Health + widget

- Đổi `APP_BUNDLE_ID` và `APP_GROUP_ID` trong `project.yml` thành định danh riêng của bạn. Ví dụ `com.tenban.steptrack` và `group.com.tenban.steptrack`.
- Đăng ký app và extension `.widget`. Bật HealthKit + Background Delivery cho app. Cả app và widget cùng có App Group chính xác. Không cần Clinical Health Records.
- Dùng certificate/profile tương thích, ký extension trước rồi app; công cụ ký phải giữ extension và các entitlement hợp lệ. Không chỉ đổi tên Bundle ID trong IPA mà bỏ qua App Group.
- Mở app → Kết nối → cho phép **Số bước** và **Quãng đường đi bộ + chạy**. Dữ liệu không xuất hiện tức thì nếu thiết bị khóa hoặc chưa đồng bộ.
- Thêm widget qua màn hình chính → nhấn giữ → Sửa → Thêm tiện ích → Step Track. Nếu widget báo cần kiểm tra, xem mục Widget trong Cài đặt của app.
- Widget đọc bản lưu chung; HealthKit observer yêu cầu cập nhật nền tối đa theo nhịp giờ và app cập nhật khi mở/kéo xuống. iOS quản lý lịch chạy, không đảm bảo thời gian thực. Sau nửa đêm widget không dùng số bước hôm qua làm số bước hôm nay.

## Kiểm tra trên thiết bị trước khi dùng hàng ngày

- Kết nối, cấp một phần quyền, từ chối quyền, rồi bật lại trong Sức khỏe. Không coi màn hình xin quyền hoàn tất là đã được phép đọc.
- So sánh số bước theo ngày với Apple Health; nếu có Apple Watch, không cộng tay hai nguồn.
- Quãng đường chưa có dữ liệu phải là `—`, không giả số liệu.
- Mở lại sau khóa máy, qua nửa đêm, đổi múi giờ; kéo cập nhật nhiều lần không nhân đôi lịch sử.
- Đổi mục tiêu, kiểm tra app + widget; thử chế độ sáng/tối, cỡ chữ lớn và VoiceOver.
- Tắt đọc/xóa bản lưu: widget phải chuyển về trạng thái chưa kết nối; dữ liệu gốc trong Health vẫn còn. Thu hồi quyền hệ thống trong Health riêng nếu muốn.
- Bản Motion chỉ có dữ liệu tối đa 7 ngày và không gồm bước từ Watch. Khi iPhone không được mang theo, bước đó không có trong bản Motion.

## Nguồn

- [Steps — Brittany Rima, MIT](https://github.com/brittanyarima/Steps)
- [HealthKit authorization](https://developer.apple.com/documentation/healthkit/authorizing-access-to-health-data)
- [Configuring HealthKit](https://developer.apple.com/documentation/xcode/configuring-healthkit-access)
- [Widget refresh](https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date)
- [Core Motion: giới hạn lịch sử](https://developer.apple.com/documentation/coremotion/cmpedometer/querypedometerdata(from:to:withhandler:))
- [Sideloadly FAQ](https://sideloadly.io/faq.html)
- [GitHub hosted runners](https://docs.github.com/en/actions/reference/runners/github-hosted-runners): runner tiêu chuẩn miễn phí cho repo công khai; repo riêng chịu hạn mức/tính phí theo tài khoản.
