@tool
class_name VoxelProp
extends StaticBody3D

const VOXEL_UNIT := 1.0 / 32.0
const LAYER_SCENE_OBJECT := 64
const PROP_ATLAS := preload("res://assets/textures/props/voxel/voxel_prop_material_atlas_32px.png")
const PROP_SHADER := preload("res://assets/shaders/dungeon_terrain.gdshader")
const PROP_ATLAS_GRID := Vector2(4, 2)
const PROP_TILE_LAYOUT := {
	"wood_mid": Vector2(0, 0),
	"wood_dark": Vector2(1, 0),
	"black_iron": Vector2(2, 0),
	"cut_stone": Vector2(3, 0),
	"wax": Vector2(0, 1),
	"flame": Vector2(1, 1),
	"bone": Vector2(2, 1),
	"red_cloth": Vector2(3, 1),
}

@export var prop_kind := "chair":
	set(value):
		prop_kind = value
		if is_inside_tree():
			rebuild()

var _iron_mat: ShaderMaterial
var _wood_mat: ShaderMaterial
var _wood_dark_mat: ShaderMaterial
var _wax_mat: ShaderMaterial
var _bone_mat: ShaderMaterial
var _stone_mat: ShaderMaterial
var _cloth_mat: ShaderMaterial


func _ready() -> void:
	set_meta("voxel_style", "one_px_32px_per_meter")
	set_meta("voxel_unit_px", 1)
	set_meta("voxel_px_per_meter", 32)
	collision_layer = LAYER_SCENE_OBJECT
	collision_mask = 0
	rebuild()


func rebuild() -> void:
	_clear_generated()
	_ensure_materials()
	match prop_kind:
		"table":
			_build_table()
		"chair":
			_build_chair()
		"bench":
			_build_bench()
		"bucket":
			_build_bucket()
		"candles":
			_build_candles(false)
		"lit_candles":
			_build_candles(true)
		"grate":
			_build_grate()
		"jail":
			_build_jail()
		"fireplace":
			_build_fireplace()
		"small_crate":
			_build_crate(Vector3i(23, 22, 23))
		"large_crate":
			_build_crate(Vector3i(35, 34, 35))
		"barrel":
			_build_barrel()
		"chest":
			_build_chest()
		"large_chest", "boss_chest":
			_build_large_chest()
		"torch":
			_build_torch()
		"pillar":
			_build_pillar()
		"banner":
			_build_banner()
		"bones":
			_build_bones()
		"plank":
			_build_plank()
		"ruble", "rubble":
			_build_rubble()
		_:
			_build_crate_like()
	_add_collision()


func _clear_generated() -> void:
	for child in get_children():
		if child.get_meta("voxel_generated", false):
			child.queue_free()


func _ensure_materials() -> void:
	if _wood_mat != null:
		return
	_wood_mat = _make_prop_mat("wood_mid", 0.82, 0.15)
	_wood_dark_mat = _make_prop_mat("wood_dark", 0.88, 0.1)
	_iron_mat = _make_prop_mat("black_iron", 0.76, 0.35)
	_wax_mat = _make_prop_mat("wax", 0.92, 0.08)
	_bone_mat = _make_prop_mat("bone", 0.9, 0.08)
	_stone_mat = _make_prop_mat("cut_stone", 0.95, 0.12)
	_cloth_mat = _make_prop_mat("red_cloth", 0.88, 0.08)


func _make_prop_mat(tile_name: String, roughness: float, specular: float) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = PROP_SHADER
	mat.set_shader_parameter("atlas", PROP_ATLAS)
	mat.set_shader_parameter("tile_col_row", PROP_TILE_LAYOUT[tile_name])
	mat.set_shader_parameter("tile_span", Vector2(1, 1))
	mat.set_shader_parameter("atlas_grid", PROP_ATLAS_GRID)
	mat.set_shader_parameter("tile_repeat", Vector2(1, 1))
	mat.set_shader_parameter("roughness", roughness)
	mat.set_shader_parameter("specular", specular)
	return mat


