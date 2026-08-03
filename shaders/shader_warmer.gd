class_name ShaderWarmer
extends Node3D

signal finished

# How many drawn frames to wait so the GPU actually compiles each pipeline.
# Particles need a couple of frames to emit and draw their first particles.
# Bump this up if you still see a tiny hitch the very first time.
const WARMUP_FRAMES := 5

# Effects that get instanced from script during gameplay (the main offenders).
const FX_SCENES: Array[PackedScene] = [
	preload("res://fx/blood_spurt.tscn"),
	preload("res://fx/metal_spark.tscn"),
	preload("res://fx/damage_number.tscn"),
	preload("res://fx/voxel_chip.tscn"),
]

# Override / surface materials applied at runtime via material_override.
const WARMUP_MATERIALS: Array[Material] = [
	preload("res://materials/zclip_material.tres"),
	preload("res://materials/glow_material.tres"),
	preload("res://materials/highlight_material.tres"),
]

var _camera: Camera3D
var _spawned: Array[Node] = []

func _ready() -> void:
	# Give the warm-up objects something to render into.
	_camera = Camera3D.new()
	add_child(_camera)
	_camera.current = true

	_spawn_warmup_objects()
	_warm_for_frames()

func _spawn_warmup_objects() -> void:
	var slot := 0

	# 1. Particle effects. Their scenes auto-emit in _ready(), so simply adding
	#    them to the tree in front of the camera draws (and compiles) them.
	for scene in FX_SCENES:
		var inst := scene.instantiate()
		add_child(inst)
		if inst is Node3D:
			(inst as Node3D).position = _slot_position(slot)
		_spawned.append(inst)
		slot += 1

	# 2. Override materials, each on a small box so it gets drawn once.
	for mat in WARMUP_MATERIALS:
		_spawn_material(mat, slot)
		slot += 1

	# Static assets and gameplay effects use lit materials; no emissive pipeline
	# warm-up is needed. Actual flame fixtures compile through their own scenes.

func _spawn_material(material: Material, slot: int) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = BoxMesh.new()
	mi.material_override = material
	add_child(mi)
	mi.position = _slot_position(slot)
	_spawned.append(mi)

func _slot_position(slot: int) -> Vector3:
	# Spread objects out in a line ~2m in front of the camera, all in frustum.
	return Vector3(-2.0 + slot * 0.6, 0.0, -2.0)

func _warm_for_frames() -> void:
	# frame_post_draw fires after the renderer finishes a frame, so awaiting it
	# guarantees the warm-up objects were actually drawn (and compiled).
	for _i in WARMUP_FRAMES:
		await RenderingServer.frame_post_draw
	_cleanup()
	finished.emit()

func _cleanup() -> void:
	for node in _spawned:
		if is_instance_valid(node):
			node.queue_free()
	_spawned.clear()
	if is_instance_valid(_camera):
		_camera.queue_free()
