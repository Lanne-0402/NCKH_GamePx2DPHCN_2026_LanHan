# Game Pixel 2D – Hỗ trợ tập luyện phục hồi chức năng

Dự án nghiên cứu phát triển game 2D kết hợp nhận diện cử động cánh tay, hướng đến việc chuyển các bài tập phục hồi chức năng thành những thử thách tương tác trong game.

Người chơi thực hiện động tác để điều khiển tiến trình màn chơi, vượt chướng ngại vật và hoàn thành phiên tập. Dự án sử dụng Godot cho phần game và được thiết kế để tiếp nhận dữ liệu từ backend nhận diện chuyển động.

> **Trạng thái:** Đang phát triển. Phiên bản hiện tại sử dụng dữ liệu mô phỏng từ `MockPoseProvider`; chưa hoàn tất tích hợp camera và MediaPipe thực tế.

## Mục tiêu

* Xây dựng năm màn chơi gắn với các động tác tập luyện khác nhau.
* Cung cấp phản hồi trực quan về tiến trình, thời gian giữ tư thế và trạng thái tracking.
* Tách biệt logic game với nguồn dữ liệu nhận diện để thuận tiện phát triển và kiểm thử.
* Tạo nền tảng cho việc tích hợp backend nhận diện chuyển động.

## Tính năng

### Năm màn chơi

| Màn chơi               | Cơ chế tương tác                                              |
| ---------------------- | ------------------------------------------------------------- |
| Map 1 – Phá đá         | Hoàn thành động tác hợp lệ để phá vật cản                     |
| Map 2 – Nâng vật cản   | Giữ tư thế để tăng tiến trình nâng                            |
| Map 3 – Đẩy tường gai  | Giữ tư thế để đẩy lùi tường theo các hướng                    |
| Map 4 – Leo vách       | Kết hợp di chuyển của nhân vật và giữ tư thế để vượt từng bậc |
| Map 5 – Suối nước nóng | Thực hiện giãn cơ theo từng bên và tích lũy điểm thưởng       |

### Quản lý phiên tập

* Theo dõi số lần thực hiện động tác hợp lệ và bị từ chối.
* Chia phiên tập thành các giai đoạn, có thời gian nghỉ.
* Hiển thị tiến trình giữ tư thế và phản hồi trong quá trình chơi.
* Xử lý tạm dừng, mất tracking và hoàn thành phiên tập.
* Tổng kết kết quả sau màn chơi.

### Mô phỏng dữ liệu và kiểm thử

* Mô phỏng kết nối, calibration và dữ liệu pose.
* Mô phỏng động tác hợp lệ, động tác bị từ chối và giữ tư thế bị gián đoạn.
* Kiểm tra thông điệp theo contract dữ liệu.
* Có các smoke test cho hệ thống lõi và từng map.

## Công nghệ

| Thành phần             | Công nghệ                     |
| ---------------------- | ----------------------------- |
| Game engine            | Godot                         |
| Ngôn ngữ               | GDScript                      |
| Giao tiếp dữ liệu      | Contract thông điệp dạng JSON |
| Nguồn dữ liệu hiện tại | MockPoseProvider              |
| Backend dự kiến        | Python, MediaPipe             |

Cấu hình project hiện khai báo Godot `4.7`. Nên mở bằng phiên bản tương ứng để hạn chế khác biệt khi import tài nguyên.

## Tổ chức mã nguồn

| Đường dẫn                     | Nội dung                                               |
| ----------------------------- | ------------------------------------------------------ |
| `core/autoload/`              | Trạng thái và dữ liệu dùng chung                       |
| `core/exercise/`              | Quản lý phiên tập và độ ổn định tracking               |
| `core/pose/`                  | Giao diện nguồn dữ liệu pose và provider mô phỏng      |
| `maps/map_1/` – `maps/map_5/` | Scene và logic của từng màn chơi                       |
| `maps/shared/`                | Nhân vật, vật phẩm và thành phần môi trường dùng chung |
| `ui/screens/`                 | Màn hình bắt đầu, calibration và lựa chọn màn chơi     |
| `ui/shared/`                  | Thành phần giao diện dùng chung                        |
| `assets/`                     | Tài nguyên hình ảnh                                    |
| `tests/`                      | Các scene và script kiểm thử                           |

