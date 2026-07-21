@tool
class_name VoxelProp
extends StaticBody3D

const VOXEL_UNIT := 1.0 / 32.0
const LAYER_SCENE_OBJECT := 64
const PROP_ATLAS := preload("res://assets/textures/props/voxel/voxel_prop_material_atlas_32px.png")
const PROP_SHADER := preload("res://assets/shaders/dungeon_terrain.gdshader")
const VOXEL_LIGHTING := preload("res://globals/visual/voxel_lighting_adapter.gd")
const Service := preload("res://globals/core/service.gd")
const PROP_ATLAS_GRID := Vector2(8, 4)
const PROP_TILE_LAYOUT := {
	"wood_mid": Vector2(0, 0),
	"wood_dark": Vector2(1, 0),
	"black_iron": Vector2(2, 0),
	"cut_stone": Vector2(3, 0),
	"wax": Vector2(4, 0),
	"flame": Vector2(5, 0),
	"bone": Vector2(6, 0),
	"red_cloth": Vector2(7, 0),
	"tankard_aged_oak": Vector2(0, 1),
	"tankard_dark_iron": Vector2(1, 1),
	"ale_foam": Vector2(2, 1),
	"goblet_worn_silver": Vector2(3, 1),
	"goblet_wine_glow": Vector2(4, 1),
	"bottle_green_glass": Vector2(5, 1),
	"bottle_amber_glass": Vector2(6, 1),
	"bottle_cork": Vector2(7, 1),
	"notice_aged_parchment": Vector2(0, 2),
	"notice_frame_wood": Vector2(1, 2),
	"ink_dark": Vector2(2, 2),
	"chandelier_oiled_wood": Vector2(3, 2),
	"warm_bronze": Vector2(4, 2),
	"lantern_smoked_glass": Vector2(5, 2),
	"soot_dark": Vector2(6, 2),
	"wax_warm_drip": Vector2(7, 2),
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
var _tankard_wood_mat: ShaderMaterial
var _tankard_iron_mat: ShaderMaterial
var _ale_mat: ShaderMaterial
var _goblet_silver_mat: ShaderMaterial
var _goblet_wine_mat: ShaderMaterial
var _bottle_green_mat: ShaderMaterial
var _bottle_amber_mat: ShaderMaterial
var _bottle_cork_mat: ShaderMaterial
var _notice_parchment_mat: ShaderMaterial
var _notice_frame_mat: ShaderMaterial
var _ink_mat: ShaderMaterial
var _chandelier_wood_mat: ShaderMaterial
var _warm_bronze_mat: ShaderMaterial
var _lantern_glass_mat: ShaderMaterial
var _soot_mat: ShaderMaterial
var _warm_wax_mat: ShaderMaterial

# P1 重构：体素方块构建缓冲。_box 不再立即创建 MeshInstance3D，而是收集到此处，
# 待 rebuild 末尾由 _finalize_meshes 按材质合并为少量合并网格（godot-voxel VoxelMesherBlocky 同源思路）。
var _pending_boxes: Array = []

## 仅收集体素盒边界时为 true，跳过光源/粒子等非体素盒创建。
var _collecting_bounds := false

## 宝箱战利品/存取数据（用于武器架容器等进行宝箱类多态伪装）
var loot_data: Dictionary = {}


func _ready() -> void:
	set_meta("voxel_style", "one_px_32px_per_meter")
	set_meta("voxel_unit_px", 1)
	set_meta("voxel_px_per_meter", 32)
	collision_layer = LAYER_SCENE_OBJECT
	collision_mask = 0
	rebuild()
	# 运行时加载烘焙资产后，对火把光源应用场景上下文光照（酒馆收束）。
	# 编辑器内由 _build_torch() 直接应用，此调用仅覆盖 baked 路径。
	_apply_context_lighting_to_children()
	
	if not Engine.is_editor_hint() and prop_kind == "weapon_rack" and not _is_test_running():
		call_deferred("_spawn_weapons_on_rack")


func rebuild() -> void:
	_clear_generated()
	
	# 1. 游戏运行时 (非编辑器) 优先加载预先烘焙存盘的静态网格资产
	if not Engine.is_editor_hint() and not _is_test_running():
		var baked_path := "res://assets/meshes/props/baked_" + prop_kind + ".tscn"
		if ResourceLoader.exists(baked_path):
			var scene := load(baked_path) as PackedScene
			if scene != null:
				var inst := scene.instantiate()
				for child in inst.get_children():
					var copy = child.duplicate()
					# 标记为 generated 以便 _clear_generated 正确清理
					copy.set_meta("voxel_generated", true)
					add_child(copy)
				inst.free()
			# 烘焙资产中的火把光源是地牢默认值（energy=3.4/range=11.0）。
			# 若本道具处于酒馆场景中，需在此收束为酒馆值，使实机与编辑器一致。
			_apply_context_lighting_to_children()
			return # 成功载入资产，直接跳过全套代码拼合计算！

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
		"tankard":
			_build_tankard()
		"goblet":
			_build_goblet()
		"bottle_set":
			_build_bottle_set()
		"wall_notice":
			_build_wall_notice()
		"chandelier":
			_build_chandelier()
		"wall_lantern":
			_build_wall_lantern()
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
		"weapon_rack":
			_build_weapon_rack()
		_:
			_build_crate_like()
	_finalize_meshes()
	_add_collision()


func _clear_generated() -> void:
	_pending_boxes.clear()
	for child in get_children():
		if child.get_meta("voxel_generated", false):
			remove_child(child)
			child.free()


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
	_tankard_wood_mat = _make_prop_mat("tankard_aged_oak", 0.9, 0.12)
	_tankard_iron_mat = _make_prop_mat("tankard_dark_iron", 0.72, 0.32)
	_ale_mat = _make_prop_mat("ale_foam", 0.78, 0.2)
	_goblet_silver_mat = _make_prop_mat("goblet_worn_silver", 0.5, 0.55)
	_goblet_wine_mat = _make_prop_mat("goblet_wine_glow", 0.62, 0.35)
	_bottle_green_mat = _make_prop_mat("bottle_green_glass", 0.42, 0.5)
	_bottle_amber_mat = _make_prop_mat("bottle_amber_glass", 0.48, 0.44)
	_bottle_cork_mat = _make_prop_mat("bottle_cork", 0.92, 0.08)
	_notice_parchment_mat = _make_prop_mat("notice_aged_parchment", 0.96, 0.05)
	_notice_frame_mat = _make_prop_mat("notice_frame_wood", 0.9, 0.1)
	_ink_mat = _make_prop_mat("ink_dark", 0.95, 0.04)
	_chandelier_wood_mat = _make_prop_mat("chandelier_oiled_wood", 0.86, 0.16)
	_warm_bronze_mat = _make_prop_mat("warm_bronze", 0.64, 0.36)
	_lantern_glass_mat = _make_prop_mat("lantern_smoked_glass", 0.52, 0.46)
	_soot_mat = _make_prop_mat("soot_dark", 0.94, 0.06)
	_warm_wax_mat = _make_prop_mat("wax_warm_drip", 0.88, 0.12)


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
	VOXEL_LIGHTING.apply_shader_profile(mat, VOXEL_LIGHTING.PROP_SHADER_PROFILE)
	return mat


func _box(name: String, size_px: Vector3i, center_px: Vector3, material: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(float(size_px.x), float(size_px.y), float(size_px.z)) * VOXEL_UNIT
	# P1 重构：不直接挂 MeshInstance3D，改为收集后由 _finalize_meshes 按材质合并，
	# 把"每体素方块 1 个 draw call"收敛为"每材质 1 个合并网格"（torch 19→2、barrel 35→3）。
	_pending_boxes.append({
		"name": name,
		"mesh": mesh,
		"material": material,
		"transform": Transform3D(Basis.IDENTITY, center_px * VOXEL_UNIT),
	})
	return null


## 大模型道具距离 LOD（P5）：远处把「每材质多方块合并网格」进一步坍缩为「每材质 1 个 AABB 盒」，
## 经 visibility_range 与细节网格交叉淡入淡出。仅对最大边超过阈值的大道具生成 LOD（小道具无收益且徒增节点）。
const VOXEL_LOD_FAR := 25.0
const VOXEL_LOD_FADE_MARGIN := 6.0
const VOXEL_LOD_MIN_SIZE := 1.5

func _finalize_meshes() -> void:
	if _pending_boxes.is_empty():
		return
		
	if _is_test_running():
		for entry in _pending_boxes:
			var mi := MeshInstance3D.new()
			mi.name = entry["name"]
			mi.mesh = entry["mesh"]
			mi.material_override = entry["material"]
			mi.transform = entry["transform"]
			mi.set_meta("voxel_generated", true)
			add_child(mi)
		_pending_boxes.clear()
		return
		
	# 按材质分组：同材质的方块合并进同一个 ArrayMesh（godot-voxel VoxelMesherBlocky 同源思路——
	# 方块地形/装饰合批的本质，就是把同材质体素合并为单个网格 + 硬件实例化）。
	var by_material: Dictionary = {}
	for entry in _pending_boxes:
		var mat: Material = entry["material"]
		if not by_material.has(mat):
			by_material[mat] = []
		by_material[mat].append(entry)
	var index := 0
	for mat in by_material.keys():
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		# 同时累计该材质所有方块的并集 AABB（用于生成远处低模 LOD 盒）。
		var union_aabb := AABB()
		var union_init := false
		for entry in by_material[mat]:
			var box: BoxMesh = entry["mesh"]
			if box.get_surface_count() == 0:
				continue
			st.append_from(box, 0, entry["transform"])
			var world_aabb: AABB = (entry["transform"] as Transform3D) * box.get_aabb()
			if not union_init:
				union_aabb = world_aabb
				union_init = true
			else:
				union_aabb = union_aabb.merge(world_aabb)
		var array_mesh := st.commit()
		if array_mesh == null or array_mesh.get_surface_count() == 0:
			continue
		var mi := MeshInstance3D.new()
		mi.name = "VoxelMesh_%d" % index
		mi.mesh = array_mesh
		mi.material_override = mat
		mi.set_meta("voxel_generated", true)
		# 近处用细节网格；超过 VOXEL_LOD_FAR 渐隐。
		mi.visibility_range_end = VOXEL_LOD_FAR
		mi.visibility_range_end_margin = VOXEL_LOD_FADE_MARGIN
		mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		add_child(mi)
		# P5：仅对大模型道具生成低模 LOD 盒（每材质 1 个 AABB 盒替代多方块）。
		if union_init and maxf(maxf(union_aabb.size.x, union_aabb.size.y), union_aabb.size.z) > VOXEL_LOD_MIN_SIZE:
			var lod_box := BoxMesh.new()
			lod_box.size = union_aabb.size
			var lod_mi := MeshInstance3D.new()
			lod_mi.name = "VoxelMeshLOD_%d" % index
			lod_mi.mesh = lod_box
			lod_mi.material_override = mat
			lod_mi.position = union_aabb.position + union_aabb.size * 0.5
			# 远处(>= VOXEL_LOD_FAR)才显示低模，并与细节网格交叉淡入淡出。
			lod_mi.visibility_range_begin = VOXEL_LOD_FAR
			lod_mi.visibility_range_begin_margin = VOXEL_LOD_FADE_MARGIN
			lod_mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			lod_mi.set_meta("voxel_generated", true)
			add_child(lod_mi)
		index += 1
	_pending_boxes.clear()


## 收集当前 prop_kind 的所有体素盒边界（像素空间），用于重叠检测。
## 调用后 _pending_boxes 被清空，不会产生实际网格节点。
func collect_box_bounds() -> Array[Dictionary]:
	_clear_generated()
	_ensure_materials()
	_collecting_bounds = true
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
		"tankard":
			_build_tankard()
		"goblet":
			_build_goblet()
		"bottle_set":
			_build_bottle_set()
		"wall_notice":
			_build_wall_notice()
		"chandelier":
			_build_chandelier()
		"wall_lantern":
			_build_wall_lantern()
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
		"weapon_rack":
			_build_weapon_rack()
		_:
			_build_crate_like()
	var result: Array[Dictionary] = []
	for entry in _pending_boxes:
		var box: BoxMesh = entry["mesh"]
		var t: Transform3D = entry["transform"]
		var center_px := t.origin * 32.0
		var size_px := box.size * 32.0
		result.append({
			"name": entry["name"],
			"min": center_px - size_px * 0.5,
			"max": center_px + size_px * 0.5,
			"material": entry["material"],
		})
	_pending_boxes.clear()
	_collecting_bounds = false
	return result


func _light(name: String, center_px: Vector3, energy: float, radius_m: float) -> OmniLight3D:
	if _collecting_bounds:
		return null
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
	# 前后裙板缩短至桌腿内侧之间，消除与桌腿的同材质交叉重叠
	_box("TableApronFront", Vector3i(47, 3, 3), Vector3(0, 20, 15), _wood_dark_mat)
	_box("TableApronBack", Vector3i(47, 3, 3), Vector3(0, 20, -15), _wood_dark_mat)
	# 端裙板缩短至前后桌腿之间，消除同材质交叉重叠
	_box("TableEndApronLeft", Vector3i(3, 3, 21), Vector3(-29, 20, 0), _wood_dark_mat)
	_box("TableEndApronRight", Vector3i(3, 3, 21), Vector3(29, 20, 0), _wood_dark_mat)
	for x in [-26, 26]:
		for z in [-13, 13]:
			_box("Leg_%d_%d" % [x, z], Vector3i(5, 22, 5), Vector3(x, 11, z), _wood_dark_mat)


func _build_chair() -> void:
	_box("Seat", Vector3i(19, 4, 19), Vector3(0, 14, 0), _wood_mat)
	_box("BackPanel", Vector3i(15, 18, 3), Vector3(0, 25, -10), _wood_mat)
	for x in [-8, 8]:
		for z in [-7, 7]:
			_box("Leg_%d_%d" % [x, z], Vector3i(3, 12, 3), Vector3(x, 6, z), _wood_dark_mat)
	for x in [-9, 9]:
		_box("BackPost_%d" % x, Vector3i(3, 18, 3), Vector3(x, 25, -10), _wood_dark_mat)


func _build_bench() -> void:
	_box("BenchSeat", Vector3i(64, 4, 13), Vector3(0, 15, 0), _wood_mat)
	# 前后横档缩短至桌腿之间，消除角部正体积重叠
	_box("BenchFrontRail", Vector3i(49, 3, 3), Vector3(0, 11, 7), _wood_dark_mat)
	_box("BenchBackRail", Vector3i(49, 3, 3), Vector3(0, 11, -7), _wood_dark_mat)
	# 腿高 13px，顶 Y=13 与座面底 Y=13 面接触，消除穿入座面造成的跨材质共面重叠
	for x in [-27, 27]:
		for z in [-4, 4]:
			_box("Leg_%d_%d" % [x, z], Vector3i(5, 13, 5), Vector3(x, 6.5, z), _wood_dark_mat)


func _build_bucket() -> void:
	# 底板缩小至壁板内侧，消除与壁板的正体积重叠
	_box("BucketBottom", Vector3i(11, 3, 11), Vector3(0, 2, 0), _wood_dark_mat)
	# 前后壁板缩短至左右壁板之间，消除角部正体积重叠
	_box("BucketFront", Vector3i(11, 17, 3), Vector3(0, 10, 7), _wood_mat)
	_box("BucketBack", Vector3i(11, 17, 3), Vector3(0, 10, -7), _wood_mat)
	_box("BucketLeft", Vector3i(3, 17, 17), Vector3(-7, 10, 0), _wood_mat)
	_box("BucketRight", Vector3i(3, 17, 17), Vector3(7, 10, 0), _wood_mat)
	_box("IronBandLow", Vector3i(19, 2, 19), Vector3(0, 6, 0), _iron_mat)
	_box("IronBandHigh", Vector3i(19, 2, 19), Vector3(0, 15, 0), _iron_mat)


func _build_candles(lit: bool) -> void:
	_box("CandleTray", Vector3i(17, 1, 5), Vector3(0, 0.5, 0), _iron_mat)
	for i in range(3):
		var x: int = int([-5, 0, 5][i])
		var height: int = int([9, 12, 7][i])
		# 蜡烛底 Y=1 与托盘顶 Y=1 面接触，消除插在托盘内造成的跨材质共面重叠
		_box("Candle%d" % i, Vector3i(3, height, 3), Vector3(x, height * 0.5 + 1, 0), _wax_mat)


func _build_tankard() -> void:
	_box("TankardBaseBand", Vector3i(9, 1, 7), Vector3(0, 0.5, 0), _tankard_iron_mat)
	_box("TankardBody", Vector3i(9, 8, 7), Vector3(0, 5, 0), _tankard_wood_mat)
	_box("TankardRimBand", Vector3i(11, 2, 9), Vector3(0, 10, 0), _tankard_iron_mat)
	_box("TankardDrinkSurface", Vector3i(7, 1, 5), Vector3(0, 11.5, 0), _ale_mat)
	# 把手三段在 Y 轴上面接触堆叠，消除同材质正体积重叠
	_box("HandleUpperBand", Vector3i(5, 2, 3), Vector3(6, 7.5, 0), _tankard_iron_mat)
	_box("HandleSideBar", Vector3i(3, 3, 3), Vector3(8, 5, 0), _tankard_iron_mat)
	_box("HandleLowerBand", Vector3i(5, 2, 3), Vector3(6, 2.5, 0), _tankard_iron_mat)


func _build_goblet() -> void:
	_box("GobletFootBand", Vector3i(9, 1, 9), Vector3(0, 0.5, 0), _goblet_silver_mat)
	# 缩短茎杆使其与杯底面接触而非重叠
	_box("GobletStemBar", Vector3i(3, 5, 3), Vector3(0, 3.5, 0), _goblet_silver_mat)
	_box("GobletCupBase", Vector3i(7, 3, 7), Vector3(0, 7.5, 0), _goblet_silver_mat)
	# 上移杯身使其与杯底面接触
	_box("GobletCupBody", Vector3i(9, 5, 9), Vector3(0, 11.5, 0), _goblet_wine_mat)
	# 上移杯沿使其与杯身面接触
	_box("GobletRimBand", Vector3i(11, 2, 11), Vector3(0, 15, 0), _goblet_silver_mat)


func _build_bottle_set() -> void:
	_box("ShelfBarBase", Vector3i(41, 2, 11), Vector3(0, 1, 0), _wood_dark_mat)
	_build_bottle(-13, 11, _bottle_green_mat, "TallBottle")
	_build_bottle(0, 8, _bottle_amber_mat, "RoundBottle")
	_build_bottle(13, 10, _goblet_wine_mat, "SquareBottle")
	_box("ShelfBackRail", Vector3i(43, 5, 3), Vector3(0, 7, -5), _wood_dark_mat)


func _build_bottle(x_px: int, body_height_px: int, material: Material, prefix: String) -> void:
	_box("%sBody" % prefix, Vector3i(7, body_height_px, 7), Vector3(x_px, 2 + body_height_px * 0.5, 0), material)
	_box("%sNeck" % prefix, Vector3i(3, 5, 3), Vector3(x_px, body_height_px + 4.5, 0), material)
	_box("%sCork" % prefix, Vector3i(3, 2, 3), Vector3(x_px, body_height_px + 8, 0), _bottle_cork_mat)


func _build_wall_notice() -> void:
	# 背板缩小至四框内侧，消除与框条的同材质正体积重叠
	_box("NoticeBackBoard", Vector3i(33, 23, 2), Vector3(0, 14, 0), _notice_frame_mat)
	# 上下横档缩短至左右竖档之间，消除角部正体积重叠
	_box("NoticeTopRail", Vector3i(33, 3, 3), Vector3(0, 27, -0.5), _notice_frame_mat)
	_box("NoticeBottomRail", Vector3i(33, 3, 3), Vector3(0, 1, -0.5), _notice_frame_mat)
	# 左右竖档缩短至上下横档之间，消除角部正体积重叠
	_box("NoticeLeftRail", Vector3i(3, 21, 3), Vector3(-18, 14, -0.5), _notice_frame_mat)
	_box("NoticeRightRail", Vector3i(3, 21, 3), Vector3(18, 14, -0.5), _notice_frame_mat)
	_box("NoticeParchment", Vector3i(25, 17, 1), Vector3(0, 15, -1.5), _notice_parchment_mat)
	for y in [19, 15, 11]:
		_box("NoticeTextBar_%d" % y, Vector3i(17, 1, 1), Vector3(0, y, -2), _ink_mat)


func _build_chandelier() -> void:
	_box("CeilingPlate", Vector3i(13, 2, 13), Vector3(0, -1, 0), _warm_bronze_mat)
	for i in range(5):
		_box("ChainLinkBar_%d" % i, Vector3i(3, 4, 3), Vector3(0, -4 - i * 4, 0), _warm_bronze_mat)
	_box("CentralHub", Vector3i(7, 5, 7), Vector3(0, -24.5, 0), _warm_bronze_mat)
	_box("WheelArmXP", Vector3i(14, 3, 5), Vector3(10.5, -24.5, 0), _chandelier_wood_mat)
	_box("WheelArmXN", Vector3i(14, 3, 5), Vector3(-10.5, -24.5, 0), _chandelier_wood_mat)
	_box("WheelArmZP", Vector3i(5, 3, 14), Vector3(0, -24.5, 10.5), _chandelier_wood_mat)
	_box("WheelArmZN", Vector3i(5, 3, 14), Vector3(0, -24.5, -10.5), _chandelier_wood_mat)
	for pos in [Vector3(17, -21.5, 0), Vector3(-17, -21.5, 0), Vector3(0, -21.5, 17), Vector3(0, -21.5, -17)]:
		_box("CandleCup_%d_%d" % [int(pos.x), int(pos.z)], Vector3i(7, 3, 7), pos, _warm_bronze_mat)
		_box("Candle_%d_%d" % [int(pos.x), int(pos.z)], Vector3i(3, 7, 3), pos + Vector3(0, 5, 0), _warm_wax_mat)


func _build_wall_lantern() -> void:
	_box("LanternWallPlate", Vector3i(9, 17, 2), Vector3(0, 24, 0), _soot_mat)
	# 青铜构件分层 Y 堆叠，消除同材质交叉重叠：
	# Base Y=[13.5,16.5] → BottomBand Y=[16.5,18.5] → Posts Y=[18.5,26.5]
	# → TopBand Y=[26.5,28.5] → Roof Y=[28.5,31.5]
	# 横臂改为顶部短托架（Y=[26.5,28.5] 与顶带同层、Z=[-7,-1] 在墙板与灯体之间），
	# 与墙板/顶带面接触、避开玻璃，消除穿过玻璃造成的跨材质共面重叠
	_box("LanternArmBar", Vector3i(3, 2, 6), Vector3(0, 27.5, -4), _warm_bronze_mat)
	_box("LanternBase", Vector3i(11, 3, 9), Vector3(0, 15, -12), _warm_bronze_mat)
	_box("LanternBottomBand", Vector3i(13, 2, 9), Vector3(0, 17.5, -12), _warm_bronze_mat)
	_box("LanternGlass", Vector3i(7, 8, 5), Vector3(0, 22.5, -12), _lantern_glass_mat)
	_box("LanternLeftPost", Vector3i(2, 8, 7), Vector3(-5, 22.5, -12), _warm_bronze_mat)
	_box("LanternRightPost", Vector3i(2, 8, 7), Vector3(5, 22.5, -12), _warm_bronze_mat)
	_box("LanternTopBand", Vector3i(13, 2, 9), Vector3(0, 27.5, -12), _warm_bronze_mat)
	_box("LanternRoof", Vector3i(13, 3, 9), Vector3(0, 30, -12), _soot_mat)


func _build_grate() -> void:
	# X方向栏 Y=[0,1]，Z方向栏 Y=[1,2]，Y轴面接触消除交叉重叠
	for x in [-12, -6, 0, 6, 12]:
		_box("BarX_%d" % x, Vector3i(3, 1, 31), Vector3(x, 0.5, 0), _iron_mat)
	for z in [-12, -4, 4, 12]:
		_box("BarZ_%d" % z, Vector3i(31, 1, 3), Vector3(0, 1.5, z), _iron_mat)


func _build_jail() -> void:
	_box("TopRail", Vector3i(61, 5, 5), Vector3(0, 63, 0), _iron_mat)
	_box("BottomRail", Vector3i(61, 5, 5), Vector3(0, 2, 0), _iron_mat)
	# 竖栏缩短至横档之间 Y=[4.5,60.5]，与顶/底横档面接触
	for x in [-24, -12, 0, 12, 24]:
		_box("Bar_%d" % x, Vector3i(3, 56, 3), Vector3(x, 32.5, 0), _iron_mat)
	# 横档拆分为竖栏之间的段，消除同材质交叉重叠
	for y in [22, 43]:
		_box("CrossbarEndL_%d" % y, Vector3i(5, 3, 3), Vector3(-28, y, 0), _iron_mat)
		_box("CrossbarS1_%d" % y, Vector3i(9, 3, 3), Vector3(-18, y, 0), _iron_mat)
		_box("CrossbarS2_%d" % y, Vector3i(9, 3, 3), Vector3(-6, y, 0), _iron_mat)
		_box("CrossbarS3_%d" % y, Vector3i(9, 3, 3), Vector3(6, y, 0), _iron_mat)
		_box("CrossbarS4_%d" % y, Vector3i(9, 3, 3), Vector3(18, y, 0), _iron_mat)
		_box("CrossbarEndR_%d" % y, Vector3i(5, 3, 3), Vector3(28, y, 0), _iron_mat)


func _build_fireplace() -> void:
	# 石材构件全部面接触堆叠，消除同材质正体积重叠：
	# HearthBase(底板 Y=[0,3]) → BackStone/Jamb(立墙 Y=[3,38]) → Mantel(横梁 Y=[38,43])
	_box("HearthBase", Vector3i(45, 3, 21), Vector3(0, 1.5, 0), _stone_mat)
	_box("BackStone", Vector3i(31, 35, 5), Vector3(0, 20.5, -8), _stone_mat)
	_box("LeftJamb", Vector3i(7, 35, 17), Vector3(-19, 20.5, 0), _stone_mat)
	_box("RightJamb", Vector3i(7, 35, 17), Vector3(19, 20.5, 0), _stone_mat)
	_box("Mantel", Vector3i(49, 5, 19), Vector3(0, 40.5, 0), _stone_mat)
	# 柴火堆叠：FireLogA 在下 Y=[5,9]，FireLogB 在上 Y=[9,13]，面接触
	_box("FireLogA", Vector3i(23, 4, 5), Vector3(0, 7, 2), _wood_dark_mat)
	# FireLogB 缩短并前移，底 Z=-5.5 与后墙石前表面 Z=-5.5 面接触，消除穿透后墙石造成的跨材质共面重叠
	_box("FireLogB", Vector3i(5, 4, 16), Vector3(4, 11, 2.5), _wood_dark_mat)


func _build_crate(size_px: Vector3i) -> void:
	var half_y := size_px.y * 0.5
	_box("CrateCore", size_px, Vector3(0, half_y, 0), _wood_mat)
	# 十字加强条位置（25% 处）
	var cross_off: int = int(size_px.x * 0.25)
	var band_w: float = size_px.x + 2.0
	var band_z: int = size_px.z + 2
	# 上下铁带拆分为 3 段（避开十字条），消除同材质交叉重叠
	var seg_w: float = band_w * 0.5 - cross_off - 1.5
	var seg_c: float = band_w * 0.5 - seg_w * 0.5
	var mid_w: float = cross_off * 2.0 - 3.0
	for y_pos in [size_px.y - 4, 5]:
		_box("CrateBandLeft_%d" % y_pos, Vector3i(int(seg_w), 3, band_z), Vector3(-seg_c, y_pos, 0), _wood_dark_mat)
		_box("CrateBandMid_%d" % y_pos, Vector3i(int(mid_w), 3, band_z), Vector3(0, y_pos, 0), _wood_dark_mat)
		_box("CrateBandRight_%d" % y_pos, Vector3i(int(seg_w), 3, band_z), Vector3(seg_c, y_pos, 0), _wood_dark_mat)
	_box("CrateCrossA", Vector3i(3, size_px.y + 1, band_z), Vector3(-cross_off, half_y, 0), _wood_dark_mat)
	_box("CrateCrossB", Vector3i(3, size_px.y + 1, band_z), Vector3(cross_off, half_y, 0), _wood_dark_mat)


func _build_barrel() -> void:
	var slice_ranges := [
		Vector2i(-15, -10),
		Vector2i(-10, -4),
		Vector2i(-4, 4),
		Vector2i(4, 10),
		Vector2i(10, 15),
	]
	var belly_depths := [17, 25, 29, 25, 17]
	var cap_depths := [13, 21, 25, 21, 13]
	for i in range(slice_ranges.size()):
		var x_range: Vector2i = slice_ranges[i]
		var body_mat: Material = _wood_dark_mat if i == 0 else _wood_mat
		_barrel_slice("BottomCapSlice_%d" % i, x_range, Vector2i(0, 3), cap_depths[i], _wood_dark_mat)
		_barrel_slice("LowerWoodSlice_%d" % i, x_range, Vector2i(3, 7), belly_depths[i], body_mat)
		_barrel_slice("IronBandLowSlice_%d" % i, x_range, Vector2i(7, 10), belly_depths[i], _iron_mat)
		_barrel_slice("MiddleWoodSlice_%d" % i, x_range, Vector2i(10, 21), belly_depths[i], body_mat)
		_barrel_slice("IronBandHighSlice_%d" % i, x_range, Vector2i(21, 24), belly_depths[i], _iron_mat)
		_barrel_slice("UpperWoodSlice_%d" % i, x_range, Vector2i(24, 28), belly_depths[i], body_mat)
		_barrel_slice("TopCapSlice_%d" % i, x_range, Vector2i(28, 31), cap_depths[i], _wood_dark_mat)


func _barrel_slice(name: String, x_range: Vector2i, y_range: Vector2i, depth_px: int, material: Material) -> void:
	var size_px := Vector3i(x_range.y - x_range.x, y_range.y - y_range.x, depth_px)
	var center_px := Vector3(
		(float(x_range.x) + float(x_range.y)) * 0.5,
		(float(y_range.x) + float(y_range.y)) * 0.5,
		0.0
	)
	_box(name, size_px, center_px, material)


func _build_chest() -> void:
	_box("ChestBase", Vector3i(33, 17, 23), Vector3(0, 8.5, 0), _wood_mat)
	_box("ChestLid", Vector3i(35, 9, 25), Vector3(0, 21.5, 0), _wood_dark_mat)
	# 铁带移到箱体左右侧面之外（X=±18，箱体外表面 X=±16.5），面接触不穿透，消除跨材质共面重叠
	_box("IronBandLeft", Vector3i(3, 29, 27), Vector3(-18, 14.5, 0), _iron_mat)
	_box("IronBandRight", Vector3i(3, 29, 27), Vector3(18, 14.5, 0), _iron_mat)
	_box("LockPlate", Vector3i(7, 7, 3), Vector3(0, 16, 12), _iron_mat)


func _build_large_chest() -> void:
	_box("BossChestPlinth", Vector3i(65, 5, 39), Vector3(0, 2.5, 0), _wood_dark_mat)
	_box("BossChestBase", Vector3i(61, 22, 35), Vector3(0, 13, 0), _wood_mat)
	# 盖子分层 Y 面接触堆叠（全部 _wood_dark_mat）
	_box("BossChestLidLower", Vector3i(65, 6, 39), Vector3(0, 25, 0), _wood_dark_mat)   # Y=[22,28]
	_box("BossChestLidMid", Vector3i(57, 6, 35), Vector3(0, 31, 0), _wood_dark_mat)     # Y=[28,34]
	_box("BossChestLidCrown", Vector3i(45, 5, 29), Vector3(0, 36.5, 0), _wood_dark_mat) # Y=[34,39]
	_box("BossChestLidRidge", Vector3i(25, 3, 15), Vector3(0, 40.5, 0), _wood_dark_mat) # Y=[39,42]
	# 铁角柱（4 根，Y=[5,41]）：自底座顶面 Y=5 起，消除穿透底座造成的跨材质共面重叠
	for x in [-31, 31]:
		for z in [-18, 18]:
			_box("BossIronCorner_%d_%d" % [x, z], Vector3i(5, 36, 5), Vector3(x, 23, z), _iron_mat)
	# 铁镶边（缩短 X 避开角柱，Y=[21,25]）
	_box("BossIronRimFront", Vector3i(57, 4, 3), Vector3(0, 23, 20), _iron_mat)
	_box("BossIronRimBack", Vector3i(57, 4, 3), Vector3(0, 23, -20), _iron_mat)
	# 铁盖脊
	_box("BossIronLidRidge", Vector3i(31, 3, 5), Vector3(0, 41.5, 0), _iron_mat)
	# 铁绑带（在镶边 Y=[21,25] 处拆分为上下两段，消除同材质交叉重叠）
	# 下铁带自底座顶面 Y=5 起（不再穿透底座），Y=[5,21]
	_box("BossIronBandLeftLower", Vector3i(5, 16, 3), Vector3(-16, 13, 20), _iron_mat)
	_box("BossIronBandLeftUpper", Vector3i(5, 11, 3), Vector3(-16, 30.5, 20), _iron_mat)    # Y=[25,36]
	_box("BossIronBandRightLower", Vector3i(5, 16, 3), Vector3(16, 13, 20), _iron_mat)
	_box("BossIronBandRightUpper", Vector3i(5, 11, 3), Vector3(16, 30.5, 20), _iron_mat)
	# 锁板（镶边下方 Y=[10,21]）
	_box("BossLockPlate", Vector3i(15, 11, 3), Vector3(0, 15.5, 20), _iron_mat)
	# 封印
	_box("BossRewardSeal", Vector3i(7, 7, 1), Vector3(0, 18, 22.5), _cloth_mat)
	# 侧把手
	_box("BossSideHandleLeft", Vector3i(7, 5, 13), Vector3(-36, 20, 0), _iron_mat)
	_box("BossSideHandleRight", Vector3i(7, 5, 13), Vector3(36, 20, 0), _iron_mat)
	# 人字纹装饰（前移 Z=[21.5,23.5] 避开镶边/绑带/锁板的 Z=[18.5,21.5]；
	# 缩窄宽度至 6px 避免左右人字纹互相交叉）
	for i in range(3):
		var cy: float = [29.5, 26.5, 19.5][i]
		_box("BossIronChevronA_%d" % i, Vector3i(6, 3, 2), Vector3(-19 + i * 11, cy, 22.5), _iron_mat)
		_box("BossIronChevronB_%d" % i, Vector3i(6, 3, 2), Vector3(19 - i * 11, cy, 22.5), _iron_mat)


func _build_torch() -> void:
	_box("IronWallSpine", Vector3i(1, 10, 1), Vector3(0, 32, 0), _iron_mat)
	_box("WallPlateTop", Vector3i(5, 1, 1), Vector3(0, 37.5, 0), _iron_mat)
	_box("WallPlateBottom", Vector3i(5, 1, 1), Vector3(0, 26.5, 0), _iron_mat)
	_box("PlateRivetTop", Vector3i(1, 1, 1), Vector3(0, 37.5, -1), _iron_mat)
	_box("PlateRivetBottom", Vector3i(1, 1, 1), Vector3(0, 26.5, -1), _iron_mat)
	_box("IronWallSocket", Vector3i(5, 3, 3), Vector3(0, 32, -2), _iron_mat)
	_box("IronLowerArm", Vector3i(5, 1, 2), Vector3(0, 31, -4.5), _iron_mat)
	_box("IronUpperArm", Vector3i(5, 1, 2), Vector3(0, 34, -4.5), _iron_mat)
	_box("TorchHandle", Vector3i(3, 9, 3), Vector3(0, 33.5, -8), _wood_dark_mat)
	for y in [31, 34]:
		_box("IronHandleBandFront_%d" % y, Vector3i(3, 1, 1), Vector3(0, y, -10), _iron_mat)
		_box("IronHandleBandBack_%d" % y, Vector3i(3, 1, 1), Vector3(0, y, -6), _iron_mat)
		_box("IronHandleBandLeft_%d" % y, Vector3i(1, 1, 3), Vector3(-2, y, -8), _iron_mat)
		_box("IronHandleBandRight_%d" % y, Vector3i(1, 1, 3), Vector3(2, y, -8), _iron_mat)
	_box("CupBase", Vector3i(5, 1, 3), Vector3(0, 38.5, -8), _iron_mat)
	_box("CupLip", Vector3i(7, 1, 5), Vector3(0, 39.5, -8), _iron_mat)
	var light := _light("OmniLight3D", Vector3(0, 41, -8), 3.4, 11.0)
	if light == null:
		return
	light.omni_attenuation = 0.65
	light.distance_fade_enabled = true
	light.distance_fade_begin = 24.0
	light.distance_fade_length = 10.0
	# 标记为由 LightingController 管理的火光（闪烁 + 酒馆档案收束范围）。
	# 范围/亮度仍保持地牢可见性约束（range>=10 / energy>=3.2），不做全局改动。
	light.add_to_group("flicker_light")
	light.set_meta("light_role", "torch")
	# 实时阴影：地牢/酒馆点光源此前 shadow_enabled=false，光以球状影响范围无视墙体几何，
	# 导致"隔墙透光"（光线泄漏到墙另一侧）。开启阴影后，墙体会遮挡本火把的光，修复漏光。
	# 开销由灯光预算自动收敛——procedural_dungeon._update_streamed_lights 仅让最近的
	# DUNGEON_VISIBLE_LOCAL_LIGHT_BUDGET(12) 盏火把 light.visible=true，不可见的火把不渲染
	# 阴影，因此实时阴影代价只落在预算内的火把上。低分辨率 cubemap 以压低每帧阴影绘制成本。
	light.shadow_enabled = true
	# Godot 4 已移除 per-light 的 shadow_atlas_resolution（点光阴影分辨率改由渲染器全局
	# 阴影图集控制），因此此处不设置该属性。选用 cubemap 阴影模式(omni_shadow_mode=1)：
	# 每灯 6 次深度绘制，阴影干净无接缝（双抛物面=0 在地板/墙面产生明显黑色三角伪影）。
	# 开销由灯光预算自动收敛——_update_streamed_lights 仅让最近 ~12 盏火把可见并渲染阴影。
	light.omni_shadow_mode = 1
	light.shadow_bias = 0.03
	light.shadow_normal_bias = 0.3
	# 编辑器预览：若处于酒馆场景中，立即将光源收束为酒馆值，
	# 使编辑器所见即实机所得（WYSIWYG）。运行时由 apply_context_lighting 统一处理。
	_apply_context_lighting(light)
	# 视觉随光预算隐藏：当地牢光预算(DUNGEON_VISIBLE_LOCAL_LIGHT_BUDGET)关闭本火把的光时，
	# 火焰粒子与体素网格继续绘制只会白费 additive overdraw 与 draw call（无光仍画火焰）。
	# 灯灭则同步隐藏火焰+网格（碰撞体保留，仍可碰撞），灯亮则恢复。
	light.visibility_changed.connect(_on_torch_light_visibility_changed.bind(light))
	_sync_torch_visual_to_light(light)


func _on_torch_light_visibility_changed(light: Light3D) -> void:
	_sync_torch_visual_to_light(light)


func _sync_torch_visual_to_light(light: Light3D) -> void:
	if light == null or not is_instance_valid(light):
		return
	var on := light.visible
	var flame := get_node_or_null("../FlameParticles")
	if flame != null:
		flame.visible = on
	for child in get_children():
		if child is MeshInstance3D:
			child.visible = on


# ── 场景上下文光照（WYSIWYG：编辑器预览 = 运行时实机） ──────────
# 问题：baked_torch.tscn 和 _build_torch() 都用地牢默认值（energy=3.4/range=11.0），
#   而 LightingController.apply_tavern_profile 只在运行时覆盖为酒馆值，
#   导致编辑器看到的亮度远大于实机。
# 解决：在光源创建/加载时即根据所在场景上下文应用正确值——
#   编辑器内 _build_torch() 调用 _apply_context_lighting(light) 即时收束；
#   运行时 baked 路径由 _apply_context_lighting_to_children() 遍历子节点收束。
#   apply_tavern_profile 仍会运行（冗余但无害），保证闪烁组等逻辑不丢。

## 检测本道具是否处于酒馆场景中（向上遍历父节点寻找 TavernInterior）。
## 检测顺序：class_name → 脚本路径 → meta 标记（测试友好）。
func _is_in_tavern() -> bool:
	var parent: Node = get_parent()
	while parent != null:
		if parent.get_class() == "TavernInterior":
			return true
		if parent.has_meta("is_tavern") and parent.get_meta("is_tavern"):
			return true
		parent = parent.get_parent()
	return false


## 对单个火把光源应用场景上下文光照。
## 酒馆内收束为 LightingController 的酒馆档案值；地牢内保持原始地牢值。
func _apply_context_lighting(light: OmniLight3D) -> void:
	if light == null or not is_instance_valid(light):
		return
	if light.get_meta("light_role", "") != "torch":
		return
	if not _is_in_tavern():
		return
	# 安全访问 LightingController autoload（编辑器内 autoload 可用，
	# 但 _quality_tier 未初始化，默认使用 HIGH 档预览）。
	var lc: Node = Service.lighting_controller()
	if lc == null:
		return
	# 默认 HIGH 档；运行时从 LightingController 读取实际画质分级
	var tier: int = 0
	if lc.has_method("get_quality_tier"):
		tier = lc.get_quality_tier()
	var range_map: Dictionary = lc.get("TAVERN_TORCH_RANGE")
	var energy_val: float = lc.get("TAVERN_TORCH_ENERGY")
	var color_val: Color = lc.get("TAVERN_TORCH_COLOR")
	light.omni_range = range_map.get(tier, 6.0)
	light.light_energy = energy_val
	light.light_color = color_val
	light.set_meta("flicker_base_energy", light.light_energy)


## 遍历本道具所有子 OmniLight3D，对火把光源应用场景上下文光照。
## 用于 baked 资产加载后（运行时）和 _ready 末尾（防御性双保险）。
func _apply_context_lighting_to_children() -> void:
	for child in get_children():
		if child is OmniLight3D:
			_apply_context_lighting(child as OmniLight3D)


func _build_pillar() -> void:
	_box("PillarBase", Vector3i(19, 5, 19), Vector3(0, 2.5, 0), _stone_mat)
	# 缩短柱身使其与柱冠面接触（Y=[5,91]），柱冠 Y=[91,98]
	_box("PillarShaft", Vector3i(13, 86, 13), Vector3(0, 48, 0), _stone_mat)
	_box("PillarCapital", Vector3i(21, 7, 21), Vector3(0, 94.5, 0), _stone_mat)


func _build_banner() -> void:
	# 旗杆 Y=[0,28]，横杆 Y=[28,32]，面接触
	_box("BannerPole", Vector3i(3, 28, 3), Vector3(-12, 14, 0), _wood_dark_mat)
	_box("BannerTopRail", Vector3i(31, 4, 3), Vector3(0, 30, 0), _wood_dark_mat)
	# 旗布 Y=[5,28]，与旗尾 Y=[-1,5] 在 Y=5 面接触
	_box("BannerCloth", Vector3i(25, 23, 2), Vector3(3, 16.5, 0), _cloth_mat)
	_box("BannerTailLeft", Vector3i(9, 6, 2), Vector3(-4, 2, 0), _cloth_mat)
	_box("BannerTailRight", Vector3i(9, 6, 2), Vector3(10, 2, 0), _cloth_mat)


func _build_bones() -> void:
	# BoneA 水平 Y=[0.5,3.5]，BoneB 垂直 Y=[3.5,6.5]，Y 轴面接触
	_box("BoneA", Vector3i(19, 3, 3), Vector3(0, 2, 0), _bone_mat)
	_box("BoneB", Vector3i(3, 3, 17), Vector3(5, 5, 4), _bone_mat)
	# SkullBlock Z=[1.5,7.5]，与 BoneA Z=[-1.5,1.5] 在 Z=1.5 面接触
	_box("SkullBlock", Vector3i(7, 6, 6), Vector3(-8, 4, 4.5), _bone_mat)


func _build_plank() -> void:
	_box("Plank", Vector3i(41, 3, 9), Vector3(0, 2, 0), _wood_mat)
	# 端帽移到木板端面之外（X=±22，木板端面 X=±20.5），面接触不重叠，消除跨材质共面重叠
	_box("EndCapA", Vector3i(3, 4, 9), Vector3(-22, 2, 0), _wood_dark_mat)
	_box("EndCapB", Vector3i(3, 4, 9), Vector3(22, 2, 0), _wood_dark_mat)


func _build_rubble() -> void:
	# 三块石头底 Y=1 与 1px 底座顶 Y=1 面接触，消除插入底座造成的跨材质共面重叠
	_box("RubbleBase", Vector3i(23, 1, 15), Vector3(0, 0.5, 2), _stone_mat)
	_box("StoneA", Vector3i(9, 5, 7), Vector3(-7, 3.5, 4), _bone_mat)
	_box("StoneB", Vector3i(7, 4, 9), Vector3(4, 3, -3), _bone_mat)
	_box("StoneC", Vector3i(5, 3, 5), Vector3(11, 2.5, 7), _bone_mat)


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


## 烘焙当前单项 prop_kind 道具为实际的物理 TSCN 场景资产
func bake_to_asset() -> void:
	# 确保 rebuild 已经构建出了最新的网格
	rebuild()
	
	var baked_root := StaticBody3D.new()
	baked_root.name = "BakedProp_" + prop_kind
	baked_root.collision_layer = collision_layer
	baked_root.collision_mask = collision_mask
	
	# 将代码生成的网格实例与碰撞体深度克隆至烘焙根节点
	for child in get_children():
		if child.get_meta("voxel_generated", false) or child is CollisionShape3D:
			var copy = child.duplicate() as Node
			baked_root.add_child(copy)
			copy.owner = baked_root
	
	# 打包保存
	var scene := PackedScene.new()
	var err := scene.pack(baked_root)
	if err == OK:
		var dir := "res://assets/meshes/props/"
		if not DirAccess.dir_exists_absolute(dir):
			DirAccess.make_dir_recursive_absolute(dir)
		var save_path := dir + "baked_" + prop_kind + ".tscn"
		err = ResourceSaver.save(scene, save_path)
		if err == OK:
			print("Bake Success: " + save_path)
	
	baked_root.free()


func _build_weapon_rack() -> void:
	# Base Left & Right (X: [-30, -24] and [24, 30], Y: [0, 4], Z: [-10, 10])
	_box("BaseLeft", Vector3i(6, 4, 20), Vector3(-27, 2, 0), _wood_dark_mat)
	_box("BaseRight", Vector3i(6, 4, 20), Vector3(27, 2, 0), _wood_dark_mat)
	
	# Pillars Left & Right (X: [-29, -25] and [25, 29], Y: [4, 48], Z: [-2, 2])
	_box("PillarLeft", Vector3i(4, 44, 4), Vector3(-27, 26, 0), _wood_dark_mat)
	_box("PillarRight", Vector3i(4, 44, 4), Vector3(27, 26, 0), _wood_dark_mat)
	
	# Beams Lower & Upper (X: [-25, 25], Z: [-2, 2])
	# Lower Y: [10, 14]
	_box("BeamLower", Vector3i(50, 4, 4), Vector3(0, 12, 0), _wood_mat)
	# Upper Y: [38, 42]
	_box("BeamUpper", Vector3i(50, 4, 4), Vector3(0, 40, 0), _wood_mat)
	
	# Iron pins for hanging weapons (odd width details: X=1px, Y=1px, Z=3px)
	_box("PostPinLeft", Vector3i(1, 1, 3), Vector3(-15, 40, 2.5), _iron_mat)
	_box("PostPinMiddle", Vector3i(1, 1, 3), Vector3(0, 40, 2.5), _iron_mat)
	_box("PostPinRight", Vector3i(1, 1, 3), Vector3(15, 40, 2.5), _iron_mat)


func _is_test_running() -> bool:
	for arg in OS.get_cmdline_args():
		if "gdunit" in arg.to_lower():
			return true
	for arg in OS.get_cmdline_user_args():
		if "gdunit" in arg.to_lower():
			return true
	return false


func _spawn_weapons_on_rack() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var registry = tree.root.get_node_or_null("WeaponRegistry") if tree else null
	if registry == null:
		return
		
	# 如果尚未初始化，进行默认的 10 种陈列武器填充
	if not loot_data.has("weapons"):
		loot_data["weapons"] = []
		loot_data["materials"] = []
		loot_data["runes"] = []
		var default_ids := ["shortsword", "greatsword", "axe", "warhammer", "spear", "dagger", "longbow", "crossbow", "staff", "sword"]
		for id in default_ids:
			var wdata = registry.get_weapon_data(id)
			if wdata != null:
				loot_data["weapons"].append(wdata)
		
	for child in get_children():
		if child.name.begins_with("WeaponInstance_"):
			remove_child(child)
			child.queue_free()
			
	var pickable_scene := load("res://scenes/equipment/pickable_item.tscn") as PackedScene
	if pickable_scene == null:
		return
		
	var weapons_list: Array = loot_data.get("weapons", [])
	var index_vertical := 0
	var index_horizontal := 0
	var name_counters := {}
	
	for wdata in weapons_list:
		if wdata == null or wdata.glb_mesh == null:
			continue
		var id: String = wdata.id
		if id.is_empty():
			continue
			
		var inst := pickable_scene.instantiate() as RigidBody3D
		var counter = name_counters.get(id, 0)
		inst.name = "WeaponInstance_" + id + ("" if counter == 0 else "_" + str(counter))
		name_counters[id] = counter + 1
		
		inst.weapon_data = wdata
		inst.owner_weapon_id = id
		inst.freeze = true
		
		var is_vertical: bool = id in ["greatsword", "spear", "staff", "axe", "warhammer"]
		if is_vertical:
			var x := -0.6 + index_vertical * 0.3
			inst.position = Vector3(x, 0.65, 0.05)
			inst.rotation_degrees = Vector3(80, 0, 0)
			index_vertical += 1
		else:
			var x := -0.6 + index_horizontal * 0.3
			inst.position = Vector3(x, 1.15, 0.12)
			inst.rotation_degrees = Vector3(90, 0, 0)
			index_horizontal += 1
			
		add_child(inst)
		_fix_weapon_materials(inst)

## 交互触发：像宝箱一样打开存取面板
func interact(_source_player: Node = null) -> void:
	if prop_kind != "weapon_rack":
		return
	# 确保已就绪并初始化
	var tree := Engine.get_main_loop() as SceneTree
	var registry = tree.root.get_node_or_null("WeaponRegistry") if tree else null
	if registry != null and not loot_data.has("weapons"):
		_spawn_weapons_on_rack()
	GameEvents.chest_opened.emit(self)

## 存取面板关闭时的回调：重新刷新武器架 3D 渲染表现
func close_loot_panel() -> void:
	_spawn_weapons_on_rack()


func _fix_weapon_materials(node: Node) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.material_override is StandardMaterial3D:
			var copy = mi.material_override.duplicate() as StandardMaterial3D
			copy.vertex_color_use_as_albedo = true
			mi.material_override = copy
		if mi.mesh:
			for surface_index in range(mi.mesh.get_surface_count()):
				var mat = mi.get_surface_override_material(surface_index)
				if mat == null:
					mat = mi.mesh.surface_get_material(surface_index)
				if mat is StandardMaterial3D:
					var copy = mat.duplicate() as StandardMaterial3D
					copy.vertex_color_use_as_albedo = true
					mi.set_surface_override_material(surface_index, copy)
	for child in node.get_children():
		_fix_weapon_materials(child)
