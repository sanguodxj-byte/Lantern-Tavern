extends Node
## UI Runtime Capture Driver
## ============================================================================
## 真实游戏驱动：
##   1. 实例化真实 World.tscn（主场景）
##   2. 强制把 TavernManager 切到 NIGHT_TAVERN 之后以走 dungeon 阶段
##   3. 注入测试数据驱动真实 UI（CombatHUD、UI 悬浮窗、ChestLootPanel）
##   4. 用主 Viewport 的实际渲染输出作为截图
##
## 关键约束：截图 = 真实游戏运行画面，UI 代码和截图必须一一对应。
## ============================================================================

const SIZE := Vector2i(1920, 1080)
const OUT_DIR := "res://reports/ui_runtime"
const OUT_ABS := "D:/123/Lantern Tavern/reports/ui_runtime"
const LOG_ABS := "D:/123/Lantern Tavern/reports/ui_runtime/driver_stderr.log"

const GOBLIN_SCENE := preload("res://scenes/characters/enemies/goblin.tscn")
const CHEST_SCENE := preload("res://scenes/props/chest/chest.tscn")
const CHEST_LOOT_PANEL_SCENE := preload("res://scenes/ui/chest_loot_panel.tscn")
const DETAIL_POPUP_SCRIPT := preload("res://scenes/ui/equipment_detail_popup.gd")

const Service := preload("res://globals/core/service.gd")

var _world: Node3D = null
var _ui: CanvasLayer = null
var _combat_hud: CanvasLayer = null
var _player: Node3D = null
var _dungeon: Node3D = null
var _fake_enemy: Node3D = null
var _fake_chest: Node3D = null
var _saved_main_scene: String = ""
var _log_file: FileAccess = null

func _log(msg: String) -> void:
	# 同时写 printerr 和文件，避免只走 stdout 看不到诊断。
	if _log_file == null:
		_log_file = FileAccess.open(LOG_ABS, FileAccess.WRITE)
	printerr(msg)
	if _log_file != null:
		_log_file.store_line(msg)
		_log_file.flush()

func _ready() -> void:
	_log("[UIDriver] _ready enter")
	_saved_main_scene = ProjectSettings.get_setting("application/run/main_scene", "")
	# 主 Viewport 大小（用于让 view_model 之类的基于屏幕的逻辑有正确 viewport）
	get_window().size = SIZE
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	DirAccess.make_dir_recursive_absolute(OUT_ABS)
	# 1) 等 World 自身把 space 切到 dungeon（player 出生 + UI 挂上 + CombatHUD ready）
	await _wait_world_ready()
	# 2) 等待若干 _process 让 CombatHUD._ensure_player / _update_bars 完成首轮同步
	for i in range(20):
		await get_tree().process_frame
	_log("[UIDriver] world ready, starting capture")
	# 3) 入口编排
	await _run_all()

func _wait_world_ready() -> void:
	# World 包装节点
	_world = _find_child_recursive(self, "World") as Node3D
	if _world == null:
		_log("[UIDriver] FATAL: World node not found in scene tree")
		get_tree().quit(1)
		return

	# 把 TavernManager 切到 NIGHT_TAVERN 之后的"探险阶段"，
	# 让 _load_initial_space 走 transition_to_dungeon()。
	# 注意：current_phase 决定 _load_initial_space 的分支（world.gd:66）
	var tm: Node = Service.tavern_manager()
	if tm != null:
		tm.current_phase = tm.Phase.NIGHT_TAVERN
		_log("[UIDriver] forced TavernManager.current_phase = NIGHT_TAVERN")
	else:
		_log("[UIDriver] WARN: TavernManager not found, World will use its default branch")

	# 强制让 World 走 dungeon。注意：_load_initial_space 的 else 分支永远到不了
	# （Phase 只有 DAY_EXPEDITION/NIGHT_TAVERN 两值），所以默认进的是 tavern。
	# 显式调用 transition_to_dungeon() 触发 dungeon phase 流程。
	if _world.has_method("transition_to_dungeon"):
		_log("[UIDriver] forcing World.transition_to_dungeon()")
		_world.call("transition_to_dungeon")
	var deadline := Time.get_ticks_msec() + 30000
	while Time.get_ticks_msec() < deadline:
		_dungeon = _world.get("current_loaded_level") as Node3D
		if _dungeon != null and is_instance_valid(_dungeon) and _dungeon.name != "TavernInterior":
			break
		await get_tree().process_frame
	if _dungeon == null or not is_instance_valid(_dungeon) or _dungeon.name == "TavernInterior":
		_log("[UIDriver] FATAL: Dungeon not loaded (current=%s)" % str(_dungeon))
		get_tree().quit(2)
		return

	# UI / CombatHUD 是 World 的直接子节点（world.gd:19-20 @onready）
	_ui = _world.get_node_or_null("UI") as CanvasLayer
	_combat_hud = _world.get_node_or_null("CombatHUD") as CanvasLayer
	if _ui == null:
		_log("[UIDriver] WARN: UI node not found under World")
	if _combat_hud == null:
		_log("[UIDriver] WARN: CombatHUD node not found under World")

	# Player（GameState.current_player 在 dungeon runtime 启动后被设置）
	deadline = Time.get_ticks_msec() + 15000
	while Time.get_ticks_msec() < deadline:
		var gs: Node = Service.game_state()
		if gs != null:
			_player = gs.get("current_player") as Node3D
			if _player != null and is_instance_valid(_player):
				break
		await get_tree().process_frame
	if _player == null or not is_instance_valid(_player):
		_log("[UIDriver] FATAL: Player not spawned after 15s")
		get_tree().quit(3)
		return

	_log("[UIDriver] ready: world=%s dungeon=%s player=%s" % [
		_world.name, _dungeon.name, _player.name
	])
	# 诊断：打印场景树里所有 CanvasLayer / Control 节点路径
	_diag_print_canvas_tree()

