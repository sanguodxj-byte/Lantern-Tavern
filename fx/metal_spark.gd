class_name MetalSpark
extends GPUParticles3D

func _ready() -> void:
	emitting = true
	finished.connect(on_particles_done)

func on_particles_done() -> void:
	queue_free()
