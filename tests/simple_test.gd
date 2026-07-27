extends SceneTree

func _initialize() -> void:
	var f = FileAccess.open("D:/123/Lantern Tavern/validation_results.txt", FileAccess.WRITE)
	if f == null:
		quit(1)
		return
	f.store_line("SCRIPT_RAN_SUCCESSFULLY")
	f.close()
	quit(0)
