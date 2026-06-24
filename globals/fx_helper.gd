extends Node

const BLOOD_SPURT_PREFAB := preload("res://fx/blood_spurt.tscn")
const METAL_SPARK_PREFAB := preload("res://fx/metal_spark.tscn")

func create_metal_spark(spark_position: Vector3) -> void:
	var spark := METAL_SPARK_PREFAB.instantiate()
	GameState.current_level.add_child(spark)
	spark.global_position = spark_position

func create_blood_fx(blood_transform: Transform3D, show_sparks : bool = true) -> void:
	var blood := BLOOD_SPURT_PREFAB.instantiate()
	blood.is_sparks_shown = show_sparks
	GameState.current_level.add_child(blood)
	blood.global_transform = blood_transform
