# Lantern Tavern 架构审查问题关闭矩阵（2026-08-03 19:40）

**范围**：全量核对 `outputs/` 下 19 份审查/整改文档（基线 `project_architecture_review_2026-08-02.md` + 10 份增量复审 + 3 份整改报告）的全部 P0/P1/P2 条目。
**结论**：7×P0 基线全部关闭；后续复审新增 2×P0 已关闭；P1 9 项中 6 项关闭、3 项部分/待产品决策；P2 10 项中 7 项关闭、3 项工程治理遗留。

---

## 1. P0 关闭矩阵（9/9 关闭）

| 编号 | 问题 | 关闭依据 | 状态 |
|---|---|---|---|
| 基线 P0-1 | 服务器移动穿墙 | `ServerCharacterMotor`（move_and_slide 物理模式）+ 专服 collision-only 地牢 + 输入固定 tick 缓冲（30Hz 消费、频率无关） | ✅ 关闭 |
| 基线 P0-2 | 信任客户端 attack_type | `AttackContextFactory` 唯一装配真相，命令白名单拒绝攻击类型字段，射程/冷却/伤害全由权威 loadout 派生 | ✅ 关闭 |
| 基线 P0-3 | 三套攻击冷却 | `AttackCadencePolicy` 单一公式，SessionRoot/PlayerCombatRuntime 共用 | ✅ 关闭 |
| 基线 P0-4 | 法术事务断裂 | `bind_player_entity` + prepare→execute→verify→commit→publish；世界执行失败不扣资源 | ✅ 关闭 |
| 基线 P0-5 | 服务端无施法资格/无装配 | `SpellAccessPolicy` commit 前校验；save_state 恢复 spell_state；房主 spawn 携带存档摘要 | ✅ 关闭 |
| 基线 P0-6 | 库存 UI 旧常量 | `InventoryTransferService`（容量预检+回滚），UI 只提交意图 | ✅ 关闭 |
| 基线 P0-7 | 平台交付未闭环 | `rendering_method.mobile="mobile"` + Windows/Android presets + CI preset 门禁 | ✅ 关闭 |
| 复审 P0-1（1059~1826 持续追踪） | 联机法术统一事务/复制闭环 | 第三轮：ray 单次端口调用（双重扣血根防）、自目标组件缺失→不 commit、movement 同步 `_live_state`、projectile 失败→不 commit、field/summon 事件 outbox + ray port_result 提升 extra_events、effects 摘要入事件 | ✅ 关闭 |
| 复审 P0-2（1059~1826 持续追踪） | 护甲固有部位未校验 | `EquipmentPolicy` 要求 target_name == meta.armor_slot（多部位须声明 armor_slots 数组）；策略层+会话层双层反例 | ✅ 关闭 |

## 2. P1 关闭矩阵（6 关闭 / 3 遗留）

| 编号 | 问题 | 关闭依据 | 状态 |
|---|---|---|---|
| 基线 P1-1 | PlayerContext 迁移未完成，规则层读 `GameState.current_player` | `GameState.resolve_player_node(peer_id)` 统一入口 + NetworkManager 会话解析器注入；enemy（3 处收口 `_resolve_target_player`）、dungeon_runtime（4 处）、extraction_portal、procedural_dungeon、tools×2 全部收口；全仓生产代码零裸读（仅注释保留） | ✅ 关闭 |
| 基线 P1-3 | 流派武器伤害倍率未统一 | `STYLE_META.damage_mult` 对齐 docs/战斗数值体系 §2.5 已决定表（单手1.00/持盾0.80/双手1.35/双持1.00+副手0.60/徒手0.80/远程1.00/法系0.50）+ 契约测试 | ✅ 关闭 |
| 基线 P1-4 | 联机击杀经验/升级权威闭环 | `ProgressionAuthority`（compute_kill_reward/award_kill_experience/apply_level_up_choice/roll_rune_candidates）+ SessionRoot 升级候选/选择意图处理器 + EVT_PROGRESSION_CHANGED；测试 progression_session/authority 全绿 | ✅ 关闭（权威层） |
| 基线 P1-8 / 复审 P1-2 | 性能分档无消费者/两套质量系统 | LightingController 订阅 `quality_tier_changed`（FULL→HIGH/BALANCED→MEDIUM/PERFORMANCE+EMERGENCY→LOW）+ 变档重应用已应用光源（幂等），行为测试覆盖 | ✅ 关闭（光照侧；全量 VisualQualityCoordinator 见遗留③） |
| 复审 P1-3 | 多人领域 current_player 回退（tools） | tools×2 收口 resolve_player_node | ✅ 关闭 |
| 复审 P1-4 | 专服 collision-only 缺端到端门禁 | `dungeon_session_collision_authority_test.gd` 4 项：真实 seed 静态墙体、马达 5 秒不穿墙、单元内自由移动、指纹确定性 | ✅ 关闭 |
| 基线 P1-2 / 复审 P1-1 | 单机/联机两套实体 / 远端可信存档仓 | 正式 Enemy 接入会话实体仓 + 服务器 SaveRepository 属 Phase B/产品层决策 | ⚠️ 部分（阶段 B 遗留） |
| 基线 P1-5 | DungeonSceneBuilder God Object | 未拆分（Phase C） | ⚠️ 遗留 |
| 基线 P1-7 | Player 聚合点 | 未拆分（Phase C） | ⚠️ 遗留 |

## 3. P2 关闭矩阵（7 关闭 / 3 遗留）

