# Lantern Tavern — 项目长期记忆

## 渲染/光照
- 桌面+新款安卓(不做iOS)。forward_plus+forward_mobile。火光/光池/雾/软阴影三后端通用；SDFGI/VoxelGI/SSAO/SSR/Decals/ReflectionProbe 仅 Forward+/Mobile。
- 火把动态 OmniLight3D(warm,range11,energy3.4)；蜡烛/壁炉静态。契约 omni_range>=10 & light_energy>=3.2。灯光预算=12(dungeon_streaming_controller.gd:17)。
- headless RendererDummy `get_texture()`=null→真实截图须窗口模式跑 tools/visual_eval_capture.gd(独立SubViewport own_world_3d=true)。4.7：`ambient_light_enabled`移除→`ambient_light_source=1`；MeshInstance3D 用 `.material_override`。
- **发光边界（用户裁定）**：只有实际光源物体/能量现象可自发光（火焰、蜡烛/烛台、酸液陷阱光体、法术弹/符文爆发、撤离门光核等，且场景有对应 Light3D 或明确能量语义）；所有普通旧资产（角色眼睛/核心、植物、材料掉落、武器符文、门框、地形焦点等）必须为受光非 emissive 材质。运行时导入材质与第一人称副本强制关闭 emission；契约测试 `non_light_asset_emission_test.gd`。

## 像素FX/UI图标
- hurt→blood_fx+voxel_chip+damage_number；blocking→metal_spark。voxel_chip：setup()须add_child前；normalize_creature_id剥实例后缀；mono下%Chips失败→get_node_or_null("Chips")。
- **符文图标规范（已决定）**：`data/rune_glyphs.gd` 为权威程序绘制入口；最终 128×128 RGBA8 完整像素卡面，由 32×32 逻辑像素以最近邻放大，切角透明、暗色纹理背景、深描边+金属双层边框、四角铆钉、五大家族专属框饰与中央符文；无抗锯齿/渐变/软发光/字体直绘。50 枚符文按元素/战斗/神秘/黑暗/神圣语义骨架确定性生成。规范见 `docs/19-符文系统（构筑深度）.md §3.2`，图鉴产物 `reports/ui_preview/rune_codex_128px.png`。
- **符文之语图标规范（已决定）**：独立入口 `data/rune_word_glyphs.gd`，不得复用普通符文卡；最终 128×128，由 32×32 最近邻放大。固定八角圣匣、三层金属框、稀有度金属色、主题冠饰、独立中央复合签名和按配方顺序排列的 2–3 颗符文色宝石。每个 word_id 必须有独立完整纹理：背景连续刻线、边框刻度/缺口、中央签名字形、冠饰线型至少四层受 ID 种子影响；主题仅定义语言，不得作为共享成品模板；测试比较完整 Image.get_data() 确保两两不同。除底部配方宝石方块外，背景/边框/冠饰/侧边/中央严禁孤立或叠加小方块，差异仅用连续折线、刻痕、缺口和轮廓表达。规范见文档 §3.3/术语表，图鉴 `reports/ui_preview/rune_word_codex_128px.png`。
- **战斗资源条规范（已决定）**：左下 HUD HP/MP/两类护盾统一为 320×40 切角像素仪表：深色底板、双层硬边框、左侧几何类型铭牌、分段填充、硬边高光阴影/纹理；HP 赤红，MP 青蓝，魔法护盾奥术蓝，物理护盾冷银。视觉重绘不可改动 CombatHUD 原数值绑定与护盾淡入淡出；预览 `reports/ui_preview/resource_bars_1280x720.png`。
- **法术配方/图标规范（已决定）**：`SpellRecipeData.RECIPES` 是唯一固定有序配方表；每个法术必须有唯一组合、已登记符文和可绘制 `imagery`。`data/spell_glyphs.gd` 按具体意象（火球、冰矛、雷链、毒雾、石墙、圣疗、召唤门等）逐法术绘制独立 128×128 卡面，32×32 最近邻放大；不得抽象模板换色、文字直绘、渐变或软光。图鉴 `reports/ui_preview/spell_codex_128px.png`。
- **法术执行/FX边界（已决定）**：`SpellRuntime` 是固定槽位法术从配方/法力/方向/冷却到结构化 `effect_plan` 的单一计划边界；PlayerSpellCaster 已接 1–5 选槽/C施法，SpellAuthority 已执行 heal/barrier/movement/buff 并接 ProjectileService；联机 CMD_CAST_SPELL 只发槽位，SessionRoot 重解析。SpellWorldExecutor 已消费 ray/area/ground/summon，提供射线、周期区域/地面场、有限时召唤与预算清理；PlayerContext 已有 per-peer SpellLoadout/SpellRuntime/Mana，SessionRoot 已按 ctx 重解析并扣法力。已补地面阻挡、最小召唤攻击、重连 spell_state 快照和服务端 cooldown commit，并闭合 EVT_SPELL_RESOLVED 客户端表现；staff/grimoire 左键共用 ATTACK_PREPARING 蓄力800ms，只有满蓄力才释放当前法术槽，右键按住仅打开编辑界面且不会被 Player 抢回鼠标；仍需每种召唤的独立AI/模型/导航与逐法术最终数值，禁止误报全部33法术最终内容完成。`PixelSpellFx` 仅消费视觉事件，FX 绝不结算伤害；只有明确能量意象可 emission。

