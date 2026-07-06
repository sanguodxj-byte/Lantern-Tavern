## 物品放置数据 — Resource 类
##
## 描述一类标签物品的放置规则：
##   - base_probability: 基础每格生成概率 (0.0-1.0)
##   - zone_probabilities: 按区域修正系数 {zone_id: multiplier}
##   - location_preference: 位置偏好（LocationPreference 枚举）
##   - physics_mode: 物理模式（PhysicsMode 枚举）
##   - spawn_min_dist_from_player: 距玩家出生点最小距离
##   - max_per_room: 每间房最大生成数
##   - item_scene_paths: 可选场景路径列表 [{path: String, weight: int}]

extends Resource
class_name ItemPlacementData

const TAGS := preload("res://data/item_tags.gd")

# ── 导出属性 ────────────────────────────────────────────────
@export var tag: String = ""                              # 对应 ItemTags 常量
@export var base_probability: float = 0.05                # 基础每格概率
@export var zone_probabilities: Dictionary = {}           # {zone_id: probability_multiplier}
@export var location_preference: int = 0                  # ItemTags.LocationPreference
@export var physics_mode: int = 0                         # ItemTags.PhysicsMode
@export var spawn_min_dist_from_player: float = 3.0       # 米
@export var max_per_room: int = 5                         # 每房上限
@export var item_scene_paths: Array = []                  # [{path: String, weight: int}]

# ── 运行时缓存 ──────────────────────────────────────────────
var _cached_scenes: Array[PackedScene] = []

## 从 JSON 字典构建
static func from_dict(data: Dictionary) -> Resource:
	var res := ItemPlacementData.new()
	res.tag                        = data.get("tag", "")
	res.base_probability           = float(data.get("base_probability", 0.05))
	res.zone_probabilities         = data.get("zone_probabilities", {})
	res.location_preference        = int(data.get("location_preference", 0))
	res.physics_mode               = int(data.get("physics_mode", 0))
	res.spawn_min_dist_from_player = float(data.get("spawn_min_dist_from_player", 3.0))
	res.max_per_room               = int(data.get("max_per_room", 5))
	res.item_scene_paths           = data.get("item_scene_paths", [])
	return res

## 获取指定区域修正后的概率
func get_effective_probability(zone: int) -> float:
	var mult: float = float(zone_probabilities.get(zone, zone_probabilities.get(str(zone), 1.0)))
	return base_probability * mult

## 获取位置偏好显示名
func location_name() -> String:
	return TAGS.LOCATION_NAMES.get(location_preference, "未知")

## 获取物理模式显示名
func physics_mode_name() -> String:
	return TAGS.PHYSICS_MODE_NAMES.get(physics_mode, "未知")

## 预加载所有场景（返回是否全部加载成功）
func preload_scenes() -> bool:
	_cached_scenes.clear()
	var ok := true
	for entry in item_scene_paths:
		var path: String = entry.get("path", "")
		if path.is_empty():
			continue
		if not ResourceLoader.exists(path):
			push_warning("[ItemPlacementData] Scene path does not exist: %s (tag=%s)" % [path, tag])
			ok = false
			continue
		var scene: PackedScene = load(path)
		if scene == null:
			push_warning("[ItemPlacementData] Failed to load scene: %s (tag=%s)" % [path, tag])
			ok = false
			continue
		_cached_scenes.append(scene)
	return ok

## 按权重随机挑选一个场景，返回 null 表示无可选场景
func pick_scene() -> PackedScene:
	if _cached_scenes.is_empty():
		# 尝试惰性加载
		preload_scenes()
	if _cached_scenes.is_empty():
		return null
	if item_scene_paths.size() == 1:
		return _cached_scenes[0]
	# 权重随机
	var total_weight := 0
	for entry in item_scene_paths:
		total_weight += int(entry.get("weight", 1))
	var roll: int = randi() % max(1, total_weight)
	var cumul := 0
	for i in range(item_scene_paths.size()):
		cumul += int(item_scene_paths[i].get("weight", 1))
		if roll < cumul:
			return _cached_scenes[i]
	return _cached_scenes[0]
