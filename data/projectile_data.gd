class_name ProjectileData
extends Resource
## 投射物定义（Resource）。
## 由 ProjectileService 注册表持有，武器/技能通过 id 引用。
## 每个投射物类型定义：飞行速度、存活时间、重力、穿透、AoE、视觉/音效等。

## 投射物 id（如 "arrow"、"bolt"、"elemental_bolt"）
@export var id: String = ""

## 显示名称（调试/UI 用）
@export var display_name: String = ""

## 飞行速度（米/秒）
@export var speed: float = 18.0

## 最大存活时间（秒），超时自动销毁
@export var lifetime: float = 3.0

## 重力倍率（0=直线飞行，1=受全重力下坠，0.3=轻微下坠）
@export var gravity_scale: float = 0.0

## 碰撞盒半径（米）
@export var collision_radius: float = 0.15

## 碰撞盒长度（米，沿飞行方向）
@export var collision_length: float = 0.5

## 可穿透的目标数（0=命中即销毁，>0=穿透 N 个目标后销毁）
@export var pierce_count: int = 0

## 每穿透一个目标伤害衰减百分比（0=不衰减，15=每次 -15%）
@export var pierce_falloff_percent: float = 0.0

## 是否命中环境（墙/地板）即销毁
@export var destroy_on_environment: bool = true

## 伤害类型：ranged / spell（决定 CombatEngine 的 attack_type 与属性加成）
@export var damage_type: String = "ranged"

## 命中爆炸 AoE 半径（0=单体伤害，>0=命中时对该半径内所有敌人造成伤害）
@export var impact_aoe_radius: float = 0.0

## 视觉模型场景（PackedScene），为空时按 damage_type 生成默认外观
@export var visual_scene: PackedScene

## 命中特效场景（PackedScene），可选
@export var impact_scene: PackedScene

## 拖尾特效场景（PackedScene），可选
@export var trail_scene: PackedScene

## 飞行音效键名（AudioManager 播放），为空则不播放
@export var flight_sound_key: String = ""

## 命中音效键名（AudioManager 播放），为空则不播放
@export var impact_sound_key: String = ""

## 自旋速度（度/秒），法球类可自旋，箭矢类通常为 0
@export var spin_speed: float = 0.0

## 默认外观颜色（visual_scene 为空时使用）
@export var default_color: Color = Color(0.8, 0.6, 0.3)

## 默认外观发光强度（visual_scene 为空时使用，0=不发光）
@export var default_emission: float = 0.0


## 快速构造工具方法
static func create(p_id: String, p_speed: float, p_damage_type: String = "ranged") -> ProjectileData:
	var data := ProjectileData.new()
	data.id = p_id
	data.display_name = p_id
	data.speed = p_speed
	data.damage_type = p_damage_type
	return data
