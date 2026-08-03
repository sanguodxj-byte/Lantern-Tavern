extends SceneTree
## 符文之语信息面板截图工具。
## 验证：悬浮符文槽位时，槽位下方面板显示的符文之语参与信息。
## 用法（不要用 --headless，需要渲染）：
##   & "D:/123/Godot_v4.7-stable_mono_win64.exe" --path "D:/123/Lantern Tavern" --script res://tools/rune_tooltip_screenshot.gd
## 输出：reports/rune_tooltip_preview/<rune_id>_info_panel.png

const RD := preload("res://globals/combat/rune_data.gd")
const RWD := preload("res://globals/combat/rune_word_data.gd")

## 模拟 SkillRuntime，提供 get_active_rune_words 方法
class MockSkillRuntime:
	extends RefCounted
	var _active: Array = []
	func set_active(active: Array) -> void:
		_active = active
	func get_active_rune_words() -> Array:
		return _active

func _init() -> void:
	_run()

func _run() -> void:
	await process_frame
	await process_frame

	# 模拟激活状态：thunder_run + aegis
	var mock_sr := MockSkillRuntime.new()
	mock_sr.set_active(["thunder_run", "aegis"])

	# 创建输出目录
	var dir := DirAccess.open("res://")
	if dir == null:
		push_error("无法打开项目目录")
		quit(1)
		return
	if not dir.dir_exists("reports/rune_tooltip_preview"):
		dir.make_dir_recursive("reports/rune_tooltip_preview")

	# 截取代表性符文的信息面板（覆盖各系代表）
	var runes_to_capture := [
		# 原始 7 个
		"surge", "force", "quick", "guardian", "ember", "echo", "launch",
		# 新增元素系代表
		"jala", "pavana", "bhumi", "tejas", "krishna", "dhuma",
		# 新增战斗系代表
		"para", "bhedana", "nighata", "vikshepa",
		# 新增神秘系代表
		"prana", "shakti", "vidya", "karma", "mantra",
		# 新增黑暗系代表
		"tamas", "raudra", "bhaya", "ghora",
		# 新增神圣系代表
		"siddhi", "moksha", "amrita",
		# 原始新符文
		"hima", "vajra", "visha", "ayu", "mrityu", "kala", "maya", "dipa",
	]
	for rune_id in runes_to_capture:
		await process_frame
		await _capture_info_panel(String(rune_id), mock_sr)

	print("=== 符文之语信息面板截图已保存到 reports/rune_tooltip_preview/ ===")
	quit(0)

func _capture_info_panel(rune_id: String, mock_sr: RefCounted) -> void:
	var bbcode := _build_info_bbcode(rune_id, mock_sr)
	if bbcode.is_empty():
		print("跳过 %s（不参与任何符文之语）" % rune_id)
		# 仍然截图显示"不参与任何符文之语"
		bbcode = "[color=#888888][i]%s 不参与任何符文之语[/i][/color]" % _rune_name(rune_id)

	# 创建 SubViewport 渲染面板
	var vp := SubViewport.new()
	vp.size = Vector2i(560, 520)
	vp.render_target_clear_mode = SubViewport.CLEAR_MODE_ONCE
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.transparent_bg = false

	# 面板背景（与实际 PanelContainer 样式一致）
	var panel_bg := PanelContainer.new()
	panel_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.05, 0.04, 0.96)
	style.set_border_width_all(2)
	style.border_color = Color(0.72, 0.43, 0.20, 0.96)
	style.set_content_margin_all(8)
	panel_bg.add_theme_stylebox_override("panel", style)
	vp.add_child(panel_bg)

	# RichTextLabel 显示信息
	var label := RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(520, 0)
	label.size = Vector2(520, 480)
	label.text = bbcode
	panel_bg.add_child(label)

	root.add_child(vp)

	# 等待渲染
	await process_frame
	await process_frame
	await process_frame

	# 截图保存
	var img := vp.get_texture().get_image()
	var path := "res://reports/rune_tooltip_preview/%s_info_panel.png" % rune_id
	var err := img.save_png(path)
	if err == OK:
		print("已保存: %s (%dx%d)" % [path, img.get_width(), img.get_height()])
	else:
		push_error("保存失败: %s (错误 %d)" % [path, err])

	vp.queue_free()
	await process_frame

## 模拟 TavernEquipmentPanel._build_rune_word_info_bbcode 的逻辑
func _build_info_bbcode(rune_id: String, mock_sr: RefCounted) -> String:
	var rune: Dictionary = RD.get_rune(rune_id)
	if rune.is_empty():
		return ""
	var word_ids: Array = RWD.get_rune_words_containing_rune(rune_id)
	if word_ids.is_empty():
		return ""

	var runic := String(rune.get("runic_name", ""))
	var rune_color := RD.get_rune_color(rune_id)
	var active_words: Array = mock_sr.get_active_rune_words()

	var lines: Array = []
	lines.append("[b][color=%s]%s[/color][/b] 参与的符文之语:" % [rune_color, runic])
	for word_id in word_ids:
		var word: Dictionary = RWD.get_rune_word(String(word_id))
		if word.is_empty():
			continue
		var w_runic := String(word.get("runic_name", ""))
		var w_desc := String(word.get("desc", ""))
		var recipe: Array = word.get("recipe", [])
		var is_active: bool = active_words.has(String(word_id))

		# 符文之语拥有独立的梵语主题名（非拼接）。
		# 配方行中每个符文用其专属色着色，当前悬浮符文加粗，建立视觉关联。
		var recipe_parts: Array = []
		for r in recipe:
			var rid := String(r)
			var r_runic := String(RD.get_rune(rid).get("runic_name", rid))
			var r_color := RD.get_rune_color(rid)
			if rid == rune_id:
				recipe_parts.append("[color=%s][b]%s[/b][/color]" % [r_color, r_runic])
			else:
				recipe_parts.append("[color=%s]%s[/color]" % [r_color, r_runic])
		var recipe_str := " → ".join(recipe_parts)

		var status_color := "#6CFF6C" if is_active else "#888888"
		var status_text := "✓ 已激活" if is_active else "未激活"
		lines.append("")
		lines.append("[b][color=#FFD700]%s[/color][/b]  [color=%s]%s[/color]" % [w_runic, status_color, status_text])
		lines.append("  %s" % recipe_str)
		lines.append("  [i][color=#AAAAAA]%s[/color][/i]" % w_desc)

	return "\n".join(lines)

func _rune_name(rune_id: String) -> String:
	var rune: Dictionary = RD.get_rune(rune_id)
	return String(rune.get("runic_name", rune_id))