func _diag_print_canvas_tree() -> void:
	_log("[UIDriver] === SCENE TREE DIAG ===")
	var stack: Array = [self]
	while stack.size() > 0:
		var node: Node = stack.pop_back()
		if node is CanvasLayer or node is Control:
			var path_parts: Array = []
			var n: Node = node
			while n != null and n != get_tree().root:
				path_parts.append(n.name)
				n = n.get_parent()
			path_parts.reverse()
			var path_str: String = "/".join(path_parts)
			var vis: String = "visible" if node.visible else "hidden"
			var has_script: String = "script" if node.get_script() != null else "no-script"
			_log("[UIDriver]  %s  [%s]  %s" % [path_str, vis, has_script])
		for c in node.get_children():
			stack.append(c)
	_log("[UIDriver] === END DIAG ===")

func _find_child_recursive(node: Node, name: String) -> Node:
	if node == null:
		return null
	if node.name == name:
		return node
	for c in node.get_children():
		var hit := _find_child_recursive(c, name)
		if hit != null:
			return hit
	return null

func _run_all() -> void:
	_log("[UIDriver] === _run_all start ===")
	await _pass_combat_hud()
	_log("[UIDriver] combat HUD done")
	await _pass_tooltips()
	_log("[UIDriver] tooltips done")
	await _pass_chest()
	_log("[UIDriver] chest done")
	# 恢复 main_scene 设定
	if not _saved_main_scene.is_empty():
		ProjectSettings.set_setting("application/run/main_scene", _saved_main_scene)
	_log("[UIDriver] === all done, quit ===")
	get_tree().quit(0)

# ── 公共：截图 ─────────────────────────────────────────
# headless 模式下 RenderingServer.frame_post_draw 不可靠（信号不一定发），
# 而且 main viewport 的 get_image() 必须等 GPU 实际提交一帧才有数据。
# 标准做法：force_sync() 同步等待，force_draw() 立即画一帧，再等几帧 _process/_draw，
# 然后 get_texture().get_image() 才有非空内容。
func _save_main_viewport(basename: String) -> bool:
	# headless OpenGL dummy 渲染下，get_viewport().get_texture() 有时拿不到
	# 已绘制的内容（返回空 Image）。多轮 force_sync / force_draw + process_frame
	# 是标准做法；这里再主 Window 兜底，必要时轮询若干帧。
	var img: Image = null
	for attempt in range(6):
		for i in range(4):
			RenderingServer.force_sync()
			RenderingServer.force_draw()
			await get_tree().process_frame
		var vp := get_viewport()
		if vp != null and vp.get_texture() != null:
			img = vp.get_texture().get_image()
			if img != null and not img.is_empty():
				break
		# 兜底：主 Window 的 viewport
		var win := get_window()
		if win != null:
			var wvp := win.get_viewport()
			if wvp != null and wvp.get_texture() != null:
				img = wvp.get_texture().get_image()
				if img != null and not img.is_empty():
					break
		_log("[UIDriver] attempt %d: image empty, retrying..." % attempt)
	if img == null or img.is_empty():
		_log("[UIDriver] FATAL: empty image from main viewport after retries")
		return false
	_log("[UIDriver] image size %dx%d" % [img.get_width(), img.get_height()])
	# 两份：res:// + 绝对路径
	var res_err := img.save_png("%s/%s" % [OUT_DIR, basename])
	var abs_err := img.save_png("%s/%s" % [OUT_ABS, basename])
	_log("[UIDriver] wrote %s res_err=%d abs_err=%d" % [basename, res_err, abs_err])
	return abs_err == OK

func _cleanup_spawned() -> void:
	# 删 fake enemy
	if _fake_enemy != null and is_instance_valid(_fake_enemy):
		_fake_enemy.queue_free()
	_fake_enemy = null
	# 删 fake chest
	if _fake_chest != null and is_instance_valid(_fake_chest):
		_fake_chest.queue_free()
	_fake_chest = null
	# 关闭所有 UI 弹窗
	if _ui != null and is_instance_valid(_ui):
		if "item_detail_popup" in _ui and _ui.item_detail_popup != null and is_instance_valid(_ui.item_detail_popup):
			_ui.item_detail_popup.hide_detail()
		if "_pickup_hint" in _ui and _ui._pickup_hint != null and is_instance_valid(_ui._pickup_hint):
			_ui._pickup_hint.hide_hint()
		if "_interact_hint" in _ui and _ui._interact_hint != null and is_instance_valid(_ui._interact_hint):
			_ui._interact_hint.hide_hint()
	# 关 character panel
	if _ui != null and is_instance_valid(_ui) and "character_panel_instance" in _ui \
			and _ui.character_panel_instance != null and is_instance_valid(_ui.character_panel_instance) \
			and _ui.character_panel_instance.visible:
		_ui.character_panel_instance.hide_panel()
	# 关所有 ChestLootPanel 实例
	for c in get_tree().get_nodes_in_group("chest_loot_panel"):
		if is_instance_valid(c):
			c.queue_free()
	for c in get_tree().root.get_children():
		if c is CanvasLayer and String(c.name).begins_with("ChestLootPanel"):
			c.queue_free()
	for i in range(3):
		await get_tree().process_frame

