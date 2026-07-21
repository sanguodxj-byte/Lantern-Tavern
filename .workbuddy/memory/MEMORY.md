# Lantern Tavern — 项目长期记忆

## 渲染/平台/光照
- 桌面+新款安卓(不做iOS)。forward_plus+forward_mobile。火光/光池/雾/软阴影三后端通用；SDFGI/VoxelGI/SSAO/SSR/Decals/ReflectionProbe 仅 Forward+/Mobile。
- 火把动态 OmniLight3D(warm,range11,energy3.4,fade24/10)；蜡烛/壁炉静态。契约 omni_range>=10 & light_energy>=3.2。procedural_dungeon 流式加载,DUNGEON_VISIBLE_LOCAL_LIGHT_BUDGET=12(代码 dungeon_streaming_controller.gd:17 为准,旧记 28 已作废)。
- **视觉评估截图**：headless 走 RendererDummy，`get_texture()` 返回 null，**须窗口模式**运行 `tools/visual_eval_capture.gd`（独立 SubViewport `own_world_3d=true` + 确定性灯光）才能真实渲染；本机 NVIDIA D3D12 / Forward+。一次性粒子(metal_spark)截图须短帧(~12)捕捉发射瞬间。Godot 4.7 `Environment.ambient_light_enabled` 已移除→用 `ambient_light_source=1`(COLOR)；`MeshInstance3D` 无 `.material`→用 `.material_override`。

## 像素 FX（已接线，非孤立）
- 全经 autoload `FxHelper`(globals/core/fx_helper.gd) 接战斗 runtime：enemy_state_hurt→blood_fx+voxel_chip+damage_number；blocking→metal_spark；dying/impaling→blood_fx。shader_warmer.FX_SCENES 预编译(含 voxel_chip.tscn)。
- 像素 shader 配方(双后端,禁 SCREEN_TEXTURE/discard)：UV floor 网格化→hash(floor(p)) 块噪声→颜色 quantize→alpha step 硬边。参考 fire_flame_particle/metal_spark_particle.gdshader。
- 被击部位体素特效：body_part_resolver.gd(命中点→最近命名骨骼)+voxel_palette.gd(部位/材质/生物→Color)→hurt 取 approx_hit_point→resolve_part_color→create_voxel_chip。gotcha：voxel_chip 须 setup() 在 add_child 前(否则首帧白闪)；normalize_creature_id 须剥实例后缀(Goblin2/@Goblin@2)才匹配生物覆盖；mono 下 %Chips unique_name 失败→改 get_node_or_null("Chips")。测试 body_part_voxel_fx_test.gd(勿入 netcode 清单)。

## GDScript/测试硬规则
- autoload 禁 class_name。Variant 推断=解析错误：Dictionary.get()/and-or 链须显式标类型；Array[T].pop_back()→`var n:T=`。**测试 mock 的函数参数用 Object/Variant,勿用 Node**(4.7 强校验,mock 常是 RefCounted)。var 先声明后用。
- 静态函数禁 tr()→TranslationServer.translate()。PackedScene.instantiate() headless 不触发 _ready()→须 add_child。跨脚本引用用 `const X:=preload(...)`(class_name 预编译期可能不可见)。
- UI 分离属性须 add_theme_constant_override/add_theme_font_size_override。autoload _ready 加子节点须 get_tree().root.call_deferred("add_child",x)。
- 4.7：RenderingServer.get_rendering_info 不收 2 参数、RENDERING_INFO_TOTAL 移除→用 Performance.RENDER_TOTAL_OBJECTS_IN_FRAME/RENDER_TOTAL_PRIMITIVES_IN_FRAME。不支持 @export_tool_button。
- gdUnit4：assert_float.is_equal_approx(e,tol)；Color 无 assert_color→assert_bool(c.is_equal_approx(e)).is_true()；extends GdUnitTestSuite；冲量/速度断言 await physics_frame(2-3)。运行 `$GODOT --headless --path $PROJ -s res://tests/gdunit4_runner.gd -- --ignoreHeadlessMode -a "tests/gdunit/<f>.gd"`，exit 0/101 通过。
- **沙箱**：mono 写 user:// 被拦→signal 11；须 dangerouslyDisableSandbox+重定向 APPDATA/LOCALAPPDATA(Windows 绝对路径 D:/...)。stdout 写文件再 grep,勿管道 head/tail。每批前 taskkill /F /IM Godot_v4.7-stable_mono_win64.exe。headless 检测 DisplayServer.get_name()=="headless"。重复实例化 skeleton-rig 敌人(rat)第2次必 signal 11。