func _box(name: String, size_px: Vector3i, center_px: Vector3, material: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(float(size_px.x), float(size_px.y), float(size_px.z)) * VOXEL_UNIT
	var instance := MeshInstance3D.new()
	instance.name = name
	instance.mesh = mesh
	instance.material_override = material
	instance.position = center_px * VOXEL_UNIT
	instance.set_meta("voxel_generated", true)
	add_child(instance)
	return instance


func _light(name: String, center_px: Vector3, energy: float, radius_m: float) -> OmniLight3D:
	var light := OmniLight3D.new()
	light.name = name
	light.position = center_px * VOXEL_UNIT
	light.light_color = Color(1.0, 0.58, 0.25)
	light.light_energy = energy
	light.light_size = 0.08
	light.omni_range = radius_m
	light.omni_attenuation = 1.7
	light.set_meta("voxel_generated", true)
	add_child(light)
	return light


func _build_table() -> void:
	_box("TableTop", Vector3i(64, 4, 34), Vector3(0, 24, 0), _wood_mat)
	_box("TableApronFront", Vector3i(64, 3, 3), Vector3(0, 20, 15), _wood_dark_mat)
	_box("TableApronBack", Vector3i(64, 3, 3), Vector3(0, 20, -15), _wood_dark_mat)
	_box("TableEndApronLeft", Vector3i(3, 3, 34), Vector3(-29, 20, 0), _wood_dark_mat)
	_box("TableEndApronRight", Vector3i(3, 3, 34), Vector3(29, 20, 0), _wood_dark_mat)
	for x in [-26, 26]:
		for z in [-13, 13]:
			_box("Leg_%d_%d" % [x, z], Vector3i(5, 22, 5), Vector3(x, 11, z), _wood_dark_mat)


func _build_chair() -> void:
	_box("Seat", Vector3i(19, 4, 19), Vector3(0, 14, 0), _wood_mat)
	_box("BackPanel", Vector3i(21, 18, 3), Vector3(0, 27, -9), _wood_mat)
	for x in [-8, 8]:
		for z in [-7, 7]:
			_box("Leg_%d_%d" % [x, z], Vector3i(3, 14, 3), Vector3(x, 7, z), _wood_dark_mat)
	for x in [-8, 8]:
		_box("BackPost_%d" % x, Vector3i(3, 29, 3), Vector3(x, 20, -9), _wood_dark_mat)


func _build_bench() -> void:
	_box("BenchSeat", Vector3i(64, 4, 13), Vector3(0, 15, 0), _wood_mat)
	_box("BenchFrontRail", Vector3i(64, 3, 3), Vector3(0, 11, 7), _wood_dark_mat)
	_box("BenchBackRail", Vector3i(64, 3, 3), Vector3(0, 11, -7), _wood_dark_mat)
	for x in [-27, 27]:
		for z in [-4, 4]:
			_box("Leg_%d_%d" % [x, z], Vector3i(5, 14, 5), Vector3(x, 7, z), _wood_dark_mat)


func _build_bucket() -> void:
	_box("BucketBottom", Vector3i(15, 3, 15), Vector3(0, 2, 0), _wood_dark_mat)
	_box("BucketFront", Vector3i(17, 17, 3), Vector3(0, 10, 7), _wood_mat)
	_box("BucketBack", Vector3i(17, 17, 3), Vector3(0, 10, -7), _wood_mat)
	_box("BucketLeft", Vector3i(3, 17, 17), Vector3(-7, 10, 0), _wood_mat)
	_box("BucketRight", Vector3i(3, 17, 17), Vector3(7, 10, 0), _wood_mat)
	_box("IronBandLow", Vector3i(19, 2, 19), Vector3(0, 6, 0), _iron_mat)
	_box("IronBandHigh", Vector3i(19, 2, 19), Vector3(0, 15, 0), _iron_mat)


func _build_candles(lit: bool) -> void:
	_box("CandleTray", Vector3i(17, 1, 5), Vector3(0, 0.5, 0), _iron_mat)
	for i in range(3):
		var x: int = int([-5, 0, 5][i])
		var height: int = int([9, 12, 7][i])
		_box("Candle%d" % i, Vector3i(3, height, 3), Vector3(x, height * 0.5, 0), _wax_mat)


func _build_grate() -> void:
	for x in [-12, -6, 0, 6, 12]:
		_box("BarX_%d" % x, Vector3i(3, 2, 31), Vector3(x, 1, 0), _iron_mat)
	for z in [-12, -4, 4, 12]:
		_box("BarZ_%d" % z, Vector3i(31, 2, 3), Vector3(0, 2, z), _iron_mat)


func _build_jail() -> void:
	_box("TopRail", Vector3i(61, 5, 5), Vector3(0, 63, 0), _iron_mat)
	_box("BottomRail", Vector3i(61, 5, 5), Vector3(0, 2, 0), _iron_mat)
	for x in [-24, -12, 0, 12, 24]:
		_box("Bar_%d" % x, Vector3i(3, 62, 3), Vector3(x, 32, 0), _iron_mat)
	for y in [22, 43]:
		_box("Crossbar_%d" % y, Vector3i(61, 3, 3), Vector3(0, y, 0), _iron_mat)


func _build_fireplace() -> void:
	_box("HearthBase", Vector3i(45, 5, 21), Vector3(0, 2.5, 0), _stone_mat)
	_box("BackStone", Vector3i(45, 35, 5), Vector3(0, 20, -8), _stone_mat)
	_box("LeftJamb", Vector3i(7, 33, 17), Vector3(-19, 19, 0), _stone_mat)
	_box("RightJamb", Vector3i(7, 33, 17), Vector3(19, 19, 0), _stone_mat)
	_box("Mantel", Vector3i(49, 7, 19), Vector3(0, 37, 0), _stone_mat)
	_box("FireLogA", Vector3i(23, 4, 5), Vector3(0, 7, 2), _wood_dark_mat)
	_box("FireLogB", Vector3i(5, 4, 21), Vector3(4, 9, 0), _wood_dark_mat)


func _build_crate(size_px: Vector3i) -> void:
	var half_y := size_px.y * 0.5
	_box("CrateCore", size_px, Vector3(0, half_y, 0), _wood_mat)
	_box("CrateBandTop", Vector3i(size_px.x + 2, 3, size_px.z + 2), Vector3(0, size_px.y - 4, 0), _wood_dark_mat)
	_box("CrateBandBottom", Vector3i(size_px.x + 2, 3, size_px.z + 2), Vector3(0, 5, 0), _wood_dark_mat)
	_box("CrateCrossA", Vector3i(3, size_px.y + 1, size_px.z + 2), Vector3(-size_px.x * 0.28, half_y, 0), _wood_dark_mat)
	_box("CrateCrossB", Vector3i(3, size_px.y + 1, size_px.z + 2), Vector3(size_px.x * 0.28, half_y, 0), _wood_dark_mat)


func _build_barrel() -> void:
	var slice_centers := [-13, -7, 0, 7, 13]
	var slice_widths := [5, 7, 7, 7, 5]
	var belly_depths := [17, 25, 29, 25, 17]
	var cap_depths := [13, 21, 25, 21, 13]
	for i in range(slice_centers.size()):
		var x: int = slice_centers[i]
		var width: int = slice_widths[i]
		_box("BarrelWoodSlice_%d" % i, Vector3i(width, 28, belly_depths[i]), Vector3(x, 15, 0), _wood_mat)
		_box("TopCapSlice_%d" % i, Vector3i(width, 3, cap_depths[i]), Vector3(x, 30.5, 0), _wood_dark_mat)
		_box("BottomCapSlice_%d" % i, Vector3i(width, 3, cap_depths[i]), Vector3(x, 1.5, 0), _wood_dark_mat)
		_box("IronBandLowSlice_%d" % i, Vector3i(width, 3, belly_depths[i] + 2), Vector3(x, 8, 0), _iron_mat)
		_box("IronBandHighSlice_%d" % i, Vector3i(width, 3, belly_depths[i] + 2), Vector3(x, 23, 0), _iron_mat)
	_box("FrontStaveCenter", Vector3i(3, 24, 3), Vector3(0, 15, 15), _wood_dark_mat)
	_box("BackStaveCenter", Vector3i(3, 24, 3), Vector3(0, 15, -15), _wood_dark_mat)
	_box("LeftStaveShadow", Vector3i(3, 24, 13), Vector3(-15, 15, 0), _wood_dark_mat)
	_box("RightStaveShadow", Vector3i(3, 24, 13), Vector3(15, 15, 0), _wood_dark_mat)


func _build_chest() -> void:
	_box("ChestBase", Vector3i(33, 17, 23), Vector3(0, 8.5, 0), _wood_mat)
	_box("ChestLid", Vector3i(35, 9, 25), Vector3(0, 21.5, 0), _wood_dark_mat)
	_box("IronBandLeft", Vector3i(3, 29, 27), Vector3(-12, 14.5, 0), _iron_mat)
	_box("IronBandRight", Vector3i(3, 29, 27), Vector3(12, 14.5, 0), _iron_mat)
	_box("LockPlate", Vector3i(7, 7, 3), Vector3(0, 16, 12), _iron_mat)


func _build_large_chest() -> void:
	_box("BossChestPlinth", Vector3i(65, 5, 39), Vector3(0, 2.5, 0), _wood_dark_mat)
	_box("BossChestBase", Vector3i(61, 22, 35), Vector3(0, 13, 0), _wood_mat)
	_box("BossChestLidLower", Vector3i(65, 6, 39), Vector3(0, 25, 0), _wood_dark_mat)
	_box("BossChestLidMid", Vector3i(57, 6, 35), Vector3(0, 30, 0), _wood_dark_mat)
	_box("BossChestLidCrown", Vector3i(45, 5, 29), Vector3(0, 35.5, 0), _wood_dark_mat)
	_box("BossChestLidRidge", Vector3i(25, 3, 15), Vector3(0, 39.5, 0), _wood_dark_mat)
	for x in [-31, 31]:
		for z in [-18, 18]:
			_box("BossIronCorner_%d_%d" % [x, z], Vector3i(5, 41, 5), Vector3(x, 20.5, z), _iron_mat)
	_box("BossIronRimFront", Vector3i(67, 5, 3), Vector3(0, 23, 20), _iron_mat)
	_box("BossIronRimBack", Vector3i(67, 5, 3), Vector3(0, 23, -20), _iron_mat)
	_box("BossIronLidRidge", Vector3i(31, 3, 5), Vector3(0, 41.5, 0), _iron_mat)
	_box("BossIronBandLeft", Vector3i(5, 36, 3), Vector3(-16, 18, 20), _iron_mat)
	_box("BossIronBandRight", Vector3i(5, 36, 3), Vector3(16, 18, 20), _iron_mat)
	_box("BossLockPlate", Vector3i(15, 15, 3), Vector3(0, 18, 21), _iron_mat)
	_box("BossRewardSeal", Vector3i(7, 7, 1), Vector3(0, 18, 22.5), _cloth_mat)
	_box("BossSideHandleLeft", Vector3i(7, 5, 13), Vector3(-36, 20, 0), _iron_mat)
	_box("BossSideHandleRight", Vector3i(7, 5, 13), Vector3(36, 20, 0), _iron_mat)
	for i in range(3):
		_box("BossIronChevronA_%d" % i, Vector3i(13, 3, 3), Vector3(-19 + i * 11, 30 - i * 5, 21), _iron_mat)
		_box("BossIronChevronB_%d" % i, Vector3i(13, 3, 3), Vector3(19 - i * 11, 30 - i * 5, 21), _iron_mat)


func _build_torch() -> void:
	_box("WallPlate", Vector3i(5, 5, 3), Vector3(0, 30, 0), _iron_mat)
	_box("PlateRivetTop", Vector3i(1, 1, 5), Vector3(0, 32, -1), _iron_mat)
	_box("PlateRivetBottom", Vector3i(1, 1, 5), Vector3(0, 28, -1), _iron_mat)
	_box("Handle", Vector3i(3, 7, 3), Vector3(0, 27, -5), _wood_dark_mat)
	_box("HandleWrapLow", Vector3i(5, 1, 5), Vector3(0, 24, -5), _iron_mat)
	_box("HandleWrapHigh", Vector3i(5, 1, 5), Vector3(0, 30, -5), _iron_mat)
	_box("SconceArm", Vector3i(3, 3, 9), Vector3(0, 32, -6), _iron_mat)
	_box("CupBase", Vector3i(7, 3, 7), Vector3(0, 35, -10), _iron_mat)
	_box("CupLeftLip", Vector3i(3, 3, 7), Vector3(-3, 36, -10), _iron_mat)
	_box("CupRightLip", Vector3i(3, 3, 7), Vector3(3, 36, -10), _iron_mat)
	var light := _light("OmniLight3D", Vector3(0, 39, -10), 3.4, 11.0)
	light.omni_attenuation = 0.65
	light.distance_fade_enabled = true
	light.distance_fade_begin = 24.0
	light.distance_fade_length = 10.0
	# 标记为由 LightingController 管理的火光（闪烁 + 酒馆档案收束范围）。
	# 范围/亮度仍保持地牢可见性约束（range>=10 / energy>=3.2），不做全局改动。
	light.add_to_group("flicker_light")
	light.set_meta("light_role", "torch")


func _build_pillar() -> void:
	_box("PillarBase", Vector3i(19, 5, 19), Vector3(0, 2.5, 0), _stone_mat)
	_box("PillarShaft", Vector3i(13, 88, 13), Vector3(0, 49, 0), _stone_mat)
	_box("PillarCapital", Vector3i(21, 7, 21), Vector3(0, 94.5, 0), _stone_mat)


func _build_banner() -> void:
	_box("BannerPole", Vector3i(3, 31, 3), Vector3(-12, 15.5, 0), _wood_dark_mat)
	_box("BannerTopRail", Vector3i(31, 3, 3), Vector3(0, 29, 0), _wood_dark_mat)
	_box("BannerCloth", Vector3i(27, 23, 2), Vector3(2, 16, 0), _cloth_mat)
	_box("BannerTailLeft", Vector3i(9, 7, 2), Vector3(-4, 2, 0), _cloth_mat)
	_box("BannerTailRight", Vector3i(9, 7, 2), Vector3(10, 2, 0), _cloth_mat)


func _build_bones() -> void:
	_box("BoneA", Vector3i(19, 3, 3), Vector3(0, 2, 0), _bone_mat)
	_box("BoneB", Vector3i(3, 3, 17), Vector3(5, 3, 4), _bone_mat)
	_box("SkullBlock", Vector3i(7, 6, 6), Vector3(-8, 4, 4), _bone_mat)


func _build_plank() -> void:
	_box("Plank", Vector3i(41, 3, 9), Vector3(0, 2, 0), _wood_mat)
	_box("EndCapA", Vector3i(3, 4, 9), Vector3(-20, 2, 0), _wood_dark_mat)
	_box("EndCapB", Vector3i(3, 4, 9), Vector3(20, 2, 0), _wood_dark_mat)


func _build_rubble() -> void:
	_box("RubbleBase", Vector3i(23, 1, 15), Vector3(0, 0.5, 2), _stone_mat)
	_box("StoneA", Vector3i(9, 5, 7), Vector3(-7, 3, 4), _bone_mat)
	_box("StoneB", Vector3i(7, 4, 9), Vector3(4, 2, -3), _bone_mat)
	_box("StoneC", Vector3i(5, 3, 5), Vector3(11, 2, 7), _bone_mat)


func _build_crate_like() -> void:
	_box("VoxelBlock", Vector3i(24, 24, 24), Vector3(0, 12, 0), _wood_mat)
	_box("VoxelBand", Vector3i(26, 4, 26), Vector3(0, 16, 0), _wood_dark_mat)


func _add_collision() -> void:
	# 若本 VoxelProp 直接挂在某个动态刚体（RigidBody3D，例如可拾取物 PickableItem、
	# 被投掷物）之下，碰撞由该刚体自身提供（见 pickable_item.gd::_fit_collision_to_visual）。
	# 此处若再添加一个独立静态碰撞体，会与父刚体自身的碰撞体在空间上重叠，而父刚体的
	# 碰撞掩码通常包含 scene_object 层 -> 物理求解器把刚体从“自己的”静态碰撞体里弹开，
	# 表现为物体一运行就飞走。因此这种情况下跳过碰撞体生成。
	# 向上遍历所有祖先：只要本 VoxelProp 最终挂在某个动态刚体（RigidBody3D，例如可拾取物
	# PickableItem、被投掷物 ThrownItem）之下，碰撞就应由该刚体自身提供（见
	# pickable_item.gd / thrown_item.gd 的 _fit_collision_to_visual）。此处若再叠加一个独立
	# 静态碰撞体，会与父刚体的碰撞体在空间上重叠，而父刚体的掩码通常包含 scene_object 层 ->
	# 物理求解器把刚体从“自己的”静态碰撞体里弹开，表现为物体一运行就飞走。
	# 因此这种情况下跳过碰撞体生成。直接父节点或更深层的祖先都算。
	if _is_under_rigid_body():
		return
	var aabb := _visual_bounds()
	if aabb.size == Vector3.ZERO:
		return
	var shape := BoxShape3D.new()
	shape.size = aabb.size
	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	collision.shape = shape
	collision.position = aabb.position + aabb.size * 0.5
	collision.set_meta("voxel_generated", true)
	add_child(collision)


func _is_under_rigid_body() -> bool:
	var node := get_parent()
	while node != null:
		if node is RigidBody3D:
			return true
		node = node.get_parent()
	return false


func _visual_bounds() -> AABB:
	var has_bounds := false
	var result := AABB()
	for child in get_children():
		if not child is MeshInstance3D:
			continue
		var mesh_instance := child as MeshInstance3D
		var aabb := mesh_instance.get_aabb()
		aabb.position += mesh_instance.position
		if not has_bounds:
			result = aabb
			has_bounds = true
		else:
			result = result.merge(aabb)
	return result if has_bounds else AABB()
