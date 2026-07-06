extends SceneTree

func _initialize() -> void:
	print("SCRIPT_ENTRY_PROBE_OK")
	OS.delay_msec(4000)
	quit(0)
