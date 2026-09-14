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

Các thành phần dùng chung được tham chiếu qua `res://maps/shared/`. Icon Settings ở màn hình bắt đầu tham chiếu ảnh nguồn; Godot tự tạo cache khi import.

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

`tests/core/resource_paths_smoke_test.tscn` kiểm tra load và khởi tạo màn chính Map 1–5, các scene visuals Map 1 và các placeholder được liệt kê. Test này không thay thế kiểm thử gameplay. Sau thay đổi tài nguyên, cần chạy lại trên bản clone hoặc giải nén mới để tránh phụ thuộc cache cũ. Bản cập nhật này đã kiểm tra tĩnh đường dẫn; chưa xác nhận smoke test chạy thành công trong Godot.

## Giới hạn hiện tại

* Chưa hoàn tất kết nối backend nhận diện chuyển động thực tế.
* Nhiều thành phần hình ảnh vẫn là placeholder.
* Map 1 đã tích hợp assets môi trường, vật cản và theme cho bảng hướng dẫn/kết quả; giao diện chưa được xem là hoàn thiện.
* Nhân vật và hướng dẫn tư thế Map 1 vẫn là placeholder; hiệu ứng và âm thanh chuyên biệt còn chờ bổ sung. Xem [assets/map_1/README.md](assets/map_1/README.md).

Dự án hiện là prototype nghiên cứu, chưa được xác nhận hiệu quả lâm sàng và không thay thế hướng dẫn của chuyên gia phục hồi chức năng.

## Định hướng phát triển

* [x] Đồng bộ tham chiếu thành phần dùng chung sang `maps/shared/` và bỏ tham chiếu trực tiếp cache ở màn hình bắt đầu.
* [x] Bổ sung danh sách kiểm tra đường dẫn cho visuals Map 1 và màn chính Map 3–5.
* [ ] Chạy lại smoke test trong Godot trên bản clone hoặc giải nén mới.
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
