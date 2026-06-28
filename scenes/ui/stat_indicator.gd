class_name StatIndicator
extends ColorRect

@onready var progress_bar: TextureRect = %ProgressBar

func refresh(current_value: int, max_value: int) -> void:
	if current_value <= 0:
		progress_bar.size.x = 0
	
	var prct := (float(current_value) / float(max_value)) * 100.0
	progress_bar.size.x = prct
	if prct > 75:
		progress_bar.modulate = Color.LIME_GREEN
	elif prct > 50:
		progress_bar.modulate = Color.GREEN_YELLOW
	elif prct > 25:
		progress_bar.modulate = Color.DARK_ORANGE
	else:
		progress_bar.modulate = Color.DARK_RED
