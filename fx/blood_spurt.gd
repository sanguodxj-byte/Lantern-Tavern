class_name BloodSpurt
extends Node3D

@onready var blood: GPUParticles3D = %Blood
@onready var sparks: GPUParticles3D = %Sparks

func _ready() -> void:
	sparks.emitting = true
	blood.emitting = true
	blood.finished.connect(on_particles_done)

func on_particles_done() -> void:
	queue_free()
