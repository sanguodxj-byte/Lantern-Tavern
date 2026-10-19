extends GdUnitTestSuite

## 音效系统已停用（现有音效均为其他项目残留，已全部移除）。
## 本套件验证：
## - AudioManager 保持 autoload 场景结构（不破坏遗留调用点）
## - play/start_music 为空操作（不播放、不报错）
## - 音效缓存为空（sound_files 已清空）

const AUDIO_MANAGER_SCENE := preload("res://globals/core/audio_manager.tscn")


func test_play_is_noop_and_does_not_play() -> void:
	var manager: Node3D = AUDIO_MANAGER_SCENE.instantiate()
	add_child(manager)
	await await_idle_frame()

	var fallback := manager.get_node("%AudioStreamPlayer3D") as AudioStreamPlayer3D
	assert_object(fallback).is_not_null()

	# 音效已移除：play 为空操作，不设置流、不播放、不报错
	var stream_before: AudioStream = fallback.stream
	manager.play("barrel-destroy", null)
	assert_object(fallback.stream).is_equal(stream_before)
	manager.free()


# 回归测试：AudioManager autoload 必须指向场景(.tscn)而非裸脚本(.gd)。
func test_autoload_points_to_scene_not_script() -> void:
	var cfg := ConfigFile.new()
	var err := cfg.load("res://project.godot")
	assert_int(err).is_equal(OK)

	var autoload_value: String = cfg.get_value("autoload", "AudioManager", "")
	var path := autoload_value.trim_prefix("*")
	assert_str(path).is_equal("res://globals/core/audio_manager.tscn")
	assert_bool(path.ends_with(".tscn")).is_true()


# 音效已移除：sound_files 已清空，缓存为空。
func test_sound_cache_is_empty_after_removal() -> void:
	var manager: Node3D = AUDIO_MANAGER_SCENE.instantiate()
	add_child(manager)
	await await_idle_frame()

	var cached: Dictionary = manager.cached_sfx
	assert_bool(cached.is_empty()).is_true()
	manager.free()


# 回归测试：start_music() 不应崩溃（空操作）。
func test_start_music_does_not_crash() -> void:
	var manager: Node3D = AUDIO_MANAGER_SCENE.instantiate()
	add_child(manager)
	await await_idle_frame()

	manager.start_music()
	manager.free()


# 回归测试：start_music() 在 audio_stream_player_3d 为 null 时不应崩溃。
func test_start_music_guards_null_player() -> void:
	var manager: Node3D = AUDIO_MANAGER_SCENE.instantiate()
	add_child(manager)
	await await_idle_frame()

	manager.set("audio_stream_player_3d", null)
	manager.start_music()
	manager.free()


# 音效已移除：_ready 不再缓存任何音频流，含 null 的 sound_files 也不会崩溃。
func test_ready_noop_with_mixed_sound_files() -> void:
	var manager: Node3D = AUDIO_MANAGER_SCENE.instantiate()
	add_child(manager)
	await await_idle_frame()

	# 注入含 null 的 sound_files 后手动重载不触发崩溃（_ready 已清空缓存）
	manager.set("sound_files", [null, null])
	var rebuilt_cache: Dictionary = manager.cached_sfx
	assert_bool(rebuilt_cache.is_empty()).is_true()
	manager.free()
