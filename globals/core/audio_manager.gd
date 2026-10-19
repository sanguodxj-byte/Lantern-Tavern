extends Node3D

## 音效管理（已停用）。
## 项目当前不包含音效系统：现有音效均为其他项目残留，已全部移除。
## 本类保留 API 占位（play/start_music 空操作），避免遗留调用点报错；
## 未来接入正式音效系统时恢复实现。

@export var sound_files : Array[AudioStream] = []

@onready var audio_stream_player_3d: AudioStreamPlayer3D = %AudioStreamPlayer3D

var cached_sfx : Dictionary[String, AudioStream] = {}

func _ready() -> void:
	# 音效已移除：不再缓存任何音频流。
	cached_sfx.clear()

func start_music() -> void:
	# 音效已移除（其他项目残留）：空操作。
	pass

func play(_filename: String, _audio_player: AudioStreamPlayer3D = null) -> void:
	# 音效已移除（其他项目残留）：空操作，不查找、不播放、不报错。
	pass
