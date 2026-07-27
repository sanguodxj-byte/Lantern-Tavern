extends RefCounted
## 装备槽“空槽剪影提示”图标生成器（从 tavern_equipment_panel.gd 拆出）。
## 纯图像处理：从生成的槽位背景贴图提取轮廓，flood-fill 得到实心剪影。

## 将槽位背景源图转换为浅色实心剪影提示图。
static func build_solid_slot_hint_image(source_image: Image, hint_color: Color, fill_neighbors: Array) -> Image:
	var image := source_image.duplicate()
	var width: int = image.get_width()
	var height: int = image.get_height()
	var boundary := PackedByteArray()
	boundary.resize(width * height)
	for y in range(height):
		for x in range(width):
			boundary[y * width + x] = 1 if _boundary_pixel(image, x, y) else 0

	# Flood-fill the matte from the canvas edge. Pixels not reached by that fill
	# are inside the silhouette and become the solid role hint.
	var exterior := PackedByteArray()
	exterior.resize(width * height)
	var queue: Array[Vector2i] = []
	for x in range(width):
		_queue_exterior(Vector2i(x, 0), width, height, boundary, exterior, queue)
		_queue_exterior(Vector2i(x, height - 1), width, height, boundary, exterior, queue)
	for y in range(height):
		_queue_exterior(Vector2i(0, y), width, height, boundary, exterior, queue)
		_queue_exterior(Vector2i(width - 1, y), width, height, boundary, exterior, queue)
	var queue_index: int = 0
	while queue_index < queue.size():
		var point := queue[queue_index]
		queue_index += 1
		for offset in fill_neighbors:
			_queue_exterior(point + offset, width, height, boundary, exterior, queue)

	for y in range(height):
		for x in range(width):
			var index: int = y * width + x
			if boundary[index] == 1 or exterior[index] == 0:
				image.set_pixel(x, y, hint_color)
			else:
				image.set_pixel(x, y, Color.TRANSPARENT)
	return image

static func _boundary_pixel(image: Image, x: int, y: int) -> bool:
	for offset_y in range(-1, 2):
		for offset_x in range(-1, 2):
			var sample_x := x + offset_x
			var sample_y := y + offset_y
			if sample_x < 0 or sample_x >= image.get_width() or sample_y < 0 or sample_y >= image.get_height():
				continue
			var pixel := image.get_pixel(sample_x, sample_y)
			if pixel.a > 0.01 and maxf(pixel.r, maxf(pixel.g, pixel.b)) > 0.10:
				return true
	return false

static func _queue_exterior(point: Vector2i, width: int, height: int, boundary: PackedByteArray, exterior: PackedByteArray, queue: Array[Vector2i]) -> void:
	if point.x < 0 or point.x >= width or point.y < 0 or point.y >= height:
		return
	var index: int = point.y * width + point.x
	if boundary[index] == 1 or exterior[index] == 1:
		return
	exterior[index] = 1
	queue.append(point)