## 伤害/战斗
- 动作战斗：命中恒 true(hitbox 接触),无投骰。删 hit_bonus/armor_evade/shield_block；伤害改确定性均值 dice_count*(sides+1)/2。ignore_def/armor_def 留。
- 远程：神射手→ME.apply_sharpshooter_crit(+10%暴击)；穿透→ME.apply_penetrating_damage(×1.12)。focused/worn 词缀 hit_bonus_add→crit_bonus_add。proc(侧垫步/魔力凝息/招架)保留。

## 敌人/体素/本地化
- 死亡卡死根因：EnemyStateDying._enter_tree 在物理步进内做物理操作→死锁。修复搬进 call_deferred("_begin_death_effects"),headless 用 _is_headless() 守卫布娃娃。回归 enemy_dying_defer_test/enemy_knockback_death_defer_test。
- 体素敌人无 Skeleton3D→VoxelRagdoll；骨架敌人走 PhysicalBoneSimulator3D。voxel_prop 运行时优先 load baked_<kind>.tscn。敌人=蒙皮 GLB+imposter LOD(18)。
- UI tr()；CSV key,en,zh 占位 %%。CanvasLayer：UI=20/CombatHUD=15/tavern_hud=25/Pause=128/overlay=32。
- **tavern 手工场景铁律**：禁任何 bake/generate/merge/批量重写；tavern_structure.gd(@tool) 结构网格同步同名+"Body" StaticBody3D,禁 rebuild/_build/_add_box_collision。改动仅目标节点。

## 联机架构（核心链路 + 铁律）
- 链路：ClientCommandDriver→NetworkManager.submit_command→SessionRoot.on_command(peer_id,cmd)→各 Authority→rpc_server_event→multiplayer_scene_bridge。用 NetworkManager.multiplayer(禁 get_tree().multiplayer)。
- 复制一律显式 RPC(MultiplayerSpawner 4.7 不可靠)。桥接每 peer 只显远端为 avatar,自身经 _spawn_local 守卫 peer_id==_local_peer_id() 跳过。
- 身份锚=player_guid+reconnect_token(ENet 每次重连新 peer_id,禁作主键)。on_command 对 CMD_RESUME 短路→migrate_peer+_migrate_peer_state→resume→发 SESSION_SNAPSHOT。
- 出生点唯一真相源 DungeonLayout.calc_player_spawn_pos()(两端逐字节一致)。handle_spawn_request 必用 player_spawn_pos,绝不硬编码 ZERO。勿删 TILE_SIZE(minimap+2 测试读)。
- world_revision：SessionRoot._bump_world(space) 递增+广播 EVT_WORLD_REVISION_CHANGED；重播已有实体(is_new=false)不 bump。测试勿硬编码,改读 s.world.world_revision。
- 心跳：client_command_driver _physics_process 累加 _maybe_send_heartbeat(5s),仅 is_client。
- 实体同步真相源 EntitySyncAuthority.build_delta(prev,curr)；rebroadcast_entities()委托 reconcile_entities({})。操作=server_spawn/update/despawn_entity。
- 安全基线 security_audit_test.gd(11 例)收口 10 类作弊,穷举 CV.FORBIDDEN_TRUSTED_FIELDS 拒绝。重连恢复 reconnect_recovery_test.gd(5 例)。
- 桥接 _apply_session_snapshot：应用权威快照后反查 despawn 不在快照的本地 _entities 键(消幽灵)。收敛走"快照全量+客户端反查 despawn"。

