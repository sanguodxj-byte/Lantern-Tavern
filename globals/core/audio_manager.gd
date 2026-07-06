extends Node3D

@export var sound_files : Array[AudioStream] = []

@onready var audio_stream_player_3d: AudioStreamPlayer3D = %AudioStreamPlayer3D

var cached_sfx : Dictionary[String, AudioStream] = {}

func _ready() -> void:
	for stream in sound_files:
		var filename := stream.resource_path.get_file().get_basename()
		cached_sfx[filename] = stream

func start_music() -> void:
	audio_stream_player_3d.play()

func play(filename: String, audio_player: AudioStreamPlayer3D = null) -> void:
	if not cached_sfx.has(filename):
		push_error("sound not found: ", filename)
		return

	var target := audio_player
	if target == null:
		target = audio_stream_player_3d
	if target == null:
		push_warning("[AudioManager] No AudioStreamPlayer3D available for sound: %s" % filename)
		return

	target.stream = cached_sfx[filename]
	target.pitch_scale = randf_range(0.85, 1.15)
	target.play()