| 编号 | 问题 | 关闭依据 | 状态 |
|---|---|---|---|
| 基线 P2-3 / 复审 P2-4 | 文档漂移 | docs/16 C#/Mono/gl_compatibility 标记历史参考 + §6.1 渲染决策更新；docs/24「占位骨架」更新为运行时实现现状；法术审计「施法输入未接线」更新为已接线 | ✅ 关闭（docs/25/README 可后续随阶段 B 再核） |
| 基线 P2-4 / 复审 P2-2 | 源码字符串测试脆弱 | 被点名套件全部行为化：spell_world_executor（fake port 单次调用/outbox/null noop）、spell_network_completion（窗口修正）、enemy_state_moving/enemy_idle/gameplay_light_policy/multiplayer_scene_integration（断言对齐实现） | ✅ 关闭（被点名项；全仓 244 文件非本轮范围） |
| 基线 P2-5 | CI 把 orphan 101 转绿 | run_ci.ps1 新增 `-FailOnOrphan` 严格开关（101→RED）；默认 YELLOW 兼容存量；batched runner 逐套件识别 PASS_ORPHAN；本轮已清零 8 个套件的 orphan（session_root/bridge/command_router/interaction_authority/player_weapon_input 等） | ✅ 关闭 |
| 复审 P2-1 | shader Inspector hints | liquid（酸液色/混合系数/滚动）→ uniform+hints；dungeon_terrain vec2 限制注释；tavern_atlas 13 个 float 补齐 hint_range | ✅ 关闭 |
| 复审 P2-2 | 法术旧字符串测试过时 | 见 P2-4 行 | ✅ 关闭 |
| 复审 P2-3 | load_check 误报成功 | source_code 非空 + can_instantiate 校验，编译失败退出码 1（实测验证） | ✅ 关闭 |
| 复审 P2-3（1059） | 并行报告目录冲突 | `run_all_gdunit_batched.ps1` 逐套件隔离 + `merge_gdunit_results.ps1` 归并已存在（PASS_ORPHAN 分类） | ✅ 关闭（工具侧） |
| 基线 P2-1 | Autoload 面过宽 / Service Locator | 未整改（Phase C/D） | ⚠️ 遗留 |
| 基线 P2-2 | SaveManager 聚合器 | 未整改（Phase C/D） | ⚠️ 遗留 |
| 基线 P2-6 / 复审 P2-4 | 工作树不可审计 | 过程性指引（按领域拆分、禁 git add -A）；本轮与既有 WIP 并存，未提交 | ⚠️ 遗留（提交策略） |

## 4. 验收清单对照（基线 §8）

### 联机
- [x] 客户端持续向墙方向输入，服务端位置不穿墙（server_character_motor + collision_authority 真实 seed + 双进程 mp_dungeon PASS）
- [x] 客户端伪报 ranged 不影响服务器推导的攻击类型和射程（AttackContextFactory 白名单 + 会话级反作弊测试）
- [x] 不同武器/流派在单机和联机得到相同冷却与伤害输入（AttackCadencePolicy + AttackContextFactory 契约测试）
- [x] 法术 caster 缺失/资格不符/世界执行失败时，法力与冷却均不变化（spell_session_atomicity 14/14）
- [ ] 场效果与召唤可被晚加入/重连客户端恢复（阶段 B：outbox 已建立，恢复测试待正式 Enemy 接入）
- [ ] 正式 Enemy AI/碰撞/死亡/掉落真实双进程（阶段 B，当前为字典代理+真实碰撞移动）
- [x] 联机击杀经验只授予正确 player_guid 的 context（ProgressionAuthority + SaveAuthority guid 幂等结算；升级选择仅意图）

### 平台与性能
- [x] Android 使用 Mobile renderer（project.godot mobile）
- [x] Windows/Android presets 可被编辑器识别（CI preset 门禁；实际导出需模板机）
- [x] RenderingProfile/质量分档能实际改变光（变档重应用光源；阴影/粒子/雾/LOD 统一协调器待阶段 C）
- [ ] Android 真机 GPU/热稳定性（需真机）

### 工程
- [x] 审查相关套件 0 assertion failure、0 orphan、退出 0（最终批 21/21；全量剩余失败均为预存 WIP 套件，见第二轮报告 §2）
- [x] 被点名核心测试不再依赖源码子串证明行为（行为化完成）
- [x] docs/16、docs/24、法术审计状态一致（本轮更新；docs/25 与根 README 未核对项随阶段 B）
- [ ] 工作树按主题拆分提交（待执行）

## 5. 遗留汇总（按依赖排序）

1. **阶段 B**：正式 Enemy 实体接入会话实体仓（P1-2/P1-4 验收项）；projectile 命中结算纳入会话权威链（P0-1-B 完整形态）；场/召唤重连恢复测试。
2. **产品决策**：P1-1 服务器 SaveRepository（账号体系/存档位置）。
3. **阶段 C**：DungeonSceneBuilder/TavernEquipmentPanel/Player/SessionRoot God Object 拆分；VisualQualityCoordinator（阴影/粒子/雾/FX/LOD 统一变档事务）；Autoload 收敛；SaveManager 聚合器。
4. **工程**：按领域拆分提交；Windows/Android 实际导出 + Android 真机验收；docs/25 与根 README_ARCHITECTURE 状态核对。
5. **预存 WIP 套件**（~30 个，模型/地牢/敌人/渲染）：随各自功能提交收尾，不在架构整改范围内。

## 6. 本轮（核对轮）变更

- `run_ci.ps1`：orphan 101 默认 YELLOW + `-FailOnOrphan` 严格开关（P2-5）。
- `docs/24-联机架构迁移.md`：`globals/multiplayer/` 状态从「注释骨架」更新为「运行时实现现状」。
- `docs/法术实现审计与交付概览.md`：「施法输入未接线」「屏障运行时未接线」更新为已接线现状（4+1 处）。
- 其余条目均为前两轮整改成果复核（附报告引用），未重复修改。