## GDScript/测试硬规则
- autoload禁class_name。Variant推断=解析错误→Dictionary.get()/and-or显式标类型；Array[T].pop_back()→`var n:T=`。测试mock参数用Object/Variant勿Node。
- 静态禁tr()→TranslationServer.translate()。PackedScene.instantiate() headless不触发_ready()→须add_child。
- 4.7：RenderingServer.get_rendering_info不收2参→用Performance.RENDER_TOTAL_OBJECTS/PRIMITIVES_IN_FRAME。无@export_tool_button。
- gdUnit4：assert_float.is_equal_approx(e,tol)；Color→assert_bool(c.is_equal_approx(e)).is_true()；await physics_frame(2-3)。run:`$GODOT --headless --path $PROJ -s res://tests/gdunit4_runner.gd -- --ignoreHeadlessMode -a "tests/gdunit/<f>.gd"`(exit 0/101通过)。
- 沙箱：mono写user://被拦→signal 11；须dangerouslyDisableSandbox+重定向APPDATA/LOCALAPPDATA。每批前taskkill Godot_v4.7-stable_mono_win64.exe。重复实例化skeleton敌人(rat)第2次必signal 11。
- ⚠️ **Python 改写 Godot `.gd` 必须 `open(path,"w",encoding="utf-8",newline="\n")`**：漏写 `newline` 在 Windows 会把 LF→CRLF，使 Godot `script.source_code` 长度多出~行数字符，基于 `source.substr(find("func X"),500).contains(...)` 的测试会越界误判失败（排查极耗时）。改完用 `b.count(b"\r\n")` 验证为 0。改用 Edit 工具或带 newline 的 Python。

## 战斗(实现≠文档05)
- 命中恒true(hitbox接触)无投骰；伤害=确定性均值 dice_count*(sides+1)/2。删hit_bonus/armor_evade/shield_block；ignore_def/armor_def留。
- 远程：神射手+10%暴击；穿透×1.12；focused/worn词缀hit_bonus_add→crit_bonus_add。
- ⚠️ 设计文档05仍写%hit(75%基准)，与实现冲突待重写。
- 🚨 **源码战斗公式/算法/数值常量均为占位符，不是已决定数值！** 设计文档(05/06/21/31 等用户拍板的)才是权威；代码应被对齐「到文档」，反之不可。写数值文档时**严禁**把 `*.gd` 里的常量当 `【代码·已决定】`——应标 `【代码·占位符·待定】`，冲突项以文档为准去改代码（不是改文档迁就代码）。
- **流派武器伤害倍率 `damage_mult`（写入 `战斗数值体系.md §2.5`）**：仅乘在**武器伤害**上，**与法术无关**——法术伤害由法术卡自身倍率决定，不乘此值。七流派全部 ✅ 已决定：单手 1.00 / 持盾 0.80 / 双手 1.35 / 双持 主1.00+副0.60 / 徒手 0.80 / 远程 1.00 / 法系 0.50。代码 `STYLE_META` 各流派 `damage_mult` 多为隐式 1.0(双手 1.0)，系占位符待对齐到本文档。
- **流派攻速倍率 `attack_speed_mult` / 移速倍率 `move_speed_mult`**（§2.5.2/§2.5.3）现为**提案·待确认**：单手1.0/0.95→0.95、双手0.85/0.90、双持1.20/1.00、徒手1.30/1.10、远程0.90/0.95、法系0.90/0.95；DPS验算双手1.59为顶点(可能过强,备选0.85→0.75或1.35→1.20)。
- **`attack_speed_mult` 语义=武器冷却（用户裁定）**：不是软攻速加成，而是**硬锁**——冷却期间禁止攻击、必须等待。公式 `武器冷却=BASE_ATTACK_INTERVAL(1.0s)/(attack_speed_mult×敏捷加成)`(`combat_engine.gd:33,54-57`)。⚠️ **代码缺口**：敌人有 `time_since_last_attack`+`duration_between_attacks`+`can_attack()` 时间锁(`enemy_state_moving.gd:132-133`)；**玩家侧无等价冷却锁**，`scenes/characters` 下只有敌人有 `time_since_last_attack`——「玩家武器冷却」概念未落地，待实现对齐文档。

