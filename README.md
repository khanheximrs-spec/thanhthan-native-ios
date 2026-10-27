# Native combat UI update

Bản sửa này chạy SwiftUI + SceneKit trực tiếp; không có WKWebView.

- Màn hình ngang, HUD HP/MP/EXP gọn, khung màu đồng tối.
- Chạm quái hoặc nút MỤC TIÊU để chọn; vòng đánh dấu và HP mục tiêu lấy từ GameWorld.
- Radar lấy vị trí nhân vật và quái còn sống, không phải ảnh bản đồ giả.
- Hiển thị hồi chiêu kỹ năng, khóa nút khi thiếu MP; số sát thương nổi trong scene.
- Túi đồ dạng lưới hiển thị bình máu thật; texture mẫu PC ghi rõ là mẫu, không phải vật phẩm đã sở hữu.
- Tạm dừng khi mở túi đồ/hướng dẫn hoặc ứng dụng chuyển nền; reset joystick để tránh tự chạy.
- Hồi sinh đưa quái về điểm xuất hiện, xóa input và lựa chọn cũ.
- Sửa đóng gói gem.png và thêm XCTest kiểm tra chọn mục tiêu, ngoài tầm, hồi chiêu, bình máu, trạng thái dừng.

## Phạm vi và kiểm chứng

Chưa thể xác nhận giống nguyên bản ThanhThan: trang play.thanhthan.info chặn phiên khảo sát. Đây là bố cục native tạm triển khai, không phải kết quả khảo sát gameplay gốc.
Mô hình quái assassin_dier.glb đã có sẵn từ bản trước; nhân vật và địa hình vẫn dựng mẫu. Chưa có mạng, tài khoản, bản đồ PC đầy đủ hay bộ trang bị/animation nhân vật.
Danh sách BMD/OZJ được cung cấp xác nhận có tài nguyên Player, nhưng danh sách tên file không thay thế mesh/rig/texture đã chuyển đổi và kiểm tra.

Build và XCTest được chạy qua pull request trên macOS. Chỉ coi IPA là bản thử nghiệm sau khi CI thành công; vẫn cần kiểm tra cảm ứng và bố cục trên iPhone thật.

## Checklist kiểm tra trên iPhone

1. Xoay ngang hai chiều: HUD và nút không bị tai thỏ che, scene phủ nền.
2. Kéo joystick rồi mở túi đồ: quái ngừng đánh; đóng lại nhân vật không tự chạy.
3. Chạm quái, tiến vào tầm, đánh: vòng chọn và HP mục tiêu phản hồi đúng.
4. Dùng kỹ năng: mất 22 MP, đếm ngược 1,8 giây; chạm liên tục không dùng thêm MP.
5. AUTO bật/tắt; mục tiêu ngoài tầm không nhận sát thương.
6. Ra nền/quay lại: không mất máu trong lúc ứng dụng bị tạm dừng.
7. Hết HP rồi hồi sinh: nhân vật sống lại, quái về điểm xuất hiện.

---

# ThanhThan Native iOS – Prototype 0.1

**Ứng dụng iOS native SwiftUI + SceneKit, không mở website.**

## Phạm vi bản v0.1

| Có trong demo | Chưa có |
| --- | --- |
| Render 3D native trên iPhone | Engine MU Season 6 gốc |
| Joystick ảo và camera đi theo | Đăng nhập máy chủ ThanhThan |
| Nhân vật và quái vật 3D dựng mẫu | Mô hình BMD gốc đã giải mã toàn bộ |
| Đánh thường, kỹ năng diện rộng, tự đánh | Đồng bộ vị trí, chiến đấu online |
| HP, MP, EXP, level, vàng, bình máu, hồi sinh | Tất cả bản đồ, vật phẩm, quest gốc |
| Ảnh PNG giải mã từ OZJ mẫu `1_1diem.ozj` | Hỗ trợ tất cả BMD/OZJ khác |

**Đây là DEMO OFFLINE, không phải một bản port hoàn chỉnh của game ThanhThan PC.**

### File từ game PC đã được sử dụng

- Texture 64x64 trong `Assets.xcassets/GemTexture.imageset/gem.png` là ảnh đã trích xuất từ mẫu `1_1diem.ozj` mà người dùng cung cấp.
- Các mô hình 3D trong demo là hình học dựng mẫu bằng SceneKit, **không phải** mô hình đã giải mã từ `absolute_gunbow.bmd`.
- Không chứa hoặc chạy `Main.exe`, không kết nối/mô phỏng máy chủ ThanhThan, không thực hiện reverse-engineering giao thức bảo vệ.

### Yêu cầu

- Xcode chạy trên macOS, **hoặc** GitHub Actions với `macos-15`.
- iOS 15 trở lên, Swift 5, SceneKit/SwiftUI.
- Để cài ứng dụng: cần ký IPA bằng chứng chỉ Apple phù hợp. GitHub tạo IPA **chưa ký**.

### Cách build IPA qua GitHub Actions

1. Tạo repository GitHub riêng cho bản native (ví dụ `thanhthan-native-ios`). Không ghi đè repo WebView cũ nếu muốn giữ bản đó.
2. Trên PC, giải nén file ZIP dự án này.
3. Upload **nội dung** thư mục `ThanhThan_Native_iOS` lên root repo mới, bao gồm thư mục ẩn `.github/workflows` và `project.yml`. Dùng Git/GitHub Desktop để chắc chắn gửi cả thư mục `.github`.
4. Vào **Actions → Build ThanhThan Native iOS Prototype → Run workflow** (hoặc push vào `main` sẽ kích hoạt tự động).
5. Khi build thành công, mở run mới nhất → **Artifacts** → `ThanhThanNative-DEMO-unsigned-IPA` và tải file ZIP.
6. Giải nén ZIP lấy `ThanhThanNative-DEMO-unsigned.ipa`.
7. Ký IPA và cài lên iPhone bằng công cụ sideload phù hợp với tài khoản Apple. Không đổi đuôi ZIP thành IPA.

Nếu workflow lỗi, mở job `build`, sao chép log bước lỗi để sửa. **Xem kết quả workflow hiện tại để xác nhận build; không suy ra build thành công từ việc kiểm tra source.**

### Mở bằng Xcode (Mac)

```sh
brew install xcodegen
xcodegen generate --spec project.yml
open ThanhThanNative.xcodeproj
```

Để cài lên thiết bị thật bằng Xcode, chọn Team trong Signing & Capabilities và thay Bundle Identifier nếu cần.

### Công cụ trích xuất tài nguyên

`tools/inspect_bmd.py` – đọc header BMD MU thông thường (không giải mã hình học):

```sh
python3 tools/inspect_bmd.py absolute_gunbow.bmd
```

`tools/ozj_to_png.py` – thử trích ảnh JPEG từ OZJ mẫu (cần Pillow):

```sh
python3 -m pip install Pillow
python3 tools/ozj_to_png.py 1_1diem.ozj sample.png
```

Một số bản BMD/OZJ có mã hóa tùy biến và không thể dùng các công cụ này trực tiếp.

### Để tiến tới bản ThanhThan online thật

Cần chủ dự án/game server cho phép sử dụng tài nguyên và cung cấp mã nguồn client hoặc đặc tả giao thức kết nối hợp lệ, handshake, xác thực, dữ liệu nhân vật/bản đồ và mã hóa tương ứng. Không thể đạt kết quả tương đương chỉ bằng cách đóng gói EXE Windows thành IPA.
