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

func play(filename: String, audio_player: AudioStreamPlayer3D) -> void:
	if cached_sfx.has(filename):
		audio_player.stream = cached_sfx[filename]
		audio_player.pitch_scale = randf_range(0.85, 1.15)
		audio_player.play()
	else:
		push_error("sound not found: ", filename)
