# Cấu trúc dự án

```text
core/
  autoload/           Trạng thái dùng chung, lưu tiến độ và kết quả
  exercise/           Vòng đời và dữ liệu phiên tập
  pose/               Hợp đồng pose provider và dữ liệu mock
maps/
  shared/
    characters/       Nhân vật Mk2 và player dùng chung
    collectibles/     Vật phẩm dùng chung
    world/            Mặt đất, nền cuộn và thành phần môi trường
  map_1/              Phá đá theo số lần lặp
  map_2/              Nâng đá theo tiến trình giữ 5 giây
  map_3/              Đẩy lùi tường gai theo giữ 5 giây
  map_4/              Leo vách đá theo chạy bậc và giữ 5 giây
  map_5/              Suối nước nóng, căng 30 giây và thưởng điểm
ui/
  shared/             Settings, HUD và hướng dẫn hai góc nhìn
  screens/
    start/            Màn hình chính
    calibration/      Kiểm tra và hiệu chỉnh camera
    map_selection/    Chọn map
    level_selection/  Chọn cấp độ trong map
    history/          Lịch sử buổi tập
tests/
  core/               Kiểm thử phiên tập, lưu dữ liệu, HUD và hướng dẫn
  maps/map_1/ – map_5/ Kiểm thử từng map
  visual/             Prototype và kiểm thử hình ảnh
  visual_output/      Ảnh đầu ra kiểm thử; không phải assets chạy game
tools/                Công cụ chuẩn bị và trích xuất assets
assets/
  characters/         Các phần nhân vật đã chọn cho prototype và Mk2
  shared/             Tài nguyên môi trường và giao diện dùng chung
  map_1/ – map_5/      Tài nguyên đã chọn theo map
```

Các map dùng `visuals/` cho cảnh vật hiện hành. Một số scene trong `placeholders/` vẫn được giữ để tương thích; hướng dẫn mới được dựng bằng `ui/shared/exercise_guide.gd`, `guide_actor.gd` và `guide_pose.gd`.

`ui/shared/game_presentation.gd` bố trí HUD, trạng thái có màu và khung camera chờ tích hợp. Nhân vật trong gameplay dùng `maps/shared/characters/player/`.

Các nhóm assets theo map có thể gồm `environment/`, `obstacles/`, `goal/`, `ui/`, `characters/`, `pose_guide/`, `effects/` và `audio/`. Không phải nhóm nào cũng đã có tài nguyên hoàn chỉnh. Repository hiện còn các asset pack nguồn; chúng không đồng nghĩa với tài nguyên đang được game sử dụng.

Quy tắc phụ thuộc: các map dùng `core`, `maps/shared`, `ui/shared` và `assets`. Thành phần dùng chung không nên phụ thuộc ngược vào scene cụ thể của một map.
