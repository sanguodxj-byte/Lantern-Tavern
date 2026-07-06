extends Node

var current_intensity: GameEvents.ImpactIntensity
var duration_map := {
	GameEvents.ImpactIntensity.LOW: 25,
	GameEvents.ImpactIntensity.MEDIUM: 40,
	GameEvents.ImpactIntensity.HIGH: 60,
}
var is_paused := false
var time_since_start_pause := Time.get_ticks_msec()

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameEvents.impact_felt.connect(on_impact_felt)

func on_impact_felt(intensity: GameEvents.ImpactIntensity) -> void:
	if intensity == GameEvents.ImpactIntensity.LOW:
		return
	get_tree().paused = true
	time_since_start_pause = Time.get_ticks_msec()
	is_paused = true
	current_intensity = intensity

func _process(_delta: float) -> void:
	var duration_since_paused := Time.get_ticks_msec() - time_since_start_pause
	if is_paused and duration_since_paused > duration_map[current_intensity]:
		is_paused = false
		get_tree().paused = false
	
	
	
	
