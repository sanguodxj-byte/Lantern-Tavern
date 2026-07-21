class_name ExtractionPortal
extends StaticBody3D

## 体素风撤离传送门。
## 用 BoxMesh 组合搭建（石质底座 + 四角发光符文柱 + 顶部方形光环 + 顶光），
## 取代原先的扁平 CylinderMesh 圆盘。collision_layer = LAYER_SCENE_OBJECT(64)，
## 使玩家 SelectRaycast(mask=72) 可命中并在准星悬停时显示交互提示。
## 内含 Area3D 实现走入自动撤离；interact() 支持按 [E] 主动撤离。

signal extraction_requested(player: Player)

const LAYER_SCENE_OBJECT := 64

@export var interaction_name := "撤离点"
@export var interaction_verb := "撤离"

var _stone_mat: StandardMaterial3D
var _rune_mat: StandardMaterial3D


func _ready() -> void:
	collision_layer = LAYER_SCENE_OBJECT
	collision_mask = 0
	set_meta("topdown_kind", "extraction")
	_ensure_materials()
	_build_visual()
	_add_pillar_collision()
	_add_trigger_area()


func _ensure_materials() -> void:
	if _stone_mat != null:
		return
	_stone_mat = StandardMaterial3D.new()
	_stone_mat.albedo_color = Color(0.22, 0.20, 0.18)
	_stone_mat.roughness = 0.95
	_rune_mat = StandardMaterial3D.new()
	_rune_mat.albedo_color = Color(0.0, 0.8, 0.6)
	_rune_mat.emission_enabled = true
	_rune_mat.emission = Color(0.0, 0.5, 0.4)
	_rune_mat.emission_energy_multiplier = 2.2
	_rune_mat.roughness = 0.4


func _box(node_name: String, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.name = node_name
	var mesh := BoxMesh.new()
	mesh.size = size
	m.mesh = mesh
	m.material_override = mat
	m.position = pos
	add_child(m)
	return m


func _build_visual() -> void:
	# 石质底座平台 + 边缘收边
	_box("PortalBase", Vector3(1.7, 0.12, 1.7), Vector3(0, 0.06, 0), _stone_mat)
	_box("PortalBaseRim", Vector3(1.8, 0.04, 1.8), Vector3(0, 0.12, 0), _stone_mat)
	# 中心发光地砖（踏入即撤离的视觉锚点）
	_box("PortalCoreTile", Vector3(1.0, 0.02, 1.0), Vector3(0, 0.14, 0), _rune_mat)
	# 四角发光符文柱
	var corners := [Vector3(-0.72, 0, -0.72), Vector3(0.72, 0, -0.72), Vector3(-0.72, 0, 0.72), Vector3(0.72, 0, 0.72)]
	for corner in corners:
		var cx := int(round(corner.x * 100.0))
		var cz := int(round(corner.z * 100.0))
		_box("RunePillar_%d_%d" % [cx, cz], Vector3(0.14, 1.4, 0.14), Vector3(corner.x, 0.82, corner.z), _rune_mat)
	# 顶部方形光环（四根横梁连接柱顶）
	_box("TopBeamNS_a", Vector3(0.12, 0.12, 1.56), Vector3(-0.72, 1.5, 0), _rune_mat)
	_box("TopBeamNS_b", Vector3(0.12, 0.12, 1.56), Vector3(0.72, 1.5, 0), _rune_mat)
	_box("TopBeamEW_a", Vector3(1.56, 0.12, 0.12), Vector3(0, 1.5, -0.72), _rune_mat)
	_box("TopBeamEW_b", Vector3(1.56, 0.12, 0.12), Vector3(0, 1.5, 0.72), _rune_mat)
	# 顶部中心光核
	_box("TopCore", Vector3(0.5, 0.5, 0.5), Vector3(0, 1.5, 0), _rune_mat)
	# 顶光：青绿色泛光，照亮传送门下方地面
	var light := OmniLight3D.new()
	light.name = "PortalLight"
	light.position = Vector3(0, 1.5, 0)
	light.light_color = Color(0.0, 0.8, 0.6)
	light.light_energy = 2.4
	light.omni_range = 9.0
	light.omni_attenuation = 1.2
	add_child(light)


func _add_pillar_collision() -> void:
	# 仅四角柱子参与碰撞（layer=64）：玩家射线可命中以显示悬停提示，
	# 同时玩家可从柱子间穿入触发 Area3D 撤离，不会被底座挡住。
	var corners := [Vector3(-0.72, 0, -0.72), Vector3(0.72, 0, -0.72), Vector3(-0.72, 0, 0.72), Vector3(0.72, 0, 0.72)]
	for corner in corners:
		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(0.14, 1.4, 0.14)
		col.shape = shape
		col.position = Vector3(corner.x, 0.82, corner.z)
		add_child(col)


func _add_trigger_area() -> void:
	var area := Area3D.new()
	area.name = "ExtractionArea"
	area.set_meta("topdown_kind", "extraction")
	area.position = Vector3(0, 1.0, 0)
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.8, 2.4, 1.8)
	col.shape = box
	area.add_child(col)
	area.body_entered.connect(_on_body_entered)
	add_child(area)


func _on_body_entered(body: Node3D) -> void:
	if body is Player:
		extraction_requested.emit(body as Player)


func interact(actor: Node = null) -> void:
	# 按 [E] 主动撤离；走入 Area3D 也会自动触发。actor 可选以兼容不同调用约定。
	var player_node: Node3D = actor if actor is Player else null
	if player_node == null:
		player_node = GameState.current_player
	if player_node is Player:
		extraction_requested.emit(player_node as Player)
