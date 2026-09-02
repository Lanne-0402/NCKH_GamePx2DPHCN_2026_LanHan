# Map 1 - Phá đá

Map 1 triển khai bài tập ép hai bả vai ra sau.

- `main_level.tscn` / `main_level.gd`: scene và luồng điều phối của Map 1.
- `map1_controller.gd`: tiến trình đá, Action Zone và hoạt cảnh kết thúc.
- `obstacle.tscn` / `obstacle.gd`: tảng đá riêng của Map 1.
- `placeholders/`: hình mẫu tách rời cho background, đá, hang kết thúc và hướng dẫn tư thế.

Map sử dụng lại `ExerciseSession`, pose provider, player, ground, scrolling background và star từ các thư mục dùng chung.

Quy chuẩn kích thước, pivot, collision và trạng thái animation được ghi tại `placeholders/PLACEHOLDER_SPEC.md`.