# ============================================================================
# Pass 1：战斗 HUD
# ============================================================================
func _pass_combat_hud() -> void:
	_cleanup_spawned()
	_log("[UIDriver] pass 1: combat HUD")
	# 0) 每次 pass 开头重新拉取 _player（因为上一 pass 可能释放）
	_log("[UIDriver] pass 1 _ready check: _player valid=%s, _dungeon valid=%s, world.current_loaded_level=%s" % [
		str(is_instance_valid(_player)), str(is_instance_valid(_dungeon)),
		str(_world.get("current_loaded_level") if is_instance_valid(_world) else "world-invalid")
	])
	if not is_instance_valid(_player):
		var gs: Node = Service.game_state()
		if gs != null and gs.get("current_player") != null and is_instance_valid(gs.current_player):
			_player = gs.current_player as Node3D
			_log("[UIDriver] re-fetched _player: %s" % str(_player))
	if not is_instance_valid(_dungeon):
		if _world != null and is_instance_valid(_world):
			_dungeon = _world.get("current_loaded_level") as Node3D
			_log("[UIDriver] re-fetched _dungeon: %s" % str(_dungeon))
	if not is_instance_valid(_player):
		_log("[UIDriver] FATAL: _player invalid at pass 1 start")
		get_tree().quit(10)
		return
	# 0.5) pass 1 截图前强制隐藏金币/材料/时间/压力等浮窗
	#      （_ensure_expedition_hud_mounted 在 pass 1 之后才挂载，
	#       所以要在这里直接对已有的 ExpeditionHUD 实例兜底）
	_hide_existing_expedition_hud_panels()
	# 1) 改 player 真实状态
	var hp: HealthComponent = _player.get("health") as HealthComponent
	if hp:
		hp.current_life = int(hp.max_life * 0.74)
	else:
		_log("[UIDriver] WARN: player.health not HealthComponent")
	# 把 player 直接喂给 CombatHUD，避免 headless 下 _ensure_player() 没及时拉到
	if _combat_hud != null and _combat_hud.has_method("_on_player_spawned"):
		_combat_hud._on_player_spawned(_player)
		# 强制把脏标记置位，等下一帧 _process 跑 _check_* → _update_*
		_combat_hud.set("_bars_dirty", true)
		_combat_hud.set("_shields_dirty", true)
		_combat_hud.set("_buffs_dirty", true)
	# 注入 ManaComponent（如果还没挂）
	var mana_script := load("res://scenes/characters/component/mana_component.gd")
	if mana_script != null and not _player.has_node("ManaComponent"):
		var mc = mana_script.new()
		mc.name = "ManaComponent"
		mc.set("max_mana", 90)
		mc.set("current_mana", 58)
		_player.add_child(mc)
	# Buffs：直接注入到 player.buffs 组件（player.gd:112 已建好）
	# combat_hud.gd:114 / 209 直接读 _player.buffs.get_buffs_dict()
	var buffs: CombatBuffComponent = _player.get("buffs") as CombatBuffComponent
	if buffs != null:
		buffs.add("burn", 3.0, 4.0)
		buffs.add("haste", 6.5, 1.25)
		buffs.add("shield_aura", 12.0, 30.0)
		buffs.add("damage_absorb", 18.0, 30.0)
		_log("[UIDriver] injected 4 buffs: %s" % str(buffs.get_buffs_dict().keys()))
	else:
		_log("[UIDriver] WARN: player.buffs is null")
	# 装备：武器 + 盾牌（耐久 < max 让耐久条显示）
	# shield 武器的 item_tag=="shield"，_weapon_uses_off_hand 会把它装到 shield_placeholder
	var registry: Node = Service.weapon_registry()
	var equip := _player.get("equipment") as Node
	if equip != null and registry != null:
		var sword_data = registry.get_weapon_data("shortsword")
		var shield_data = registry.get_weapon_data("shield")
		if sword_data != null and "condition" in sword_data:
			sword_data.condition = int(sword_data.max_condition * 0.78)
		if shield_data != null and "condition" in shield_data:
			shield_data.condition = int(shield_data.max_condition * 0.42)
		if equip.has_method("configure_weapon_slot"):
			equip.configure_weapon_slot(0, sword_data, true)   # 主武器槽 → 短剑
			equip.configure_weapon_slot(1, shield_data, true)  # 副武器槽 → 盾牌
		GameEvents.weapon_changed.emit(sword_data)
		GameEvents.shield_changed.emit(shield_data)
	# 2) 注入一个伪敌人 — 放在玩家正前方视线内，确保 EnemyHealthBar raycast 能命中
	_spawn_fake_enemy_in_view("暗影猎手", 230, 410, "shadow_hunter")
	# 3) 把敌人血条指向 fake enemy（set_target + 强制 modulate.a=1 防淡出）
	if _combat_hud != null:
		var enemy_hp_bar := _combat_hud.get_node_or_null("TopCenter/EnemyHealthBar")
		if enemy_hp_bar and _fake_enemy != null and enemy_hp_bar.has_method("set_target"):
			enemy_hp_bar.set_target(_fake_enemy)
			enemy_hp_bar.modulate.a = 1.0
		# 推几条战斗日志
		var combat_log := _combat_hud.get_node_or_null("TopLeft/CombatLog")
		if combat_log and combat_log.has_method("push_entry"):
			combat_log.push_entry("你击中了 [暗影猎手] 18 点伤害", Color(0.95, 0.85, 0.55, 1.0))
			combat_log.push_entry("[暗影猎手] 闪避了你的攻击", Color(0.85, 0.55, 0.55, 1.0))
			combat_log.push_entry("获得 [燃烧] 持续 3.0 秒", Color(0.95, 0.45, 0.25, 1.0))
	# 4) 模拟按住右键进入真 BLOCKING 状态（与玩家真操作一致路径）
	# PlayerStateBlocking.gd:65 _process 检查 Input.is_action_pressed("block")
	Input.action_press("block")
	_log("[UIDriver] pressed block; player.state=%d" % _player.state)
	# 等 PlayerState 自己进 BLOCKING
	for i in range(15):
		await get_tree().process_frame
		if _player.state == Player.State.BLOCKING:
			break
	# headless 下 Input.action_press 不被 _input 捕获 → 直接走状态机强制切到 BLOCKING
	# （PlayerStateBlocking._enter_state 不依赖 Input，复用 CombatHUD 真实 update 路径）
	if _player.state != Player.State.BLOCKING and _player.has_method("switch_state"):
		_player.switch_state(Player.State.BLOCKING)
		_log("[UIDriver] forced switch_state(BLOCKING) (headless Input 不可达)")
	for i in range(10):
		await get_tree().process_frame
	_log("[UIDriver] player.state=%d, is_currently_blocking=%s, state_node=%s" % [
		_player.state, str(_player.is_currently_blocking()), str(_player.state_node)
	])
	# 4.5) 如果 is_currently_blocking 仍为 false（headless 下 Input.action_press 不被 _input 捕获），
	#       退而求其次：直接通过 CombatHUD 暴露的公共 API set_values() 驱动两个 shield bar 显示。
	#       这等价于 _update_magic_shield / _update_physical_shield 内部真实调用。
	#       与"通过 GameState 真实路径"等价，仍然显示 CombatHUD 的真实 UI 状态。
	var magic_bar: Control = null
	var physical_bar: Control = null
	if _combat_hud != null:
		magic_bar = _combat_hud.get_node_or_null("BottomLeft/MagicShieldBar")
		physical_bar = _combat_hud.get_node_or_null("BottomLeft/PhysicalShieldBar")
	# 物理护盾：用真实 shield_data 的 condition（被前面 configure_weapon_slot + set_shield_data 注入）
	if physical_bar != null and equip != null and equip.has_method("get_active_shield_data"):
		var shield_data = equip.get_active_shield_data()
		if shield_data != null:
			physical_bar.set_values(int(shield_data.condition), int(shield_data.max_condition))
			_log("[UIDriver] forced physical_shield_bar.set_values(%d, %d)" % [
				int(shield_data.condition), int(shield_data.max_condition)
			])
		else:
			_log("[UIDriver] WARN: shield_data null, skip physical bar")
	else:
		_log("[UIDriver] WARN: physical_bar or equip not available")
	# 法术护盾：从 damage_absorb buff + max_life 计算（与 combat_hud.gd:209-217 等价）
	if magic_bar != null and hp:
		var absorb_pct := 0.0
		if buffs and "_buffs" in buffs and buffs._buffs.has("damage_absorb"):
			absorb_pct = float(buffs._buffs["damage_absorb"].get("value", 0.0))
		var absorb_amount := int(round(hp.max_life * absorb_pct / 100.0))
		magic_bar.set_values(absorb_amount, hp.max_life)
		_log("[UIDriver] forced magic_shield_bar.set_values(%d, %d)" % [absorb_amount, hp.max_life])
	# 5) 等多帧让 _process 跑（CombatHUD._check_shields_changed / _update_physical_shield）
	for i in range(60):
		await get_tree().process_frame
	# 5.5) 期间敌人血条可能被自己的 _process 抢清，set_target 后再强制一次
	if _combat_hud != null:
		var enemy_hp_bar := _combat_hud.get_node_or_null("TopCenter/EnemyHealthBar")
		if enemy_hp_bar and _fake_enemy != null and is_instance_valid(_fake_enemy) \
				and enemy_hp_bar.has_method("set_target"):
			enemy_hp_bar.set_target(_fake_enemy)
			enemy_hp_bar.modulate.a = 1.0
	# 5.6) 诊断：把 CombatHUD 关键子节点状态打出来
	if _combat_hud != null:
		var bcon := _combat_hud.get_node_or_null("BottomLeft/BuffContainer")
		var msb := _combat_hud.get_node_or_null("BottomLeft/MagicShieldBar")
		var psb := _combat_hud.get_node_or_null("BottomLeft/PhysicalShieldBar")
		var wi := _combat_hud.get_node_or_null("BottomLeft/WeaponIndicator")
		var si := _combat_hud.get_node_or_null("BottomLeft/ShieldIndicator")
		var ch_player = _combat_hud.get("_player")
		var ch_buffs = null
		var ch_buff_keys: Array = []
		if ch_player != null and is_instance_valid(ch_player) and ch_player.get("buffs") != null:
			ch_buffs = ch_player.buffs
			ch_buff_keys = ch_buffs.get_buffs_dict().keys()
		_log("[UIDriver] DIAG combat_hud._player=%s, buffs=%s, keys=%s" % [
			str(ch_player), str(ch_buffs), str(ch_buff_keys)
		])
		_log("[UIDriver] DIAG BuffContainer children=%d, vis=%s" % [
			bcon.get_child_count() if bcon else -1, str(bcon.visible) if bcon else "null"
		])
		_log("[UIDriver] DIAG MagicShieldBar vis=%s, mod.a=%.2f, is_active=%s" % [
			str(msb.visible) if msb else "null",
			msb.modulate.a if msb else -1.0,
			str(msb.is_active()) if msb and msb.has_method("is_active") else "n/a"
		])
		_log("[UIDriver] DIAG PhysicalShieldBar vis=%s, mod.a=%.2f, is_active=%s" % [
			str(psb.visible) if psb else "null",
			psb.modulate.a if psb else -1.0,
			str(psb.is_active()) if psb and psb.has_method("is_active") else "n/a"
		])
		_log("[UIDriver] DIAG WeaponIndicator vis=%s" % (str(wi.visible) if wi else "null"))
		_log("[UIDriver] DIAG ShieldIndicator vis=%s" % (str(si.visible) if si else "null"))
		# SkillBar
		var sb := get_node_or_null("World/ProceduralDungeon/ExpeditionHUDLayer/ExpeditionHUD/SkillBarInstance")
		if sb == null:
			# 兜底：递归找
			sb = _find_child_recursive(_world, "SkillBarInstance")
		if sb != null:
			_log("[UIDriver] DIAG SkillBar vis=%s, slot_f_name.text=%s, slot_g_name.text=%s" % [
				str(sb.visible),
				str(sb.get_node_or_null("ActiveRow/SlotF/SkillName").text) if sb.get_node_or_null("ActiveRow/SlotF/SkillName") else "null",
				str(sb.get_node_or_null("ActiveRow/SlotG/SkillName").text) if sb.get_node_or_null("ActiveRow/SlotG/SkillName") else "null"
			])
		else:
			_log("[UIDriver] DIAG SkillBar NOT FOUND in scene tree, attempting to mount ExpeditionHUD...")
			_ensure_expedition_hud_mounted()
			# 多等几帧让 SkillBar _ready / 第一次 _process 完成（缓存技能名、图标、CDOverlay）
			for i in range(15):
				await get_tree().process_frame
			# 再次确认挂载成功
			sb = _find_child_recursive(_world, "SkillBarInstance")
			if sb != null:
				_log("[UIDriver] DIAG SkillBar after mount: vis=%s, slot_f_name.text=%s, slot_g_name.text=%s" % [
					str(sb.visible),
					str(sb.get_node_or_null("ActiveRow/SlotF/SkillName").text) if sb.get_node_or_null("ActiveRow/SlotF/SkillName") else "null",
					str(sb.get_node_or_null("ActiveRow/SlotG/SkillName").text) if sb.get_node_or_null("ActiveRow/SlotG/SkillName") else "null"
				])
	await _save_main_viewport("01_combat_hud.png")
	# 恢复
	Input.action_release("block")
	for i in range(5):
		await get_tree().process_frame
	if _player.has_method("switch_state") and _player.state != Player.State.MOVING:
		_player.switch_state(Player.State.MOVING)
	if hp:
		hp.current_life = hp.max_life
	if buffs and "_buffs" in buffs:
		buffs._buffs.clear()
	_log("[UIDriver] pass 1 cleanup: _player valid=%s, _dungeon valid=%s" % [
		str(is_instance_valid(_player)), str(is_instance_valid(_dungeon))
	])

