extends Node

## 窗口化（非 headless）第一人称截图：装备近战武器、播放挥砍，
## 把 idle 与 slash 两帧存 PNG，用于确认左键攻击时画面里“手臂”到底是什么。

func _ready() -> void:
	var player = preload("res://scenes/characters/player/player.tscn").instantiate()
	add_child(player)
	await get_tree().process_frame
	await get_tree().process_frame

	var wr := get_tree().root.get_node_or_null("WeaponRegistry") as Node
	var weapon_data = null
	if wr != null and wr.has_method("get_weapon_data"):
		# 优先短剑，否则取第一个近战武器
		weapon_data = wr.get_weapon_data("shortsword")
		if weapon_data == null and wr.has_method("get_all_ids"):
			for id in wr.get_all_ids():
				var w = wr.get_weapon_data(id)
				if w != null and w.get("weapon_class") in ["one_hand", "two_hand"]:
					weapon_data = w
					break
	print("WEAPON_DATA=", weapon_data)

	var vm = player.get_node_or_null("MainCamera/ViewModel") if player.has_node("MainCamera/ViewModel") else null
	if vm != null and weapon_data != null and vm.has_method("set_weapon"):
		vm.set_weapon(weapon_data)
	# 让武器相机同步到主相机（切到第 11 层）
	await get_tree().process_frame
	await get_tree().process_frame

	# idle 帧
	_capture("D:/123/Lantern Tavern/reports/fp_idle.png")

	# slash 帧：身体播 slash + ViewModel 采样挥砍
	var ap := player.get_node_or_null("character/AnimationPlayer") as AnimationPlayer
	if ap != null and ap.has_animation("slash"):
		ap.play("slash")
		ap.seek(0.35, true)
	if vm != null and vm.has_method("sample_action"):
		vm.sample_action(vm.resolve_melee_action(), 0.5)
	await get_tree().process_frame
	await get_tree().process_frame
	_capture("D:/123/Lantern Tavern/reports/fp_slash.png")

	print("CAPTURE_DONE")
	get_tree().quit()

func _capture(path: String) -> void:
	var vp := get_viewport()
	var tex := vp.get_texture()
	if tex == null:
		print("NO_TEXTURE for ", path)
		return
	var img := tex.get_image()
	if img == null:
		print("NO_IMAGE for ", path)
		return
	var err := img.save_png(path)
	print("SAVED ", path, " err=", err, " size=", img.get_size())
