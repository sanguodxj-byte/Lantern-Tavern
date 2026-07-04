extends Control
## CD 径向扇形遮罩：在技能图标上绘制暗色扇形，覆盖未就绪区域。
## progress=0 → 全遮罩（刚释放）；progress=1 → 无遮罩（就绪）。
## 由 skill_bar.gd 每帧 queue_redraw 驱动。

var progress: float = 1.0

func _draw() -> void:
	if progress >= 1.0:
		return
	var r: float = min(size.x, size.y) * 0.5 - 2.0
	var center: Vector2 = size * 0.5
	# 暗色扇形从 12 点方向顺时针扫过 (1-progress) 圆周
	var sweep: float = (1.0 - progress) * TAU
	var point_count: int = max(8, int(sweep / 0.1))
	var pts: PackedVector2Array = PackedVector2Array([center])
	for i in range(point_count + 1):
		var angle: float = -PI / 2 + sweep * float(i) / float(point_count)
		pts.append(center + Vector2(cos(angle), sin(angle)) * r)
	draw_colored_polygon(pts, Color(0, 0, 0, 0.65))
	# 就绪边界高亮线
	if progress < 0.999:
		var edge_angle: float = -PI / 2 + sweep
		var edge_pt: Vector2 = center + Vector2(cos(edge_angle), sin(edge_angle)) * r
		draw_line(center, edge_pt, Color(1, 1, 0.6, 0.9), 1.5)