Xem thêm [PROJECT_STRUCTURE.md](PROJECT_STRUCTURE.md) và [JSON_Contract.docx](JSON_Contract.docx).

## Chạy dự án

1. Clone repository:

   ```bash
   git clone https://github.com/Hanari05/-NCKH-GamePixel2D_PHCN.git
   cd ./-NCKH-GamePixel2D_PHCN
   ```

2. Mở Godot và chọn **Import**.

3. Chọn file `project.godot`.

4. Chờ engine import tài nguyên.

5. Nhấn **F6** để chạy scene đang mở hoặc **F5** để chạy toàn bộ project.

> **Lưu ý phiên bản hiện tại:** Một số tham chiếu vẫn sử dụng `res://shared/` sau khi thư mục được chuyển sang `maps/shared/`. Cần đồng bộ các đường dẫn này trước khi chạy các màn chơi liên quan.

### Điều khiển mô phỏng

Các phím dưới đây phục vụ phát triển và kiểm thử, không phải thao tác điều khiển cuối cùng của sản phẩm.

| Phím | Chức năng                                          |
| ---- | -------------------------------------------------- |
| `T`  | Bật/tắt trạng thái tracking                        |
| `K`  | Ngắt/kết nối lại backend mô phỏng                  |
| `C`  | Bắt đầu calibration mô phỏng                       |
| `R`  | Mô phỏng một động tác hợp lệ hoặc chuỗi giữ tư thế |
| `F`  | Mô phỏng động tác bị từ chối                       |
| `N`  | Bỏ qua thời gian nghỉ tại màn chơi                 |

## Kiểm thử

Mở các scene trong `tests/core/` hoặc `tests/maps/` và chạy bằng **F6**.

Các kiểm thử tập trung vào:

* Vòng đời phiên tập.
* Dữ liệu yêu cầu gửi tới pose provider.
* Tiến trình động tác và giữ tư thế.
* Xử lý gián đoạn tracking.
* Điều kiện hoàn thành màn chơi.

Các test hiện có sử dụng dữ liệu mô phỏng, chưa thay thế cho kiểm thử với camera và người dùng thực tế.

## Giới hạn hiện tại

* Chưa hoàn tất kết nối backend nhận diện chuyển động thực tế.
* Nhiều thành phần hình ảnh vẫn là placeholder.
* Các asset pack đã được bổ sung nhưng chưa hoàn tất tích hợp vào màn chơi.
* Cần đồng bộ đường dẫn tài nguyên và tài liệu cấu trúc sau khi tổ chức lại thư mục.

Dự án hiện là prototype nghiên cứu, chưa được xác nhận hiệu quả lâm sàng và không thay thế hướng dẫn của chuyên gia phục hồi chức năng.

## Định hướng phát triển

* [ ] Đồng bộ đường dẫn tài nguyên và chạy lại các smoke test.
* [ ] Tích hợp backend camera/MediaPipe theo contract.
* [ ] Thay thế placeholder bằng tài nguyên hình ảnh phù hợp.
* [ ] Hoàn thiện phản hồi giao diện và hướng dẫn động tác.
* [ ] Kiểm thử trên dữ liệu thực tế.
* [ ] Bổ sung video demo và bản build trải nghiệm.

## Nhóm thực hiện

| Thành viên          | Vai trò chính                                                                              |
| ------------------- | ------------------------------------------------------------------------------------------ |
| Nông Thị Hồng Lan   | Chủ trì đề tài; backend và thuật toán nhận diện                                            |
| Nguyễn Ngọc Gia Hân | Front-end game; thiết kế và xây dựng năm map; xử lý tích hợp dữ liệu ở phía game; kiểm thử |

## Tài nguyên bên thứ ba

Dự án có sử dụng tài nguyên hình ảnh từ các nguồn bên ngoài. Quyền sử dụng và phân phối từng tài nguyên phụ thuộc vào điều khoản của tác giả tương ứng.

Khi sử dụng lại dự án, cần kiểm tra các file license/terms đi kèm asset pack. Nội dung nghiên cứu, mã nguồn và tài nguyên bên thứ ba không mặc nhiên có cùng điều kiện sử dụng.
