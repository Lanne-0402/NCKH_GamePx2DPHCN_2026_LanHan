# Cấu trúc dự án

```text
core/
  autoload/        Trạng thái dùng chung toàn game
  exercise/        Vòng đời và dữ liệu phiên tập
  pose/            Hợp đồng pose provider và dữ liệu mock
maps/shared/
  characters/      Nhân vật có thể dùng lại giữa các map
  collectibles/    Vật phẩm dùng lại
  world/           Mặt đất và nền cuộn dùng lại
ui/screens/
  start/            Màn hình chính
  calibration/      Kiểm tra và hiệu chỉnh camera
  map_selection/    Chọn map
  level_selection/  Chọn cấp độ trong map
maps/
  map_1/            Gameplay phá đá theo số lần lặp
    visuals/        Scene môi trường, mặt đất, vật cản và đích Map 1
    placeholders/   Scene tạm; hướng dẫn tư thế vẫn đang sử dụng
  map_2/            Gameplay nâng đá theo tiến trình giữ 5 giây
  map_3/            Gameplay đẩy lùi tường gai theo giữ 5 giây
  map_4/            Gameplay leo vách đá theo chạy bậc + giữ 5 giây
  map_5/            Gameplay suối nước nóng — căng 30 giây + thưởng điểm
tests/
  core/             Smoke test hạ tầng phiên tập
  maps/map_1/ – map_5/ Smoke test từng map
assets/             Các asset pack nguồn và tài nguyên dùng chung
  map_1/            Assets đã chọn và sao chép cho Map 1
    environment/    Nền rừng và tile mặt đất
    obstacles/      Hình ảnh vật cản
    goal/           Hình ảnh đích đến
    ui/             Texture giao diện và Theme
    characters/     Chờ assets nhân vật thay thế
    pose_guide/     Chờ hình minh họa tư thế
    effects/        Chờ hiệu ứng chuyên biệt
    audio/          Chờ âm thanh
```

Quy tắc phụ thuộc: các map có thể dùng `core`, `maps/shared` và `assets`; mã trong các thư mục dùng chung không được phụ thuộc ngược vào một map cụ thể.

Map 1 đã tích hợp assets môi trường, vật cản và theme cho bảng hướng dẫn/kết quả. Nhân vật và hướng dẫn tư thế vẫn dùng placeholder; các thư mục chờ assets chỉ chứa tài liệu hướng dẫn.

Cache `.godot/` được Godot tạo khi import và không được Git theo dõi. Giữ các file `.import` và `.uid` đi kèm tài nguyên/mã nguồn.