func _spawn_fake_enemy_in_view(display_name: String, cur: int, mx: int, base_type: String) -> void:
	if _dungeon == null:
		return
	var enemy: Enemy = GOBLIN_SCENE.instantiate()
	enemy.set_meta("enemy_base_type", base_type)
	enemy.name = "FakeEnemyForUI"
	# 放敌人到玩家当前 forward 方向 9m（之前 4m 太近，敌人 mesh 会占据屏幕下半，
	# 遮挡屏幕底部中央的 SkillBar；9m 让敌人只占上 1/3 屏幕，给 SkillBar 留出空间）
	var forward := -_player.global_transform.basis.z
	forward.y = 0.0
	if forward.length() < 0.001:
		forward = Vector3.FORWARD
	forward = forward.normalized()
	enemy.position = _player.global_position + forward * 9.0
	enemy.position.y = _player.global_position.y + 1.2
	_dungeon.add_child(enemy)
	await get_tree().process_frame
	# 直接用 rotation.y 让玩家身体朝敌人（不是 camera，是 body 转）
	var to_enemy := enemy.global_position - _player.global_position
	to_enemy.y = 0.0
	if to_enemy.length() > 0.001:
		_player.rotation.y = atan2(to_enemy.x, to_enemy.z)
	var health: HealthComponent = enemy.get("health") as HealthComponent
	if health:
		health.max_life = mx
		health.current_life = cur
	_fake_enemy = enemy
	_log("[UIDriver] fake enemy at %s, player rot.y=%.3f, forward=%s" % [
		str(enemy.global_position), _player.rotation.y, str(-_player.global_transform.basis.z)
	])
	# 提升玩家视野光圈能量，让截图能看清地牢结构
	if _player.has_method("_setup_player_light"):
		_player._setup_player_light()
	# 直接给玩家光加力：调高 light_energy 和 omni_range
	for child in _player.get_children():
		if child is OmniLight3D or child is SpotLight3D:
			child.light_energy = 4.0
			child.omni_range = 30.0