## 敌人/体素/本地化
- 死亡卡死：EnemyStateDying._enter_tree物理步进内做物理→死锁；修复call_deferred("_begin_death_effects")+_is_headless()守卫。
- 敌人死亡表现统一优先 VoxelRagdoll；当前敌人场景里的 PhysicalBoneSimulator3D/PhysicalBone3D 仅为旧资源兼容，不参与存活期或死亡表现，运行时禁用模拟器并清零骨骼碰撞。voxel_prop运行时优先load baked_<kind>.tscn。
- tavern手工场景铁律：禁bake/generate/merge/批量重写；tavern_structure.gd(@tool)仅同步同名+"Body" StaticBody3D，改动仅目标节点。

## 装备/体素建模
- 盔甲/装备是**独立模型**，不是身体模型的一部分；建模为包裹身体的空心板壳（hollow shell），各板在身体表面外侧保持间隙，不能与身体产生正体积重叠。
- 装备与身体验证指标：装备包围盒应大于身体包围盒（“大一圈”）；`armour self-overlap = 0`；`armour-vs-body positive-volume overlap = 0`。
- Blender 5.1 后台导入 GLB 后，必须 `bpy.context.view_layer.update()` + `o.update_tag()` 再读取 `matrix_world` 的 AABB，否则世界矩阵陈旧，导致包围盒尺寸错误。
- Blender 后台运行相对路径行为不一致：GLTF 导出会按启动目录解析，而渲染输出 `scene.render.filepath` 可能解析到 `C:\`。装备/渲染工具应使用 `PROJECT = Path(__file__).resolve().parent.parent` 生成的绝对路径，避免输出漂移。


## 联机
- 链路ClientCommandDriver→NetworkManager.submit_command→SessionRoot.on_command→各Authority→rpc_server_event→bridge。用NetworkManager.multiplayer(禁get_tree().multiplayer)。复制显式RPC。
- 身份锚=player_guid+reconnect_token(ENet重连新peer_id禁作主键)。出生点DungeonLayout.calc_player_spawn_pos()(两端一致)；handle_spawn_request禁硬编码ZERO。勿删TILE_SIZE。
- 同步30Hz节流SNAPSHOT_BROADCAST_HZ=30(_entity_update_buffer→_flush_snapshots；spawn/despawn即时)；快照收敛=全量+客户端反查despawn。心跳5s仅client。
- gotcha：dungeon_layout事件键"type"非"event"；send_interact→target_entity_id；send_attack→target_hint；远端avatar动态get_avatar_peers()。

## 地牢性能(已落地)
- 流控差集增量；火把/音频随可见性暂停。LOS节流0.2s。分帧实例化ENEMY_SPAWN_BATCH_PER_FRAME=4。
- navmesh：ENABLE_ASYNC_NAVMESH_BAKE:=false(默认关)；P-B错峰PATH_UPDATE_JITTER_MS=50；P-C AI模拟半径18m is_ai_active()。
- 真实性能压测后追加：静态环境碰撞仍保持玩家周围3x3 chunk；CharacterBody3D/RigidBody3D/Area3D动态物理仅激活玩家当前chunk(radius=0)，满暗蚀强制追击敌人例外跨区激活。
- `Particles3D`本机4.7不可作类型名→GPUParticles3D/CPUParticles3D。headless `--script`须dangerouslyDisableSandbox+重定向。

## 工具/Git
- 代码图tools/gdscript_codemap.py→根gdscript_codemap.json(docs副本已归档)。
- Bash工具PortableGit路径损坏→改用PowerShell调`D:\Git\cmd\git.exe`；临时文件已.gitignore；push用凭据缓存`GIT_TERMINAL_PROMPT=0`。
- ⚠️ Windows路径分隔符坑：`git ls-files`输出用正斜杠`/`，而`Get-Item.FullName`是反斜杠`\`。用`$tracked -contains $rel`判断"是否已被跟踪"时会因分隔符不匹配而**恒为false**→误把已跟踪文件当未跟踪删掉！比对前必须`$rel = $rel.Replace('\','/')`归一化。
- ⚠️ 禁盲目`git add -A`：会顺带把所有未跟踪改动（含无关工作内容）一并暂存。删错/误暂存后恢复：`git reset -q HEAD`(仅清暂存保留工作树) + `git restore --worktree -- <path>`(从HEAD把误删的已跟踪文件拉回磁盘)。
