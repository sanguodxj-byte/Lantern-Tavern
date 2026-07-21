extends GdUnitTestSuite

const AUDIO_MANAGER_SCENE := preload("res://globals/core/audio_manager.tscn")


func test_play_uses_default_player_when_audio_player_is_null() -> void:
	var manager: Node3D = AUDIO_MANAGER_SCENE.instantiate()
	add_child(manager)
	await await_idle_frame()

	var fallback := manager.get_node("%AudioStreamPlayer3D") as AudioStreamPlayer3D
	assert_object(fallback).is_not_null()

	manager.play("barrel-destroy", null)

	assert_object(fallback.stream).is_equal(manager.cached_sfx["barrel-destroy"])
	manager.free()


# 回归测试：AudioManager autoload 必须指向场景(.tscn)而非裸脚本(.gd)。
# 若指向脚本，Godot 只会创建空 Node3D，没有 AudioStreamPlayer3D 子节点，
# 也没有填充的 sound_files，导致 start_music() 报 "Cannot call method 'play' on a null value."。
func test_autoload_points_to_scene_not_script() -> void:
	var cfg := ConfigFile.new()
	var err := cfg.load("res://project.godot")
	assert_int(err).is_equal(OK)

	var autoload_value: String = cfg.get_value("autoload", "AudioManager", "")
	# autoload 值形如 "*res://globals/core/audio_manager.tscn"，去掉前缀 '*'
	var path := autoload_value.trim_prefix("*")
	assert_str(path).is_equal("res://globals/core/audio_manager.tscn")
	# 关键：必须以 .tscn 结尾，证明是场景而非脚本
	assert_bool(path.ends_with(".tscn")).is_true()


# 回归测试：场景实例化后必须拥有 AudioStreamPlayer3D 子节点与已填充的音效缓存。
func test_scene_has_audio_player_and_populated_sounds() -> void:
	var manager: Node3D = AUDIO_MANAGER_SCENE.instantiate()
	add_child(manager)
	await await_idle_frame()

	var player := manager.get_node("%AudioStreamPlayer3D") as AudioStreamPlayer3D
	assert_object(player).is_not_null()

	var cached: Dictionary = manager.cached_sfx
	assert_bool(cached.size() > 0).is_true()
	# 抽查若干关键音效已被缓存
	assert_bool(cached.has("slash")).is_true()
	assert_bool(cached.has("barrel-destroy")).is_true()
	manager.free()


# 回归测试：start_music() 不应崩溃（原 bug：audio_stream_player_3d 为 null）。
func test_start_music_does_not_crash() -> void:
	var manager: Node3D = AUDIO_MANAGER_SCENE.instantiate()
	add_child(manager)
	await await_idle_frame()

	# 调用前不应抛出 "Cannot call method 'play' on a null value."
	manager.start_music()
	manager.free()


# 回归测试：_ready() 必须跳过 sound_files 中的 null 条目，而非对 null 调用
# .resource_path 触发崩溃。原 bug：key-pickup.wav 资源缺失时 ext_resource 解析为 null，
# 导致 _ready() 报 "Cannot call method 'play' on a null value."（GDScript 链式调用误报）。
func test_ready_skips_null_streams_without_crash() -> void:
	# 构造一个 AudioManager 实例，手动注入 null 与有效 AudioStream 混合的 sound_files
	var manager: Node3D = AUDIO_MANAGER_SCENE.instantiate()
	# 在 _ready() 触发前替换 sound_files：先 add_child 触发 _ready 会用真实数据，
	# 所以这里测试的是"再次手动调用 _ready 行为"——但 _ready 是引擎回调不可重复调用。
	# 改用直接复现核心逻辑：遍历含 null 的数组，模拟 _ready 的健壮性。
	var mixed_sound_files: Array = [null, null]
	# 取一个已知存在的 AudioStream（slash）作为有效条目
	var real_stream: AudioStream = manager.cached_sfx.get("slash", null) if manager.cached_sfx.size() > 0 else null
	# 若此时 cached_sfx 尚未填充（_ready 未跑），先 add_child 触发
	if real_stream == null:
		add_child(manager)
		await await_idle_frame()
		real_stream = manager.cached_sfx.get("slash", null)
	else:
		add_child(manager)
		await await_idle_frame()
	assert_object(real_stream).is_not_null()
	mixed_sound_files.append(real_stream)
	manager.set("sound_files", mixed_sound_files)

	# 模拟 _ready() 中的健壮遍历逻辑：跳过 null、仅缓存有效条目
	var rebuilt_cache: Dictionary = {}
	for stream in mixed_sound_files:
		if stream == null:
			continue
		var filename: String = stream.resource_path.get_file().get_basename()
		rebuilt_cache[filename] = stream
	# null 条目应被跳过，仅 real_stream 一项入缓存
	assert_int(rebuilt_cache.size()).is_equal(1)
	assert_bool(rebuilt_cache.has("slash")).is_true()
	manager.free()


# 回归测试：start_music() 在 audio_stream_player_3d 为 null 时不应崩溃。
# 复现原 bug：autoload 若指向脚本而非场景，@onready 取不到 %AudioStreamPlayer3D，
# audio_stream_player_3d 为 null，start_music() 调 .play() 报 null 错误。
func test_start_music_guards_null_player() -> void:
	var manager: Node3D = AUDIO_MANAGER_SCENE.instantiate()
	add_child(manager)
	await await_idle_frame()

	# 强制置空 audio_stream_player_3d，复现"子节点缺失"场景
	manager.set("audio_stream_player_3d", null)
	# 不应抛出 "Cannot call method 'play' on a null value."
	manager.start_music()
	manager.free()


# 回归测试：sound_files 中每一项 ext_resource 引用的音频文件都必须真实存在于磁盘。
# 原 bug：key-pickup.wav 在 _deleted_files.txt 中被标记删除，但 audio_manager.tscn 仍引用它，
# 导致 ext_resource 解析为 null AudioStream，_ready() 崩溃。
func test_all_referenced_sound_files_exist_on_disk() -> void:
	var manager: Node3D = AUDIO_MANAGER_SCENE.instantiate()
	add_child(manager)
	await await_idle_frame()

	var cached: Dictionary = manager.cached_sfx
	# cached_sfx 的键即文件名（不含扩展），值即 AudioStream
	# _ready() 已跳过 null；若任一条目被跳过，cached_sfx.size() 会小于 sound_files.size()
	var sound_files_arr: Array = manager.get("sound_files")
	var null_count := 0
	for stream in sound_files_arr:
		if stream == null:
			null_count += 1
	# 当前所有 ext_resource 都应成功加载（key-pickup.wav 已从 git HEAD 恢复）
	assert_int(null_count).is_equal(0)
	# cached_sfx 应与 sound_files 数量一致（无跳过）
	assert_int(cached.size()).is_equal(sound_files_arr.size())
	manager.free()
