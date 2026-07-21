extends SceneTree

# Crash-resilient headless probe.
# Recursively loads + instantiates every .tscn under scenes/, ticks a frame, frees.
# Before instantiating each scene it appends the path to a STATE file (flushed),
# so if the engine hard-crashes (signal 11) the outer driver can restart and
# resume past the crasher. Each restart processes only scenes not already in STATE.
# Results (OK / LOAD_FAIL / INSTANCE_FAIL / CRASH) are appended to RESULT file.

const SCAN_DIRS := ["res://scenes"]
const STATE_PATH := "user://probe_state.txt"      # attempted scenes (one per line)
const RESULT_PATH := "user://probe_result.txt"    # per-scene outcome

var _scenes: Array[String] = []
var _attempted := {}

func _init() -> void:
	_load_attempted()
	_collect(SCAN_DIRS)
	_scenes.sort()
	call_deferred("_run")

func _load_attempted() -> void:
	if FileAccess.file_exists(STATE_PATH):
		var f := FileAccess.open(STATE_PATH, FileAccess.READ)
		if f:
			while not f.eof_reached():
				var line := f.get_line().strip_edges()
				if line != "":
					_attempted[line] = true
			f.close()

func _mark_attempted(path: String) -> void:
	var f := FileAccess.open(STATE_PATH, FileAccess.READ_WRITE) if FileAccess.file_exists(STATE_PATH) else FileAccess.open(STATE_PATH, FileAccess.WRITE)
	if f:
		f.seek_end()
		f.store_line(path)
		f.flush()
		f.close()

func _record(line: String) -> void:
	var f := FileAccess.open(RESULT_PATH, FileAccess.READ_WRITE) if FileAccess.file_exists(RESULT_PATH) else FileAccess.open(RESULT_PATH, FileAccess.WRITE)
	if f:
		f.seek_end()
		f.store_line(line)
		f.flush()
		f.close()

func _collect(dirs: Array) -> void:
	for d in dirs:
		_scan_dir(d)

func _scan_dir(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if fname.begins_with("."):
			fname = dir.get_next()
			continue
		var full := path.path_join(fname)
		if dir.current_is_dir():
			_scan_dir(full)
		elif fname.ends_with(".tscn"):
			_scenes.append(full)
		fname = dir.get_next()
	dir.list_dir_end()

func _run() -> void:
	var container := Node.new()
	container.name = "ProbeContainer"
	get_root().add_child(container)

	var pending: Array[String] = []
	for s in _scenes:
		if not _attempted.has(s):
			pending.append(s)

	if pending.is_empty():
		print("PROBE_ALL_DONE")
		quit(0)
		return

	# Fast path: process all pending in one process. Each scene is marked attempted
	# BEFORE instantiating, so if the engine hard-crashes, the driver restarts and
	# this crasher is already recorded (skipped), letting the run advance.
	for scene_path in pending:
		_mark_attempted(scene_path)
		print("PROBE_START ", scene_path)

		var ps := ResourceLoader.load(scene_path, "PackedScene")
		if ps == null or not (ps is PackedScene):
			print("PROBE_LOAD_FAIL ", scene_path)
			_record("LOAD_FAIL " + scene_path)
			continue

		var inst: Node = (ps as PackedScene).instantiate()
		if inst == null:
			print("PROBE_INSTANCE_FAIL ", scene_path)
			_record("INSTANCE_FAIL " + scene_path)
			continue

		container.add_child(inst)
		await process_frame
		await process_frame
		if is_instance_valid(inst):
			inst.queue_free()
			await process_frame

		print("PROBE_OK ", scene_path)
		_record("OK " + scene_path)

	print("PROBE_ALL_DONE")
	quit(0)
