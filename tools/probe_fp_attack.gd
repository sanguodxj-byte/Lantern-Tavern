extends Node3D

# 端到端复现：真实关卡方式生成玩家 -> 装近战武器 -> 进入 SLASHING -> 挥砍中逐帧截图 + 扫描身体层。
# 目的：确认左键攻击时身体（含手臂）是否会被主相机渲染（即用户报告的"看见手臂"）。

const PlayerPkg := preload("res://scenes/characters/player/player.tscn")
const WR := preload("res://data/weapon_registry.gd")

func _ready() -> void:
	# 1) 真实生成玩家
	var player: Node3D = PlayerPkg.instantiate()
	player.name = "LocalPlayer"
	add_child(player)
	player.global_position = Vector3(0, 1.0, 0)
	# 让主相机成为当前渲染相机
	var cam: Camera3D = player.get_node("%MainCamera") as Camera3D
	if cam != null:
		cam.current = true

	# 2) 装一把近战武器（取第一个非盾单手武器）
	var wr: Node = get_tree().root.get_node_or_null("WeaponRegistry")
	var wd = null
	if wr != null and wr.has_method("get_all_ids"):
		var ids: Array = wr.get_all_ids()
		for id in ids:
			var d = wr.get_weapon_data(id)
			if d != null and d.get("weapon_class") != "shield" and d.get("glb_mesh") != null:
				wd = d
				break
	print("PROBE_WEAPON_DATA=", wd.get("id") if wd != null else "NULL")

	# 3) 同步到 ViewModel（第一人称武器）
	var vm = player.get_node("%ViewModel")
	if vm != null and wd != null and vm.has_method("set_weapon"):
		vm.set_weapon(wd)

	# 4) 进入 SLASHING 状态（模拟左键攻击）
	var PlayerCls = load("res://scenes/characters/player/player.gd")
	# State.SLASHING 枚举值需要从 player 取
	var slashing_val: int = -1
	if player.has_method("switch_state"):
		# 通过反射枚举：直接调用一个会进入 slash 的公开路径
		# 这里用 get_primary_weapon_release_state 推断，再 switch_state
		var rel = player.get_primary_weapon_release_state()
		print("PROBE_RELEASE_STATE=", rel)
		if rel >= 0:
			slashing_val = rel
			player.switch_state(rel)
	print("PROBE_ENTERED_SLASHING=", slashing_val)

	# 5) 等几帧让状态机跑起来，期间逐帧截图 + 扫描
	_scan_body_layers(player, "T0_enter")
	await get_tree().create_timer(0.12).timeout
	_capture(player, "fp_attack_a")
	_scan_body_layers(player, "T1")
	await get_tree().create_timer(0.12).timeout
	_capture(player, "fp_attack_b")
	_scan_body_layers(player, "T2")
	await get_tree().create_timer(0.12).timeout
	_capture(player, "fp_attack_c")
	_scan_body_layers(player, "T3")
	print("PROBE_ATTACK_DONE")

func _scan_body_layers(player: Node3D, tag: String) -> void:
	var character_node: Node = player.get_node_or_null("character")
	if character_node == null:
		print(tag, " NO_CHARACTER")
		return
	var visible_count := 0
	var total := 0
	var queue: Array = [character_node]
	while not queue.is_empty():
		var n: Node = queue.pop_back()
		if n is GeometryInstance3D:
			total += 1
			# 主相机 cull_mask=1，故 layers&1 !=0 即主相机可见
			if (n.layers & 1) != 0:
				visible_count += 1
				print(tag, " VISIBLE_MESH_ON_LAYER1=", n.name, " layers=", n.layers)
		queue.append_array(n.get_children())
	print(tag, " body_visible_on_layer1=", visible_count, "/", total)

func _capture(player: Node3D, name: String) -> void:
	await get_tree().process_frame
	var vp: Viewport = get_viewport()
	var tex = vp.get_texture()
	if tex == null:
		print("PROBE_CAP_NO_TEXTURE ", name)
		return
	var img = tex.get_image()
	if img == null:
		print("PROBE_CAP_NO_IMAGE ", name)
		return
	var out := "res://reports/%s.png" % name
	img.save_png(out)
	print("PROBE_CAP_SAVED ", out)