## 联机 gotcha 速查
- dungeon_layout 事件键 "type" 非 "event"→两键都查。send_interact→target_entity_id；send_attack→target_hint(两键都带)。重复拾取→ERR_INVALID_TARGET。
- String.get_slice("|",1) 返回第1字段；取完整指纹须 line.split("|",true,1)[1]。远端 avatar 动态查 get_avatar_peers() 找"非房主非自身",勿写死 peer id。同 seed→同 layout_fingerprint。
- Phase9 Lobby：主菜单「联机」→lobby_menu.tscn；autoload MultiplayerSession(host_room/join_room/start_expedition/leave_room+晚到重播)。DungeonSession 挂 /root/MultiplayerSession/DungeonSession。leave_room 须 free+复位+room_updated.emit([])。冒烟 tools/_smoke_lobby.gd→LOBBY_SMOKE_RESULT:PASS。
- 带宽节流 SNAPSHOT_BROADCAST_HZ=30,player_snapshot 缓冲 _snapshot_buffer[peer],30Hz _flush_snapshots。PerfMonitor HUD(F3)。
- 专用服务器 scenes/multiplayer/dedicated_server.gd(非玩家)。env DS_PORT(54321)/DS_MAX_PLAYERS(8)/DS_IDLE_SHUTDOWN_SEC(0)。启动器 tools/dedicated_server.cmd。

