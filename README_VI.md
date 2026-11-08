# HSONScanner 1.0.0

Scanner runtime dạng read-only dành cho kiểm thử tương thích giao diện iOS.

## Scanner thu thập

- Bundle ID, tên ứng dụng, version và build.
- Kiến trúc được biên dịch và model/phiên bản iOS.
- Các image/framework nằm bên trong bundle ứng dụng đang nạp.
- Danh mục class của ứng dụng thuộc các nhóm `UIView`, `UIViewController`, `UIApplicationDelegate` và `UISceneDelegate`, cùng superclass và image chứa class.
- Một snapshot nhẹ của root/presented view controller và các view cấp cao tại thời điểm quét.

## Scanner không làm

- Không đọc danh sách selector/phương thức riêng tư hay implementation.
- Không gọi hoặc hook phương thức của ứng dụng.
- Không đọc dữ liệu key, license, receipt, subscription, payment hay thông tin đăng nhập.
- Không gửi dữ liệu qua mạng.

## Đầu ra

Sau khi dylib được nạp và ứng dụng chạy khoảng 8 giây, báo cáo được ghi tại:

`<App Sandbox>/Documents/HSONScanReport.json`

Trên thiết bị thử nghiệm có quyền truy cập sandbox, có thể lấy file bằng công cụ quản lý file của môi trường đó. Nếu ứng dụng không cho phép truy cập Documents từ giao diện Files, dùng công cụ sandbox/file manager đã được môi trường của bạn cấp quyền.

## Build

Cần macOS hoặc môi trường build iOS đã cài:

- Theos
- iPhoneOS SDK tương thích
- `clang` và `make`

Đặt biến môi trường `THEOS`, sau đó chạy:

```sh
./build.sh
```

File được chép vào `dist/HSONScanner.dylib` nếu Theos build thành công.

Makefile nhắm `arm64` và `arm64e`. Thiết bị thực tế cần kiến trúc tương thích; `arm64e` không được mọi toolchain/SDK cũ hỗ trợ. Nếu toolchain báo không hỗ trợ arm64e, chỉnh `ARCHS := arm64` rồi build lại.

## Cấu hình nạp

`Filter.plist.template` chỉ là mẫu cho môi trường jailbreak dùng cơ chế filter theo bundle ID. Thay `REPLACE_WITH_VIDEO_STAR_BUNDLE_ID` bằng Bundle ID đọc từ IPA đã cài/được phép kiểm thử. Không dùng nguyên placeholder.

Vì bạn chọn môi trường cài đặt là “other”, chưa thể xác định cơ chế nạp dylib hoặc vị trí cài đặt chính xác. Các môi trường sideload/TrollStore/jailbreak khác nhau về loader, signing và sandbox. Không có cách an toàn để đoán một cấu hình cài đặt dùng chung.

## Giới hạn báo cáo

Đây là snapshot runtime, không phải danh sách API đầy đủ. Class bị strip, Swift metadata không khả dụng hoặc class được tạo sau thời điểm quét có thể không xuất hiện. Không dùng kết quả làm bằng chứng rằng một API là ổn định hay được nhà phát triển hỗ trợ.