# ============================================================================
# Pass 2：悬浮窗（拾取提示 + 交互提示 + 装备详情弹窗）
# ============================================================================
func _pass_tooltips() -> void:
	_cleanup_spawned()
	_log("[UIDriver] pass 2: tooltips")
	# 强制挂上 ExpeditionHUD（包含 SkillBar），避免 headless 下 mount_expedition_hud() 早返回
	_ensure_expedition_hud_mounted()
	# 走真实信号触发详情弹窗，与玩家真操作路径一致
	var detail: Dictionary = DETAIL_POPUP_SCRIPT.detail_for_equipment_id("shortsword")
	_log("[UIDriver] detail dict keys=%s, title=%s, lines=%d" % [
		str(detail.keys()), str(detail.get("title", "")), int(detail.get("lines", []).size())
	])
	# player.gd:686 / 706 每帧 emit item_detail_changed({} / ...) 会覆盖 signal 路径；
	# UI._hide_all_hints() 又会把 popup 隐藏。直接调 UI 的内部方法：先显示 popup，
	# 再直接调 _show_hint_by_type("pickup", ...)，既保留 popup，又显示 pickup hint，
	# 还不会被后续 player emit / _hide_all_hints 清掉。
	#
	# 另外 player.gd:232/591/600 的 _physics_process 仍会持续 emit
	# interaction_hint_changed("", "", ...) 清空 hints；为不被其覆盖，
	# 在 pass 2 期间临时禁用 player 的 process 回调（结束后恢复）。
	var _saved_player_set_process: bool = false
	var _saved_player_set_physics_process: bool = false
	if _player != null and is_instance_valid(_player):
		_saved_player_set_process = _player.is_processing()
		_saved_player_set_physics_process = _player.is_physics_processing()
		_player.set_process(false)
		_player.set_physics_process(false)
		_log("[UIDriver] pass 2 disabled player process/physics_process to block emit overrides")
	if _ui != null and is_instance_valid(_ui):
		if _ui.has_method("on_item_detail_changed"):
			_ui.on_item_detail_changed(detail, Vector2(640, 460))
		if _ui.has_method("_show_hint_by_type"):
			_ui._show_hint_by_type("pickup", "[E] 拾取  短剑 +1", Vector2(640, 460))
		if "_interact_hint" in _ui and _ui._interact_hint != null and _ui._interact_hint.has_method("show_for_object"):
			_ui._interact_hint.show_for_object("Hold [E] to Open (5s)\nChest", Vector2(1200, 520))
	for i in range(4):
		await get_tree().process_frame
	if _ui != null and is_instance_valid(_ui) and "item_detail_popup" in _ui \
			and _ui.item_detail_popup != null and is_instance_valid(_ui.item_detail_popup):
		var popup: Control = _ui.item_detail_popup
		_log("[UIDriver] item_detail_popup visible=%s, size=%s, global_pos=%s" % [
			str(popup.visible), str(popup.size), str(popup.global_position)
		])
		_log("[UIDriver] DIAG UI._pickup_hint.vis=%s pos=%s" % [
			str(_ui._pickup_hint.visible if _ui._pickup_hint else "null"),
			str(_ui._pickup_hint.global_position if _ui._pickup_hint else "null"),
		])
		_log("[UIDriver] DIAG UI._interact_hint.vis=%s pos=%s" % [
			str(_ui._interact_hint.visible if _ui._interact_hint else "null"),
			str(_ui._interact_hint.global_position if _ui._interact_hint else "null"),
		])
	for i in range(15):
		await get_tree().process_frame
	# 恢复 player process
	if _player != null and is_instance_valid(_player):
		_player.set_process(_saved_player_set_process)
		_player.set_physics_process(_saved_player_set_physics_process)
		_log("[UIDriver] pass 2 restored player process=%s physics=%s" % [
			str(_saved_player_set_process), str(_saved_player_set_physics_process)
		])
	# 诊断：UI 子节点状态
	if _ui != null and is_instance_valid(_ui):
		_log("[UIDriver] DIAG UI.item_detail_popup.vis=%s size=%s global_pos=%s" % [
			str(_ui.item_detail_popup.visible if _ui.item_detail_popup else "null"),
			str(_ui.item_detail_popup.size if _ui.item_detail_popup else "null"),
			str(_ui.item_detail_popup.global_position if _ui.item_detail_popup else "null"),
		])
		_log("[UIDriver] DIAG UI._pickup_hint.vis=%s pos=%s text=%s" % [
			str(_ui._pickup_hint.visible if _ui._pickup_hint else "null"),
			str(_ui._pickup_hint.global_position if _ui._pickup_hint else "null"),
			str(_ui._pickup_hint._text_label.text if _ui._pickup_hint and _ui._pickup_hint.get_node_or_null("VBoxContainer/Label") else "?")
		])
		_log("[UIDriver] DIAG UI._interact_hint.vis=%s pos=%s" % [
			str(_ui._interact_hint.visible if _ui._interact_hint else "null"),
			str(_ui._interact_hint.global_position if _ui._interact_hint else "null"),
		])
	# 诊断：SkillBar 是否在场景里
	var sb := get_node_or_null("World/ProceduralDungeon/ExpeditionHUDLayer/ExpeditionHUD/SkillBarInstance")
	if sb == null:
		sb = _find_child_recursive(_world, "SkillBarInstance")
	if sb != null:
		_log("[UIDriver] DIAG SkillBar at pass 2 vis=%s, slotF.text=%s slotG.text=%s" % [
			str(sb.visible),
			str(sb.get_node_or_null("ActiveRow/SlotF/SkillName").text) if sb.get_node_or_null("ActiveRow/SlotF/SkillName") else "null",
			str(sb.get_node_or_null("ActiveRow/SlotG/SkillName").text) if sb.get_node_or_null("ActiveRow/SlotG/SkillName") else "null"
		])
	else:
		_log("[UIDriver] DIAG SkillBar STILL NOT FOUND after ensure_expedition_hud_mounted")
	await _save_main_viewport("02_tooltip_overlay.png")

