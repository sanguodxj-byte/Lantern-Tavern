class_name PixelSpellFx
extends Node3D

## 硬边像素法术视觉。仅视觉，不参与伤害/碰撞权威。
## 使用离散小立方体和短线轨迹；只对明确能量现象启用 emission。

const MAX_CHIPS := 48
const CHIP_SIZE := 0.08
const LIFE_CAST := 0.35
const LIFE_HIT := 0.55
const LIFE_AREA := 1.4

var _elapsed := 0.0
var _lifetime := LIFE_HIT
var _phase := "hit"
var _direction := Vector3.FORWARD
var _chips: Array[MeshInstance3D] = []


static func spawn(parent: Node, event: Dictionary, world_position: Vector3, direction: Vector3 = Vector3.FORWARD) -> Node3D:
	if parent == null:
		return null
	var fx := load("res://fx/pixel_spell_fx.gd").new() as Node3D
	fx.position = world_position
	parent.add_child(fx)
	fx.configure(event, direction)
	return fx


func configure(event: Dictionary, direction: Vector3 = Vector3.FORWARD) -> void:
	_phase = String(event.get("phase", "hit"))
	_direction = direction.normalized() if direction.length_squared() > 0.001 else Vector3.FORWARD
	_lifetime = LIFE_CAST if _phase == "cast" else (LIFE_AREA if _phase == "area" else LIFE_HIT)
	var imagery := String(event.get("imagery", "unknown"))
	var color := Color(event.get("color", Color.WHITE))
	_build_pattern(imagery, color)


func _process(delta: float) -> void:
	_elapsed += delta
	var t := clampf(_elapsed / _lifetime, 0.0, 1.0)
	for index in _chips.size():
		var chip := _chips[index]
		if chip == null:
			continue
		var lane := float(index % 5 - 2)
		var rise := float(index % 3) * 0.04
		chip.position += (_direction * (0.8 + index % 4 * 0.12) + Vector3(lane * 0.08, rise, 0)) * delta
		chip.scale = Vector3.ONE * maxf(0.05, 1.0 - t)
	if _elapsed >= _lifetime:
		queue_free()


func _build_pattern(imagery: String, color: Color) -> void:
	var count := 18
	if _phase == "area": count = 36
	elif _phase == "cast": count = 12
	count = mini(count, MAX_CHIPS)
	for index in count:
		var chip := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3.ONE * CHIP_SIZE * (1.0 + float(index % 3) * 0.35)
		chip.mesh = mesh
		var material := StandardMaterial3D.new()
		material.albedo_color = color.darkened(float(index % 4) * 0.08)
		material.roughness = 0.72
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED if _is_energy_imagery(imagery) else BaseMaterial3D.SHADING_MODE_PER_PIXEL
		if _is_energy_imagery(imagery):
			material.emission_enabled = true
			material.emission = color
			material.emission_energy_multiplier = 0.8
		chip.material_override = material
		chip.position = _pattern_position(imagery, index, count)
		add_child(chip)
		_chips.append(chip)


func _pattern_position(imagery: String, index: int, count: int) -> Vector3:
	var normalized := float(index) / maxf(float(count - 1), 1.0)
	if imagery.contains("lightning") or imagery.contains("thunder") or imagery.contains("spark"):
		return Vector3((index % 2) * 0.18 - 0.09, normalized * 1.2 - 0.6, -normalized * 0.25)
	if imagery.contains("barrier") or imagery.contains("shield") or imagery.contains("sanctuary"):
		var angle := normalized * TAU
		return Vector3(cos(angle) * 0.65, sin(angle) * 0.65, 0)
	if imagery.contains("cloud") or imagery.contains("whirlpool") or imagery.contains("portal") or imagery.contains("orb"):
		var angle := normalized * TAU * 2.0
		return Vector3(cos(angle) * (0.25 + normalized * 0.35), sin(angle) * 0.35, sin(angle * 0.5) * 0.25)
	if imagery.contains("spear") or imagery.contains("ray") or imagery.contains("jet") or imagery.contains("blade"):
		return Vector3(0, (index % 3 - 1) * 0.08, -normalized * 1.2)
	return Vector3((index % 5 - 2) * 0.12, (index % 4 - 1) * 0.11, -normalized * 0.55)


func _is_energy_imagery(imagery: String) -> bool:
	for token in ["fire", "ember", "lightning", "thunder", "spark", "light_ray", "holy", "portal", "arcane", "overcharge"]:
		if imagery.contains(token):
			return true
	return false
