extends Node3D
## 战斗 HUD 实况捕获（视觉审查用）：
## 实例化 combat_hud.tscn，强制显示全部常规元素并按真实状态填值，
## 窗口化渲染后保存到匿名目录 reports/visual_review/cv/img_001.png。

const COMBAT_HUD_SCENE := preload("res://scenes/ui/combat_hud.tscn")
const OUTPUT_PATH := "res://reports/visual_review/cv/img_001.png"

var _hud: CanvasLayer


func _ready() -> void:
	print("HUD_CAPTURE_READY")
	get_window().size = Vector2i(1920, 1080)
	# 深色背景层（模拟地牢环境），置于 HUD 之下
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.05, 0.055, 0.065, 1.0)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)

	_hud = COMBAT_HUD_SCENE.instantiate() as CanvasLayer
	add_child(_hud)
	await get_tree().process_frame
	await get_tree().process_frame
	_prepare_hud_state()
	await get_tree().process_frame
	await get_tree().process_frame
	var image := get_viewport().get_texture().get_image()
	if image == null:
		printerr("HUD capture image is null")
		get_tree().quit(1)
		return
	var dir := DirAccess.open("res://")
	if dir != null:
		dir.make_dir_recursive("reports/visual_review/cv")
	var err := image.save_png(OUTPUT_PATH)
	if err != OK:
		printerr("Failed to save hud capture: %d" % err)
		get_tree().quit(1)
		return
	print("HUD_CAPTURE_SAVED %s %dx%d" % [OUTPUT_PATH, image.get_width(), image.get_height()])
	get_tree().quit(0)


func _prepare_hud_state() -> void:
	if _hud == null:
		return
	# 经验条：等级 3，经验 145/300
	if _hud.has_method("_update_experience_display"):
		_hud._update_experience_display(3, 145, 300)
	# 待处理升级角标：×2（新功能，位于经验条上方）
	if _hud.has_method("_update_pending_level_up_label"):
		_hud._update_pending_level_up_label(2)
	# 战斗日志：两条示例
	var log: Control = _hud.get_node_or_null("TopLeft/CombatLog")
	if log != null and log.has_method("push_entry"):
		log.push_entry("获得 45 角色经验", Color(1.0, 0.76, 0.32))
		log.push_entry("击杀了 哥布林", Color(0.9, 0.4, 0.35))
	# 敌血条：强制显示（TopCenter 默认可见，给其挂名内容）
	var enemy_bar: Control = _hud.get_node_or_null("TopCenter/EnemyHealthBar")
	if enemy_bar != null:
		enemy_bar.visible = true
		if enemy_bar.has_method("set_enemy") or "display_name" in enemy_bar:
			enemy_bar.set("display_name", "哥布林")
	# 左侧资源条保持默认（HP 100/100 等），强制显示容器
	for path in ["TopLeft", "TopCenter", "BottomLeft", "BottomCenterExperience", "PendingLevelUpLabel", "MinimapContainer"]:
		var node: Control = _hud.get_node_or_null(path)
		if node != null:
			node.visible = true
