extends Node

## 逐帧播放角色身体的每个动画，扫描是否有节点被动画轨道改回第 1 层（主相机可见层），
## 或 visible 被翻转。若命中，说明“左键看见手臂”是动画轨道暴露身体所致。

func _ready() -> void:
	var player = preload("res://scenes/characters/player/player.tscn").instantiate()
	add_child(player)
	await get_tree().process_frame
	await get_tree().process_frame
	var ap := player.get_node("character/AnimationPlayer") as AnimationPlayer
	var character := player.get_node("character")
	if ap == null or character == null:
		print("NO_AP_OR_CHARACTER")
		return
	var anims := ap.get_animation_list()
	print("ANIMATION_LIST: ", anims)
	for anim_name in anims:
		ap.play(anim_name)
		var anim := ap.get_animation(anim_name)
		var len := anim.length if anim != null else 1.0
		for i in range(0, 11):
			var t := len * float(i) / 10.0
			ap.seek(t, true)
			_scan(character, anim_name, t)
	print("DONE_ANIM_REVEAL")

func _scan(node: Node, anim_name: String, t: float) -> void:
	if node is GeometryInstance3D:
		var g := node as GeometryInstance3D
		if g.layers & 1:
			print("REVEAL anim=%s t=%.3f node=%s layers=%d" % [anim_name, t, node.get_path(), g.layers])
	if node is CanvasItem:
		var c := node as CanvasItem
		if not c.visible:
			print("HIDDEN anim=%s t=%.3f node=%s (CanvasItem visible=false)" % [anim_name, t, node.get_path()])
	for c in node.get_children():
		_scan(c, anim_name, t)