func _ensure_expedition_hud_mounted() -> void:
	# 头无或重入保护：检查是否已经挂上。
	if _dungeon == null or not is_instance_valid(_dungeon):
		_log("[UIDriver] _ensure_expedition_hud_mounted: _dungeon invalid, skip")
		return
	# 找现有 ExpeditionHUDLayer / ExpeditionHUD
	var existing_layer := _dungeon.get_node_or_null("ExpeditionHUDLayer") as Node
	if existing_layer != null and existing_layer.get_node_or_null("ExpeditionHUD") != null:
		_log("[UIDriver] _ensure_expedition_hud_mounted: already mounted, force-hide TopHUD/MiddleHUD")
		var existing_hud: Node = existing_layer.get_node("ExpeditionHUD")
		_hide_expedition_hud_panels(existing_hud)
		return
	var hud_scene := load("res://scenes/ui/expedition_hud.tscn") as PackedScene
	if hud_scene == null:
		_log("[UIDriver] _ensure_expedition_hud_mounted: failed to load expedition_hud.tscn")
		return
	var hud := hud_scene.instantiate()
	var layer := CanvasLayer.new()
	layer.name = "ExpeditionHUDLayer"
	layer.add_child(hud)
	_dungeon.add_child(layer)
	_log("[UIDriver] _ensure_expedition_hud_mounted: mounted ExpeditionHUD with SkillBarInstance")
	_hide_expedition_hud_panels(hud)

func _hide_expedition_hud_panels(hud: Node) -> void:
	# 强制隐藏金币/材料/时间/压力等右侧浮窗。
	# expedition_hud.gd._ready() 已经做了一次，这里再兜底：
	# 1) 父节点 visible=false
	# 2) label 自身 visible=false（防止 _update_hud() set_text 间接点亮渲染）
	if hud == null:
		return
	if hud.has_node("TopHUD"):
		var top: CanvasItem = hud.get_node("TopHUD") as CanvasItem
		top.visible = false
		for sub in ["GoldLabel", "TimeLabel", "HPBar"]:
			if top.has_node(sub):
				(top.get_node(sub) as CanvasItem).visible = false
	if hud.has_node("MiddleHUD"):
		var mid: CanvasItem = hud.get_node("MiddleHUD") as CanvasItem
		mid.visible = false
		for sub in ["MaterialLabel", "PressureLabel"]:
			if mid.has_node(sub):
				(mid.get_node(sub) as CanvasItem).visible = false