## 联机集成测试运行
- 双进程 ENet 测试需 5~12min,run_in_background 2min 硬上限强杀→用 PowerShell 前台(带 timeout),超时自动转后台。loopback ENet 偶发不通=沙箱抖动非回归,改 gdUnit 单测验逻辑。
- CI 清单 tools/run_multiplayer_tests.sh(netcode 套件;--list/--selfcheck/--junit=)：Godot 需 Windows 风格 --path(用 cygpath -w)、export APPDATA。断言以 gdUnit Overall Summary/Statistics errors/failures==0(exit 101=orphan 仍 PASS)。非 netcode 套件勿入。
- 全量运行器 tools/run_all_gdunit_batched.ps1：递归扫描 tests/gdunit/*_test.gd 自动发现,reports/all_gdunit_*.csv|log 汇总。命名 *_test.gd 即纳入。
- DSC 单测：spawn_server_entities 内 get_node_or_null("/root/NetworkManager") 要求 DSC 在树内→须 NetworkManager.add_child(ctrl)。每用例 free 旧 session→_ensure_session()→init_server()+is_host=true。

## 地牢性能优化(已落地,2026-07-21)
- 流控跨块差集增量：dungeon_streaming_controller 灯光用 `_active_light_set` 差集(去掉全表 hide-all)，视觉/地形 chunk 用 last-active 集合增量增删。灯光预算仍为 12。
- 火把粒子/音频随可见性暂停：隐藏时递归暂停 GPUParticles3D/CPUParticles3D(emitting=false) 与 AudioStreamPlayer3D(stream_paused=true)。**关键坑**：火把在 `_spawn_torch_on_wall` 只注册为 **physics 节点**(`streamed_physics_nodes`)，不走可视节点，故须在物理激活路径 `_set_visual_root_active` 也对根调 `_apply_visual_side_effects`（首轮只在可视路径做，对火把无效，第二轮补漏）。灯光预算只控 OmniLight3D，不控粒子/音频。
- 敌人 LOS 节流：enemy.gd `has_line_of_sight_to` 加 `_los_cache_timer`(LOS_INTERVAL=0.2s) 缓存射线结果，最多每 0.2s 重测；仅影响初次索敌延迟，已登记玩家不依赖此检测。
- P0 敌人分帧实例化：DungeonSpawner 新增 `build_enemy_spawn_plan(layout,player)`(描述符列表) 与 `instantiate_enemy_descriptor(desc,...)`；`spawn_enemies_from_layout` 增 `batched` 参数(默认 false 保持同步契约,测试安全)。DungeonRuntime.spawn_enemies 改取计划后按帧批量(ENEMY_SPAWN_BATCH_PER_FRAME=4)实例化并注册 streaming；无场景树时回退同步。
- P1 实体同步 30Hz 节流：network_manager `server_update_entity` 有真实 peer 时把 EVT_ENTITY_SNAPSHOT 入 `_entity_update_buffer`(按 entity_id 合并)，在 `tick()`→`_flush_snapshots` 按 SNAPSHOT_BROADCAST_HZ=30 下发；spawn/despawn 仍可靠即时。单进程 headless 仍即时(保持单测同步性)。
- **GDScript gotcha**：粒子基类 `Particles3D` 在本机 Godot 4.7 GDScript 作用域**不可作类型名**(`Could not find type "Particles3D"`)。判粒子须用具体类型 `GPUParticles3D`/`CPUParticles3D`，勿用基类 cast。
- **验证方式**：headless `--script` 加载改文件做解析校验(须 dangerouslyDisableSandbox+重定向 APPDATA/LOCALAPPDATA)。`--script` 模式 autoload 不全→`AudioManager`/`PhysicsSetup` 等"Identifier not found"属误报，非本改动引入；真实游戏内可解析。

## 地牢性能第二轮新热点(2026-07-21 排查) + 第三轮实施
- P-A 生成单帧卡顿：`_build_navigation_mesh`(:720) `bake_from_source_geometry_data` 同步烤整图 navmesh。
  **第三轮实施**：加 `ENABLE_ASYNC_NAVMESH_BAKE:=false`(默认关闭)。开启走 `bake_from_source_geometry_data_async` 后台烤(缺 API 回退同步)。**为何默认关**：本环境仅 headless，导航烘焙文档不稳定(偶发 crash；--script 下异步回调不触发致探针挂起)，无法验证异步能把多边形回填进 NavigationRegion3D；若失败敌人永久无法寻路=灾难。待「有窗口」构建冒烟测试通过后置 true。perf 测试靠 `bake_from_source_geometry_data` 前缀子串仍通过。
- P-B navmesh 雷群(**已实施**)：`enemy_state_moving` 加 `PATH_UPDATE_JITTER_MS:=50` + 每实例 `_path_update_interval_ms := PATH_UPDATE_INTERVAL_MS + randi_range(0,50)`，初始相位 `-randi_range(0,150)`；追击/巡逻两处节流比较改用 `_path_update_interval_ms`。错开同批敌人同帧 `set_target_position`(整图 A*) 触发。
- P-C 物理激活半径 ~36m 与 imposter LOD 18m 失衡(**已实施**)：`enemy.gd` 加 `AI_SIM_RADIUS_M:=18.0`(=ENEMY_IMPOSTER_LOD_DISTANCE 边界)+`is_ai_active()`(已交战/暗蚀强制/玩家≤18m→true;远距未交战→false)；`enemy_state_moving._physics_process` 开头门控：`is_ai_active()` 否时仅清零水平速度+process_movement 保持静止，跳过追击/巡逻 A* 与导航查询。边界互补(LOD>18m 开,AI>18m 停)，无可见冻结。
- P-D 火把/非批装饰为独立 MeshInstance3D 未 MultiMesh→draw call 高；应纳入 `batched_decor_scenes` 或火焰预算(未动,需谨慎处理火把灯光/粒子/音频)。
- P-E shader 首次编译 hitch（无预热）；已有 `shaders/shader_warmer.gd` + `world.gd` 加载期 warming(FX_SCENES 含 voxel_chip 等)，地牢侧可后续补首批敌人材质 warming(未动)。
- P-F/P-G 追击射线预算 / `fx_helper` 特效对象池(观测项,重战时优化,未动)。
- 澄清：`network_manager.tick()` 单人 early-return、`_run_detection` 不存在、`exploration_pressure` 每分钟几次→均非热点。
- 详细报告：docs/地牢性能排查_第二轮.md 含「五、实施状态」。

## 工具
- 场景实例化排错探针 tools/scene_instantiate_probe.gd + 驱动 D:/tmp/run_probe_driver.sh：崩溃可续跑(每场景 add_child 前先写 user://probe_state.txt,驱动重启越过 crasher)。
- GDScript 代码图 tools/gdscript_codemap.py→docs/CODEMAP.md+gdscript_codemap.json(重跑刷新)。
