extends SceneTree

## 大地图 UI 截图工具（对接真实地牢生成器）
##
## 实例化真实 ProceduralDungeon 场景，等待程序化生成完成，
## 从 dungeon.layout.grid 读取真实地牢数据，注入到 LargeMap + CombatMinimap，
## 然后截图。
##
## 必须以非 headless 模式运行（需要 GPU 渲染）。
## 输出: reports/large_map_capture/large_map.png

const SIZE := Vector2i(1920, 1080)
const OUT_ABS := "D:/123/Lantern Tavern/reports/large_map_capture"
const DUNGEON_SCENE := "res://scenes/expedition/procedural_dungeon.tscn"
const CAPTURE_SEED := 94021  # 与 dungeon_topdown_generation_test 一致的确定性种子

var _frames := 0
var _phase := 0
var _large_map: LargeMap = null
var _minimap: CombatMinimap = null
var _player: Node3D = null
var _dungeon: Node = null


func _initialize() -> void:
	print("[LargeMapCapture] START")
	DirAccess.make_dir_recursive_absolute("res://reports/large_map_capture")
	DirAccess.make_dir_recursive_absolute(OUT_ABS)
	root.size = SIZE
	# 深色背景
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.02, 0.03, 1.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)


func _process(_delta: float) -> bool:
	_frames += 1

	if _phase == 0:
		# 等待 autoloads 加载
		if _frames < 30:
			return false
		_setup_dungeon()
		_phase = 1
		_frames = 0
		return false

	if _phase == 1:
		# 等待地牢生成完成（需要多帧让 _ready → generate → layout 填充）
		if _frames < 60:
			return false
		if not _check_dungeon_ready():
			# 再等 60 帧
			if _frames < 120:
				return false
			printerr("[LargeMapCapture] FATAL: dungeon not ready after 120 frames")
			quit(1)
			return true
		_setup_map_ui()
		_phase = 2
		_frames = 0
		return false

	if _phase == 2:
		# 等待 LargeMap 渲染
		if _frames < 20:
			return false
		var img: Image = root.get_texture().get_image()
		if img == null or img.is_empty():
			printerr("[LargeMapCapture] FATAL: empty image")
			quit(1)
			return true
		img.save_png("%s/large_map.png" % OUT_ABS)
		print("[LargeMapCapture] wrote large_map.png size=%dx%d" % [img.get_width(), img.get_height()])
		_large_map.hide_map()
		_phase = 3
		_frames = 0
		return false

	if _phase == 3:
		if _frames < 10:
			return false
		var img2: Image = root.get_texture().get_image()
		if img2 != null and not img2.is_empty():
			img2.save_png("%s/minimap_comparison.png" % OUT_ABS)
			print("[LargeMapCapture] wrote minimap_comparison.png")
		print("[LargeMapCapture] DONE")
		quit(0)
		return true

	return false


## 实例化真实 ProceduralDungeon，设置确定性种子后加入场景树触发 _ready() 生成
func _setup_dungeon() -> void:
	print("[LargeMapCapture] instantiating ProceduralDungeon seed=%d" % CAPTURE_SEED)
	# 禁用敌人生成（避免无 GPU 资源累积崩溃，且截图不需要敌人）
	# 同时让 DungeonSpawner 使用 mock 节点
	var spawner: Node = root.get_node_or_null("DungeonSpawner")
	if spawner != null:
		spawner.set("use_mock_nodes", true)
		print("[LargeMapCapture] DungeonSpawner.use_mock_nodes = true")

	var packed := load(DUNGEON_SCENE) as PackedScene
	if packed == null:
		printerr("[LargeMapCapture] FATAL: cannot load %s" % DUNGEON_SCENE)
		quit(1)
		return
	_dungeon = packed.instantiate()
	# 设置确定性种子（必须在 add_child 前设置，_ready 里读）
	_dungeon.generation_seed = CAPTURE_SEED
	_dungeon.spawn_population_enabled = false
	_dungeon.dungeon_zone = 0
	root.add_child(_dungeon)
	print("[LargeMapCapture] dungeon added to tree, waiting for generation...")


## 检查地牢 layout 是否已生成完毕
func _check_dungeon_ready() -> bool:
	if _dungeon == null or not is_instance_valid(_dungeon):
		return false
	var layout = _dungeon.get("layout")
	if layout == null:
		return false
	var grid: Array = layout.get("grid")
	if grid.is_empty():
		return false
	var width: int = layout.get("width")
	var height: int = layout.get("height")
	if width <= 0 or height <= 0:
		return false
	print("[LargeMapCapture] dungeon ready: %dx%d grid, rooms=%d" % [
		width, height, layout.get("rooms").size()
	])
	return true


## 从真实地牢 layout 读取网格数据，注入到 CombatMinimap + LargeMap
func _setup_map_ui() -> void:
	var layout = _dungeon.get("layout")
	var grid: Array = layout.grid
	var tile_size: float = layout.tile_size
	var gw: int = layout.width
	var gh: int = layout.height
	var ox: float = -(float(gw) * tile_size) / 2.0
	var oz: float = -(float(gh) * tile_size) / 2.0

	print("[LargeMapCapture] setting up map UI: grid=%dx%d tile=%.1f" % [gw, gh, tile_size])

	# 创建小地图实例
	_minimap = CombatMinimap.new()
	_minimap.map_size = 220
	root.add_child(_minimap)

	# 注入真实地牢网格数据
	_minimap.set_grid_data(grid, Vector3(ox, 0, oz), tile_size)

	# 标记所有非空格子为已探索（模拟玩家已探索整层地牢）
	for gy in range(gh):
		for gx in range(gw):
			if gy < grid.size() and gx < grid[gy].size():
				if int(grid[gy][gx]) != 0:
					_minimap.mark_cell_explored(gx, gy)

	# 模拟玩家位置：使用 layout 的 player_spawn_cell
	var spawn_cell: Vector2i = layout.player_spawn_cell
	if layout.is_key_cell_missing(spawn_cell):
		# 回退到 start 房间中心
		if layout.room_roles.has("start"):
			var start_rect: Rect2i = layout.room_roles["start"]
			spawn_cell = start_rect.position + Vector2i(start_rect.size.x / 2, start_rect.size.y / 2)
		else:
			spawn_cell = Vector2i(gw / 2, gh / 2)

	var spawn_pos: Vector3 = layout.calc_player_spawn_pos()
	print("[LargeMapCapture] player spawn cell=%s pos=%s" % [str(spawn_cell), str(spawn_pos)])

	_player = Node3D.new()
	_player.name = "CapturePlayer"
	_player.rotation.y = 0.3  # 轻微偏转，让箭头有方向感
	root.add_child(_player)
	_player.global_position = spawn_pos
	_minimap.set_player(_player)

	# 创建大地图
	_large_map = LargeMap.new()
	root.add_child(_large_map)
	_large_map.set_minimap(_minimap)
	# 禁用小地图的 _process，防止 _refresh_references() 清空注入的数据
	_minimap.set_process(false)
	_large_map.show_map()
	print("[LargeMapCapture] map UI ready, has_grid=%s, explored=%d, large_map.vis=%s" % [
		str(_minimap._has_grid), _minimap.get_explored_count(), str(_large_map.visible)
	])