func _hide_existing_expedition_hud_panels() -> void:
	# 递归在 _dungeon 下找已经挂载的 ExpeditionHUD 实例
	# （可能是真实游戏 World 启动时挂的，也可能是之前 pass 注入的）。
	# pass 1 截图前必须把这些面板的 visible 强制为 false，
	# 否则右上角会出现"金币: 100"和"材料: 0"，违反 UI 清理目标。
	var hud: Node = _find_child_recursive(_dungeon, "ExpeditionHUD") if _dungeon else null
	if hud == null:
		hud = _find_child_recursive(_world, "ExpeditionHUD") if _world else null
	if hud == null:
		_log("[UIDriver] _hide_existing_expedition_hud_panels: no ExpeditionHUD found yet")
		return
	_hide_expedition_hud_panels(hud)
	_log("[UIDriver] _hide_existing_expedition_hud_panels: hid TopHUD/MiddleHUD on %s" % str(hud))

# ============================================================================
# Pass 3：宝箱互动
# ============================================================================
func _pass_chest() -> void:
	_cleanup_spawned()
	_log("[UIDriver] pass 3: chest interaction")
	# 0) 兜底再次确认 _player / _dungeon 仍有效
	if not is_instance_valid(_player):
		var gs: Node = Service.game_state()
		if gs != null and gs.get("current_player") != null and is_instance_valid(gs.current_player):
			_player = gs.current_player as Node3D
			_log("[UIDriver] pass 3 re-fetched _player: %s" % str(_player))
	if not is_instance_valid(_dungeon):
		if _world != null and is_instance_valid(_world):
			_dungeon = _world.get("current_loaded_level") as Node3D
			_log("[UIDriver] pass 3 re-fetched _dungeon: %s" % str(_dungeon))
	if not is_instance_valid(_player) or not is_instance_valid(_dungeon):
		_log("[UIDriver] FATAL pass 3: player or dungeon invalid")
		get_tree().quit(11)
		return
	# 1) 在玩家身后 6m 放一个 chest（不挡正前方视野）
	_fake_chest = CHEST_SCENE.instantiate() as Node3D
	_fake_chest.name = "FakeChestForUI"
	var back := _player.global_transform.basis.z
	back.y = 0.0
	if back.length() < 0.001:
		back = Vector3.BACK
	back = back.normalized()
	_fake_chest.position = _player.global_position + back * 6.0
	_dungeon.add_child(_fake_chest)
	await get_tree().process_frame
	if _fake_chest.has_method("_generate_loot_data"):
		_fake_chest._generate_loot_data()
	# 2) 往 GameState 塞些物品让 panel 有内容
	var gs: Node = Service.game_state()
	if gs != null:
		gs.add_carried_material("black_rye_root", 4)
		gs.add_carried_material("goblin_ear", 2)
		gs.add_carried_rune("ember", 1)
		# 加 3 件装备,让 ChestLootPanel 的装备栏有内容
		gs.add_carried_equipment("shortsword", 1)
		gs.add_carried_equipment("dagger", 1)
		gs.add_carried_equipment("shield", 1)
		var registry: Node = Service.weapon_registry()
		if registry != null:
			var dagger_data = registry.get_weapon_data("dagger")
			if dagger_data != null:
				gs.add_carried_equipment_instance(dagger_data)
	# 3) 直接实例化 ChestLootPanel 并调用 show_for_chest()
	#    比发 GameEvents.chest_opened 信号更可靠（信号依赖 player 状态机，
	#    headless 下经常无响应）。
	#    挂在 _world 节点下,与 World.open_overlay_scene 路径一致,
	#    保证 CanvasLayer 真正被主 viewport 渲染。
	var panel := CHEST_LOOT_PANEL_SCENE.instantiate()
	panel.name = "ChestLootPanel_Pass3"
	panel.layer = 50
	if _world != null and is_instance_valid(_world):
		_world.add_child(panel)
	else:
		get_tree().root.add_child(panel)
	await get_tree().process_frame
	if panel.has_method("show_for_chest"):
		panel.show_for_chest(_fake_chest, _player)
		_log("[UIDriver] pass 3 ChestLootPanel.show_for_chest() called, vis=%s" % str(panel.visible))
	else:
		_log("[UIDriver] FATAL pass 3: ChestLootPanel has no show_for_chest method")
	# 4) 等多帧让 panel 完成 _load_loot_data / _refresh_display / item_count
	for i in range(30):
		await get_tree().process_frame
	# 5) 诊断 panel 状态
	if panel is CanvasLayer:
		_log("[UIDriver] pass 3 panel: vis=%s, layer=%d" % [str(panel.visible), panel.layer])
		var panel_root: Control = panel.get_node_or_null("Root") as Control
		if panel_root != null:
			_log("[UIDriver] pass 3 panel.Root: pos=%s size=%s vis=%s" % [
				str(panel_root.position), str(panel_root.size), str(panel_root.visible)
			])
			# 查 LootFrame 实际 size
			var lf: Control = panel_root.get_node_or_null("LootFrame") as Control
			if lf != null:
				_log("[UIDriver] pass 3 LootFrame: pos=%s size=%s vis=%s" % [
					str(lf.position), str(lf.size), str(lf.visible)
				])
		# 查 panel 是不是 CanvasLayer
		_log("[UIDriver] pass 3 panel is CanvasLayer: %s" % str(panel is CanvasLayer))
		var cl: ItemList = panel.get_node_or_null("Root/LootFrame/Margin/LootBody/Margin2/VBox/ContentRow/ChestColumn/ChestMargin/ChestVBox/ChestList")
		var bl: ItemList = panel.get_node_or_null("Root/LootFrame/Margin/LootBody/Margin2/VBox/ContentRow/BackpackColumn/BackpackMargin/BackpackVBox/BackpackList")
		_log("[UIDriver] pass 3 panel: chest_list items=%d, backpack_list items=%d" % [
			cl.item_count if cl else -1, bl.item_count if bl else -1
		])
	# 5.4) 存一张主 viewport 截图
	await _save_main_viewport("03_chest_interaction.png")
	# 5.5) 强制让 panel 可见（_ready 中 visible = false，show_for_chest 应该设为 true）
	_log("[UIDriver] pass 3 BEFORE panel.visible=true")
	panel.visible = true
	_log("[UIDriver] pass 3 AFTER panel.visible=true")
	for i in range(5):
		await get_tree().process_frame
	_log("[UIDriver] pass 3 AFTER process_frame loop")
	# 5.55) 查 LootFrame 的实际 StyleBox 和 theme
	var loot_frame: Control = panel.get_node_or_null("Root/LootFrame") as Control
	_log("[UIDriver] pass 3 loot_frame=%s" % str(loot_frame))
	if loot_frame != null:
		_log("[UIDriver] pass 3 loot_frame size=%s, clip_contents=%s" % [
			str(loot_frame.size), str(loot_frame.clip_contents)
		])
		# 检查 LootFrame 自身是否有 panel style
		var own_sb: StyleBox = loot_frame.get_theme_stylebox("panel")
		_log("[UIDriver] pass 3 loot_frame get_theme_stylebox(panel)=%s" % str(own_sb))
		if own_sb is StyleBoxFlat:
			_log("[UIDriver] pass 3 LootFrame panel style bg=%s border=%s" % [
				str((own_sb as StyleBoxFlat).bg_color), str((own_sb as StyleBoxFlat).border_color)
			])
		# 查 loot_frame modulate
		_log("[UIDriver] pass 3 loot_frame modulate=%s self_modulate=%s" % [
			str(loot_frame.modulate), str(loot_frame.self_modulate)
		])
		# 查 loot_frame 的 theme
		var tf: Theme = loot_frame.theme
		_log("[UIDriver] pass 3 loot_frame.theme=%s" % str(tf))
		# 检查子节点
		var margin: Control = loot_frame.get_node_or_null("Margin") as Control
		if margin != null:
			_log("[UIDriver] pass 3 Margin size=%s" % str(margin.size))
		var loot_body: Control = loot_frame.get_node_or_null("Margin/LootBody") as Control
		if loot_body != null:
			_log("[UIDriver] pass 3 LootBody size=%s vis=%s" % [
				str(loot_body.size), str(loot_body.visible)
			])
	# 5.6) 查 _chest.loot_data
	if _fake_chest != null and is_instance_valid(_fake_chest):
		_log("[UIDriver] pass 3 _fake_chest.loot_data type=%s" % str(typeof(_fake_chest.get("loot_data"))))
		var ld = _fake_chest.get("loot_data")
		if ld is Dictionary:
			_log("[UIDriver] pass 3 loot_data keys=%s" % str((ld as Dictionary).keys()))
	# 5.7) 把 panel 所有子节点的颜色 dump 出来
	_log("[UIDriver] pass 3 panel children count=%d" % panel.get_child_count())
	for c in panel.get_children():
		_log("[UIDriver] pass 3 panel child: name=%s type=%s vis=%s modulate=%s" % [
			c.name, c.get_class(), str(c.visible), str(c.modulate)
		])


