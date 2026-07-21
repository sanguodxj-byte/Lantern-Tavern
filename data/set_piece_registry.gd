## SetPieceRoom 注册表（autoload，无 class_name，符合项目铁律）。
## 加载 res://data/set_pieces/ 下全部 .tres 的 SetPieceRoom，供 isaac 注入期按 id 查询。
## 纯数据定位器，不含游戏逻辑。新增房间 = 丢一个 .tres 进目录，无需改代码。
## 设计依据：docs/set_piece_room_design.md §4.2（仿 WeaponRegistry 模式）。
extends Node

var _pieces: Dictionary = {}   # String(id) -> SetPieceRoom

signal registry_ready
signal set_piece_registered(id: String)

func _ready() -> void:
	_load_all()
	registry_ready.emit()

func _load_all() -> void:
	var dir := DirAccess.open("res://data/set_pieces/")
	if dir == null:
		push_warning("[SetPieceRegistry] data/set_pieces/ 不存在")
		return
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if fname.ends_with(".tres") and not fname.ends_with(".import"):
			var res := load("res://data/set_pieces/" + fname) as SetPieceRoom
			if res != null and res.is_valid():
				if _pieces.has(res.id):
					push_error("[SetPieceRegistry] 重复 id: %s (%s)" % [res.id, fname])
				else:
					_pieces[res.id] = res
					set_piece_registered.emit(res.id)
			elif res != null:
				push_error("[SetPieceRegistry] .tres 校验失败（图案非法）: %s" % fname)
		fname = dir.get_next()
	dir.list_dir_end()

func get_set_piece(id: String) -> SetPieceRoom:
	return _pieces.get(id, null)

func get_all() -> Array[SetPieceRoom]:
	var out: Array[SetPieceRoom] = []
	for p in _pieces.values():
		out.append(p)
	return out

## 按约束过滤（zone/depth/role），供 isaac 注入期加权随机选择。
func filter_candidates(zone: int, depth: int, reserved_role: String) -> Array[SetPieceRoom]:
	var out: Array[SetPieceRoom] = []
	for p in _pieces.values():
		if not p.allowed_zones.is_empty() and not (zone in p.allowed_zones):
			continue
		if depth < p.min_depth or depth > p.max_depth:
			continue
		if reserved_role != "" and p.required_role != "" and p.required_role != reserved_role:
			continue
		if reserved_role != "" and reserved_role in p.blocked_roles:
			continue
		out.append(p)
	return out