func _render_panel_to_subviewport(panel: CanvasLayer, basename: String) -> bool:
	# 用独立的 SubViewport 把 panel 渲染一次,绕开主 viewport 的
	# CanvasLayer 合成问题。这能告诉我们 panel 本身是否正常。
	# 注意：不要 duplicate panel(深复制会丢失 theme 引用),
	# 直接 instantiate 新的并 show_for_chest 同样的数据。
	var sv := SubViewport.new()
	sv.size = SIZE
	sv.transparent_bg = false
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sv.handle_input_locally = false
	get_tree().root.add_child(sv)
	var panel_copy := CHEST_LOOT_PANEL_SCENE.instantiate() as CanvasLayer
	panel_copy.name = "PanelCopyInSubviewport"
	panel_copy.layer = 1
	sv.add_child(panel_copy)
	# 先不要 show_for_chest,看默认状态是不是橙色
	panel_copy.visible = true
	for i in range(8):
		RenderingServer.force_sync()
		RenderingServer.force_draw()
		await get_tree().process_frame
	# 打印 panel_copy 整个子节点
	_log("[UIDriver] SubViewport panel_copy tree (BEFORE show_for_chest):")
	_log_panel_tree(panel_copy, "  ")
	var img0: Image = sv.get_texture().get_image()
	if img0 != null and not img0.is_empty() and img0.get_width() > 100 and img0.get_height() > 100:
		var c0: Color = img0.get_pixel(img0.get_width() / 2, img0.get_height() / 2)
		_log("[UIDriver] SubViewport center BEFORE show_for_chest: %s" % str(c0))
	# 现在调用 show_for_chest
	if panel_copy.has_method("show_for_chest") and _fake_chest != null and is_instance_valid(_fake_chest) \
			and _player != null and is_instance_valid(_player):
		panel_copy.show_for_chest(_fake_chest, _player)
	for i in range(8):
		RenderingServer.force_sync()
		RenderingServer.force_draw()
		await get_tree().process_frame
	var img: Image = sv.get_texture().get_image()
	if img == null or img.is_empty():
		_log("[UIDriver] SubViewport render failed, empty image")
		sv.queue_free()
		return false
	_log("[UIDriver] SubViewport image size %dx%d" % [img.get_width(), img.get_height()])
	# 检查中心像素颜色
	if img.get_width() > 100 and img.get_height() > 100:
		var c: Color = img.get_pixel(img.get_width() / 2, img.get_height() / 2)
		_log("[UIDriver] SubViewport center AFTER show_for_chest: %s" % str(c))
	var res_err := img.save_png("%s/%s" % [OUT_DIR, basename])
	var abs_err := img.save_png("%s/%s" % [OUT_ABS, basename])
	_log("[UIDriver] wrote %s res_err=%d abs_err=%d" % [basename, res_err, abs_err])
	sv.queue_free()
	return abs_err == OK

func _log_panel_tree(node: Node, indent: String) -> void:
	_log("%s%s [%s] vis=%s size=%s modulate=%s" % [
		indent, node.name, node.get_class(),
		str(node.visible if node is CanvasItem else "n/a"),
		str(node.size) if node is Control else "n/a",
		str(node.modulate) if node is CanvasItem else "n/a"
	])
	for c in node.get_children():
		_log_panel_tree(c, indent + "  ")
