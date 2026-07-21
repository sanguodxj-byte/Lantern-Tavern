# 第一人称体素武器动画优化任务

> 状态：待实施  
> 优先级：P1  
> 目标版本：下一轮战斗手感迭代  
> 视觉方向：Minecraft 的清晰构图与夸张反馈 + Barony 的武器重量和类型差异  
> 适用范围：本地玩家第一人称 ViewModel，不替代第三人称骨骼动画

## 1. 目标

将当前由 `view_model.gd` 大段插值和 Tween 直接控制 `WeaponHolder.transform` 的方案，升级为可在 Godot 编辑器中预览、可按武器类型复用、与战斗判定严格同步的分层第一人称动画系统。

完成后应满足：

- 策划或美术可在 Godot `AnimationPlayer` 时间轴中编辑挥剑、突刺、重劈、拉弓、射击和装填动作。
- 第一人称动作具有 Minecraft 式清晰轮廓、快速出招和稳定屏幕构图。
- 轻重武器具有 Barony 式前摇、冲量、回弹和收招差异。
- 动画表现与伤害窗口解耦。状态机和 `CombatSlashAnimator` 仍是战斗时序的唯一真相源。
- 移动摇摆、瞄准、攻击、后坐力分别作用于不同节点，禁止多个系统同时改写同一个 Transform。
- 第一人称动画仅为本地视觉表现，不进入联机快照，也不改变服务端伤害判定。
- 保留现有第三人称 `_rig.glb`、`AnimationPlayer`、`BoneAttachment3D` 和武器弧线流程。

## 2. 非目标

本任务第一轮不包含：

- 不制作完整第一人称手臂骨架。
- 不重新生成或批量修改任何体素武器 GLB。
- 不修改酒馆场景、酒馆材质或任何烘焙流程。
- 不用第一人称动画事件直接造成伤害或生成投射物。
- 不引入 `AnimationTree`。当前动作互斥且层级可拆分，`AnimationPlayer` 足够，复杂状态图会增加维护成本。
- 不同步 ViewModel Transform 到其他客户端；其他玩家继续观看第三人称角色动画。
- 不在第一轮实现双持、检查武器、复杂连击树或程序化 IK。

## 3. 当前实现与问题

### 3.1 当前数据流

```text
输入 / PlayerState
  ├── PlayerStateSlashing
  │     ├── 播放第三人称 character/AnimationPlayer
  │     ├── CombatSlashAnimator 计算进度和命中窗口
  │     └── ViewModel.apply_slash_arc(progress)
  ├── PlayerStateAttackPreparing
  │     ├── ViewModel.apply_melee_charge(progress)
  │     └── ViewModel.apply_bow_pull(progress)
  └── PlayerStateShooting
        ├── 生成投射物
        └── ViewModel.apply_recoil()
```

相关文件：

| 文件 | 当前职责 |
|---|---|
| `scenes/characters/player/view_model.tscn` | 仅包含 `WeaponHolder` 和 `MuzzlePoint` |
| `scenes/characters/player/view_model.gd` | 持握、瞄准、挥砍、拉弓、后坐力全部混在一个脚本中 |
| `scenes/characters/player/state/player_state_slashing.gd` | 计算归一化挥砍进度并驱动命中 |
| `scenes/characters/player/state/player_state_attack_preparing.gd` | 驱动近战蓄力和拉弓进度 |
| `scenes/characters/player/state/player_state_shooting.gd` | 生成投射物并触发后坐力 |
| `globals/combat/combat_slash_animator.gd` | 武器动作分类、时长、命中窗口和第三人称武器弧线 |
| `tests/gdunit/view_model_test.gd` | 第一人称 ViewModel 基础与集成测试 |

### 3.2 主要问题

1. `WeaponHolder` 同时承载持握、瞄准、蓄力、挥砍和后坐力，Tween 与逐帧 Transform 写入可能互相覆盖。
2. 动作关键姿态硬编码在 GDScript 中，无法在编辑器时间轴直观预览。
3. `apply_slash_arc()` 随武器类型继续增长后会形成难维护的大型 `match`。
4. 动画表现参数和战斗参数混在一起，调视觉幅度时容易误触命中窗口。
5. 当前射击使用通用第三人称 `throw_weapon`/`slash`，第一人称只有后坐力，缺少独立的弓释放、弩发射和弩装填表现。
6. 缺少固定的动作命名、轨道所有权和回退规则，新武器接入容易产生不一致。
7. 缺少用于快速预览所有武器动作的独立场景，调一个动作需要进入完整游戏流程。

## 4. 推荐架构

### 4.1 节点分层

将 `view_model.tscn` 调整为以下稳定层级：

```text
ViewModel
├── BobPivot                    # 呼吸、走路起伏、镜头惯性
│   └── AimPivot                # 默认持握与瞄准位置混合
│       └── ActionPivot         # 挥砍、突刺、格挡、射击、装填
│           └── WeaponSocket    # 武器类型/模型安装修正
│               ├── WeaponModel # 运行时实例化的 GLB
│               └── MuzzlePoint # 投射物起点，随全部上层动作移动
└── AnimationPlayer             # 只允许写 ActionPivot
```

轨道所有权必须固定：

| 节点 | 唯一写入者 | 允许内容 |
|---|---|---|
| `BobPivot` | ViewModel sway/bob 代码 | 呼吸、移动起伏、转向滞后、落地冲击 |
| `AimPivot` | ViewModel aiming 代码 | hip/aim 位置与旋转混合 |
| `ActionPivot` | `AnimationPlayer` | 攻击、格挡、装备、射击、装填 |
| `WeaponSocket` | 武器姿态配置 | 不同模型的安装位置、旋转、缩放 |
| `WeaponModel` | 资源实例化逻辑 | 模型与少量纯视觉形变，不写全局动作 |

禁止 `Tween`、`_physics_process()` 和 `AnimationPlayer` 同时写同一个节点的 `transform`。

### 4.2 动画驱动策略

采用“时间轴创作、状态机采样”的混合方案：

- `AnimationPlayer` 保存并预览关键帧。
- 近战和拉弓不依赖 `animation_finished` 决定伤害。
- 状态机继续计算 `0.0 .. 1.0` 的权威进度。
- ViewModel 根据进度对目标动画执行 `seek(progress * animation_length, true)`。
- 命中窗口继续使用 `CombatSlashAnimator.PLAYER_HIT_START/END`。
- 射击和装填等已经由状态机明确触发的一次性表现可正常 `play()`，但投射物生成仍由 `PlayerStateShooting` 执行。

推荐接口：

```gdscript
func sample_action(action_name: StringName, normalized_progress: float) -> void
func play_action(action_name: StringName, custom_speed: float = 1.0) -> void
func stop_action(reset_pose: bool = true) -> void
func set_aim_weight(weight: float) -> void
func set_weapon_profile(profile_id: StringName) -> void
func get_muzzle_global_transform() -> Transform3D
```

`sample_action()` 的行为约束：

1. 将进度 clamp 到 `0.0 .. 1.0`。
2. 动画不存在时使用动作族回退动画。
3. 切换动作名时先播放并立即暂停目标动画。
4. 使用 `seek()` 采样，不让 AnimationPlayer 自己推进近战时间。
5. 进度达到 `1.0` 或状态退出时恢复 `ActionPivot` 的单位 Transform。

### 4.3 职责边界

```text
PlayerState / CombatSlashAnimator
  负责：输入、状态转换、冷却、蓄力、攻击总时长、命中窗口、伤害

ViewModelAnimator
  负责：动画名解析、时间轴采样、回退、姿态复位、局部视觉反馈

ViewModel
  负责：武器模型实例化、渲染层、瞄准、Bob/Sway、枪口查询

AnimationLibrary
  负责：ActionPivot 的关键帧内容

第三人称 AnimationPlayer
  负责：其他玩家可见的身体和手臂动作
```

## 5. 动画规格

### 5.1 第一轮必需动画

| 动画名 | 动作族 | 目标武器 | 建议总时长 | 回退 |
|---|---|---|---:|---|
| `vm_idle` | 基础 | 全部 | 1.00s 循环 | 单位姿态 |
| `vm_equip` | 基础 | 全部 | 0.25s | 直接显示 |
| `vm_slash_one_hand` | 近战 | 单手剑、单手斧、钉锤 | 0.46s | `vm_slash_default` |
| `vm_slash_heavy` | 近战 | 双手剑、战锤、双手斧 | 0.78s | `vm_slash_default` |
| `vm_stab_dagger` | 近战 | 匕首 | 0.28s | `vm_stab_default` |
| `vm_thrust_spear` | 近战 | 长矛 | 0.52s | `vm_stab_default` |
| `vm_slash_default` | 近战 | 未分类近战 | 0.45s | 单位姿态 |
| `vm_stab_default` | 近战 | 未分类刺击 | 0.40s | `vm_slash_default` |
| `vm_melee_charge` | 蓄力 | 可蓄力近战 | 1.00s 采样 | 保持默认姿态 |
| `vm_bow_draw` | 远程 | 长弓 | 1.00s 采样 | 保持瞄准姿态 |
| `vm_bow_release` | 远程 | 长弓 | 0.24s | 通用 recoil |
| `vm_crossbow_fire` | 远程 | 弩 | 0.24s | 通用 recoil |
| `vm_crossbow_reload` | 远程 | 弩 | 1.20s | 保持低位 |
| `vm_wand_cast` | 法术 | 法杖 | 0.38s | `vm_crossbow_fire` |

盾牌目前被 `ViewModel.set_weapon()` 排除，`vm_bash_shield` 留到独立副手 ViewModel 任务，不在第一轮伪造不可见动作。

### 5.2 动作节奏

| 武器 | 前摇 | 主动挥击 | 收招 | 风格重点 |
|---|---:|---:|---:|---|
| 匕首 | 0.08s | 0.06s | 0.14s | 小幅回收、极速直刺、轻微手腕翻转 |
| 单手剑 | 0.14s | 0.10s | 0.22s | 大轮廓横斩、命中位置清晰、短回弹 |
| 长矛 | 0.18s | 0.09s | 0.25s | 明显后收、沿屏幕中心直线前冲 |
| 双手重武器 | 0.28s | 0.12s | 0.38s | 高举、快速下砸、长回正和过冲 |
| 长弓释放 | 0.00s | 0.08s | 0.16s | 瞬间前弹、手臂缓冲、弹性回位 |
| 弩射击 | 0.00s | 0.06s | 0.18s | 短促后坐、轻微上抬、稳定复位 |

节奏原则：

- 待机时武器稳定占据右下区域，不持续遮挡准心。
- 起手姿态要比写实动作更大，确保低分辨率体素轮廓可读。
- 主动挥击段应明显快于前摇和收招。
- 轻武器以位置变化为主，重武器增加旋转、下沉和回正过冲。
- 不给每次动作叠加强烈镜头摇晃。镜头反馈低于武器反馈，避免晕动。
- 不缩放武器制造打击感，除非是明确的风格化特效；默认保持 `Vector3.ONE`。

### 5.3 推荐姿态关键点

动画统一按归一化时间制作，便于状态机采样：

```text
0.00  默认姿态
0.20  起手峰值
0.28  命中窗口开始
0.50  主要接触姿态
0.78  命中窗口结束
0.90  回弹/过冲
1.00  单位姿态
```

具体动画可以改变起手和收招观感，但第一轮仍应让主要挥击落入现有 `0.28 .. 0.78` 命中窗口。未来若要为每类武器设置不同命中窗口，应先把窗口升级为战斗规格数据，不能只改动画关键帧。

### 5.4 武器动作分类

第一轮继续从 `WeaponData.weapon_class`、`item_tag` 和 `tags` 推导动作类型，不要求修改 `weapons.json`：

| 条件 | ViewModel profile | 近战/远程动画 |
|---|---|---|
| `tags` 含 `dagger` | `dagger` | `vm_stab_dagger` |
| `tags` 或 class 含 `spear` | `spear` | `vm_thrust_spear` |
| `weapon_class == two_hand` | `heavy` | `vm_slash_heavy` |
| `weapon_class == longbow` 或 bow tag | `bow` | `vm_bow_draw` / `vm_bow_release` |
| `weapon_class == crossbow` 或 crossbow tag | `crossbow` | `vm_crossbow_fire` / `vm_crossbow_reload` |
| `weapon_class == wand` | `wand` | `vm_wand_cast` |
| 其他近战 | `one_hand` | `vm_slash_one_hand` |

当一件武器确实需要独特动作时，再在 `weapons.json` 增加明确的视觉 profile 字段，并同步更新 `WeaponData`、数据完整性测试和管线导入逻辑；不得通过武器显示名做字符串猜测。

## 6. 实施步骤

### 阶段 0：建立回归基线

- [ ] 运行 `tests/gdunit/view_model_test.gd`、`combat_feel_test.gd`、`crossbow_behavior_test.gd`、`crosshair_aim_test.gd`。
- [ ] 记录单手剑、双手武器、匕首、长矛、长弓、弩的现有第一人称截图或短视频。
- [ ] 确认现有伤害窗口、弩装填时间和投射物出生位置，作为行为基线。
- [ ] 新建 `tests/gdunit/view_model_animator_test.gd`，先写失败测试覆盖目标接口和回退行为。

完成条件：现有测试结果和六类武器视觉基线均已保存，新增测试处于预期失败状态。

### 阶段 1：只做节点分层，不改变动作外观

- [ ] 在 `view_model.tscn` 中添加 `BobPivot/AimPivot/ActionPivot/WeaponSocket`。
- [ ] 将 `MuzzlePoint` 移至 `WeaponSocket` 下，保持相同局部前向偏移。
- [ ] 修改 `view_model.gd`，让运行时武器模型添加到 `WeaponSocket`。
- [ ] 将原基础持握 Transform 从旧 `WeaponHolder` 转移到 `AimPivot`。
- [ ] 临时把现有程序化挥砍结果写入 `ActionPivot`，确保重构前后视觉近似。
- [ ] 所有 `get_muzzle_global_position()` 调用改从新层级读取；优先新增 `get_muzzle_global_transform()`，旧方法暂时保留兼容。

必须新增或更新测试：

- [ ] 场景包含完整稳定层级。
- [ ] 武器模型实例化到 `WeaponSocket`。
- [ ] 枪口位于武器前方且跟随 `ActionPivot`。
- [ ] 瞄准只改变 `AimPivot`，不改变 `ActionPivot`。
- [ ] `restore_transform()` 后所有动作层回到单位 Transform。

完成条件：行为测试全部通过，游戏内六类武器与基线相比没有明显位置跳变，投射物仍从正确枪口发出。

### 阶段 2：引入 ViewModelAnimator 和 AnimationLibrary

- [ ] 新建 `scenes/characters/player/view_model_animator.gd`，只负责动作选择、采样、播放、回退和复位。
- [ ] 在 `view_model.tscn` 添加 `AnimationPlayer`。
- [ ] 新建独立 `AnimationLibrary` 资源，避免把大量关键帧直接堆入主场景文本。
- [ ] 先制作 `vm_slash_default`、`vm_crossbow_fire` 和单位姿态三个最小动画。
- [ ] `AnimationPlayer` 轨道只允许指向 `ActionPivot`，不得写 `AimPivot`、摄像机或动态 `WeaponModel` 路径。
- [ ] 实现 `sample_action()`：clamp、动画查找、回退、暂停、seek、复位。
- [ ] 实现 `play_action()`：用于释放、装填、装备等一次性视觉动作。
- [ ] 将缺失动画降级为无动作或通用动作并只警告一次，禁止因视觉资源缺失阻断攻击。

必须新增测试：

- [ ] `sample_action()` 在 `0.0`、`0.5`、`1.0` 能得到预期姿态。
- [ ] 越界进度会 clamp。
- [ ] 未知动画使用正确回退且不报错。
- [ ] 动画停止后 `ActionPivot` 恢复单位 Transform。
- [ ] AnimationLibrary 包含所有第一轮必需动画名。
- [ ] 所有动画轨道只写允许的节点路径。

完成条件：默认挥砍和弩后坐力已由 AnimationPlayer 表现，伤害与发射逻辑完全未迁移到动画事件。

### 阶段 3：迁移近战动画

- [ ] 按规格制作 `vm_slash_one_hand`。
- [ ] 制作 `vm_slash_heavy`，突出高举、下砸、沉降和长收招。
- [ ] 制作 `vm_stab_dagger`，保持短促且不大幅遮挡屏幕。
- [ ] 制作 `vm_thrust_spear`，限制横向摆动，强化 Z 轴前冲。
- [ ] 制作 `vm_melee_charge`，由蓄力比例采样。
- [ ] 把 `_get_melee_type()` 迁移为统一的 profile/animation resolver，避免 ViewModel 与 `CombatSlashAnimator` 各自维护不同映射。
- [ ] `PlayerStateSlashing` 继续提供当前 `slash_progress`，改为调用 `sample_action(resolved_animation, slash_progress)`。
- [ ] 状态退出、受伤中断、死亡和切换武器时都必须复位动作层。
- [ ] 移除已被时间轴替代的硬编码近战姿态，但在所有迁移和测试完成前保留兼容回退路径。

必须新增测试：

- [ ] 每种 `weapon_class/tags` 解析到正确动画。
- [ ] null、未知 class 和不完整 tags 回退到默认挥砍。
- [ ] 动画中断后不会残留旋转或位置偏移。
- [ ] 近战进度仍来自 `CombatSlashAnimator.progress()`。
- [ ] 命中窗口仍由 `is_player_hit_active()` 控制，不读取动画事件。

完成条件：四类近战武器具有明显不同轮廓，所有现有伤害、耐久、音效和冷却测试通过。

### 阶段 4：迁移远程动画

- [ ] 将长弓拉弓迁移为 `vm_bow_draw` 采样动画。
- [ ] 保留满弓轻微颤动和呼吸漂移，但把它放到 `BobPivot` 的小幅 additive offset，不写 `ActionPivot`。
- [ ] 使用 `vm_bow_release` 替代长弓硬编码 Tween。
- [ ] 使用 `vm_crossbow_fire` 替代弩硬编码 Tween。
- [ ] 增加 `vm_crossbow_reload`，时长与当前约 `1.2s` 的装填规则一致。
- [ ] 让弩装填状态触发动画，但“装填完成”仍由现有冷却/状态逻辑决定。
- [ ] 投射物生成仍发生在 `PlayerStateShooting._fire_projectile()`，不能迁入 call method track。
- [ ] 检查动画全过程中 `MuzzlePoint` 朝向和出生位置，避免箭矢从镜头或手部生成。

必须新增测试：

- [ ] 拉弓 `0.0/0.5/1.0` 姿态单调推进且可逆采样。
- [ ] 发射只生成一个投射物，视觉动画不得重复调用服务。
- [ ] 长弓与弩解析到不同释放动画。
- [ ] 弩装填动画缺失不会改变装填冷却规则。
- [ ] 右键持续按住时射击后仍返回瞄准状态。

完成条件：长弓和弩具有不同射击反馈，发射方向、装填限制、耐久与瞄准行为无回归。

### 阶段 5：加入 Bob、Sway 和轻量命中反馈

- [ ] 在 `BobPivot` 实现低幅度呼吸，静止时不可喧宾夺主。
- [ ] 根据本地移动速度实现步行起伏，空中不播放地面步频。
- [ ] 根据摄像机角速度实现有限的转向滞后，并设置最大位移/旋转钳制。
- [ ] 瞄准时把 Bob/Sway 强度降低到 hip 状态的 20% 至 35%。
- [ ] 在确认命中后允许 `30ms .. 50ms` 的 ViewModel 动作停顿或减速。
- [ ] 命中停顿仅影响本地 `ActionPivot` 动画采样，不暂停 SceneTree、不延迟服务器伤害、不冻结敌人。
- [ ] 添加低幅度摄像机冲量接口；默认关闭或限制在约 `0.5° .. 1.5°`。
- [ ] 在设置菜单预留“第一人称武器摇摆强度”和“镜头冲击强度”，至少支持关闭镜头冲击。

必须新增测试：

- [ ] Bob 只写 `BobPivot`。
- [ ] Aim 只写 `AimPivot`。
- [ ] 瞄准状态正确降低摇摆强度。
- [ ] 所有 sway 输出受最大幅度限制。
- [ ] 命中停顿不修改 `Engine.time_scale`、`SceneTree.paused` 或联机状态。

完成条件：移动和攻击叠加时无 Transform 抢写、抽动或永久偏移，低强度设置下不会造成明显晕动。

### 阶段 6：编辑器预览与制作工作流

- [ ] 新建 `scenes/debug/view_model_animation_preview.tscn`。
- [ ] 预览场景支持从 `WeaponRegistry` 选择武器并实例化真实 GLB。
- [ ] 支持动作下拉选择、播放/暂停、归一化进度滑条、hip/aim 切换。
- [ ] 显示 `MuzzlePoint` 调试标记、当前 profile、动画名和回退状态。
- [ ] 添加固定 FOV 与 16:9、16:10、4:3 安全框检查。
- [ ] 预览工具不得写入 `weapons.json`，也不得修改或重新导出 GLB。
- [ ] 在 `docs/18-体素骨骼动画工作流.md` 增补“第一人称 ViewModel 动画”章节，明确它与第三人称骨骼动画是两套资源。

必须新增测试：

- [ ] 预览场景可实例化。
- [ ] 武器切换后旧模型正确释放。
- [ ] 所有 Registry 武器至少能解析到一个合法 profile。
- [ ] 预览工具不包含写入武器数据或资产的代码路径。

完成条件：无需进入完整地牢即可查看全部第一人称动作，并能在 Godot 时间轴中编辑和立即预览。

### 阶段 7：清理旧实现

- [ ] 删除已被替代的 `apply_slash_arc()` 分支和 recoil Tween。
- [ ] 删除不再使用的 Transform 常量和重复武器分类逻辑。
- [ ] 保留必要的兼容方法一轮版本，并加弃用注释；调用点迁移完成后再删除。
- [ ] 更新 `view_model_test.gd`，避免只通过搜索源码字符串来验证行为，优先断言节点和运行结果。
- [ ] 运行第一人称相关测试、全量 gdUnit4 和联机集成测试。
- [ ] 在桌面与常用分辨率进行人工验收并保存最终对比截图。

完成条件：生产路径只剩一套第一人称动作驱动，旧代码不再被状态机调用，全量测试通过。

## 7. 预计文件变更

| 文件 | 操作 | 内容 |
|---|---|---|
| `scenes/characters/player/view_model.tscn` | 修改 | 分层 Pivot、AnimationPlayer、外部 AnimationLibrary |
| `scenes/characters/player/view_model.gd` | 修改 | 模型、瞄准、Bob/Sway、枪口与 animator 协作 |
| `scenes/characters/player/view_model_animator.gd` | 新增 | 动画采样、播放、回退、复位 |
| `scenes/characters/player/view_model_animation_library.tres` | 新增 | 第一人称动作关键帧 |
| `scenes/characters/player/state/player_state_slashing.gd` | 修改 | 从硬编码弧线切换为归一化动画采样 |
| `scenes/characters/player/state/player_state_attack_preparing.gd` | 修改 | 近战蓄力与拉弓采样 |
| `scenes/characters/player/state/player_state_shooting.gd` | 修改 | 触发弓/弩释放表现，不改变投射物职责 |
| `globals/combat/combat_slash_animator.gd` | 小幅修改 | 统一或暴露动作 profile 映射，继续持有战斗时序 |
| `scenes/debug/view_model_animation_preview.tscn` | 新增 | 动画制作与检查工具 |
| `scenes/debug/view_model_animation_preview.gd` | 新增 | 武器/动画选择和预览控制 |
| `tests/gdunit/view_model_test.gd` | 修改 | 新层级、枪口、瞄准、兼容集成 |
| `tests/gdunit/view_model_animator_test.gd` | 新增 | 采样、回退、复位、轨道所有权 |
| `tests/gdunit/view_model_preview_test.gd` | 新增 | 预览场景和 Registry 覆盖 |
| `tests/gdunit/combat_feel_test.gd` | 修改 | 保证伤害窗口仍由战斗时序控制 |
| `tests/gdunit/crossbow_behavior_test.gd` | 修改 | 射击/装填动画与规则解耦 |
| `docs/18-体素骨骼动画工作流.md` | 修改 | 增补第一人称制作工作流 |

每个新增或修改的代码文件必须按项目规则提供对应 gdUnit4 测试。AnimationLibrary 和场景资源也必须有资源存在性、动画名、轨道路径和可实例化测试。

## 8. 测试计划

### 8.1 单元测试重点

1. 节点层级和轨道所有权。
2. 武器数据到 profile/动画名的确定性映射。
3. 动画采样、边界 clamp、缺失动画回退。
4. 动作完成、中断、换武器和节点释放后的姿态复位。
5. Aim、Bob、Action 不互相改写 Transform。
6. `MuzzlePoint` 跟随最终姿态且返回有效世界 Transform。
7. 动画缺失不阻断攻击、投射物或装填规则。
8. 命中窗口不依赖 AnimationPlayer callback。

### 8.2 建议测试命令

```bash
"D:/123/Godot_v4.7-stable_mono_win64.exe" --headless -s tests/gdunit4_runner.gd -- --ignoreHeadlessMode -a tests/gdunit/view_model_test.gd

"D:/123/Godot_v4.7-stable_mono_win64.exe" --headless -s tests/gdunit4_runner.gd -- --ignoreHeadlessMode -a tests/gdunit/view_model_animator_test.gd

"D:/123/Godot_v4.7-stable_mono_win64.exe" --headless -s tests/gdunit4_runner.gd -- --ignoreHeadlessMode -a tests/gdunit/combat_feel_test.gd

"D:/123/Godot_v4.7-stable_mono_win64.exe" --headless -s tests/gdunit4_runner.gd -- --ignoreHeadlessMode -a tests/gdunit/crossbow_behavior_test.gd

"D:/123/Godot_v4.7-stable_mono_win64.exe" --headless -s tests/gdunit4_runner.gd -- --ignoreHeadlessMode -a tests/gdunit/
```

### 8.3 人工验收矩阵

每类武器至少检查以下组合：

| 武器 | hip 攻击 | aim/蓄力 | 移动中 | 靠墙 | 连续输入 | 中断恢复 | 枪口 |
|---|---|---|---|---|---|---|---|
| 单手剑 | 必测 | 蓄力 | 必测 | 必测 | 必测 | 必测 | 不适用 |
| 双手重武器 | 必测 | 蓄力 | 必测 | 必测 | 必测 | 必测 | 不适用 |
| 匕首 | 必测 | 蓄力 | 必测 | 必测 | 必测 | 必测 | 不适用 |
| 长矛 | 必测 | 蓄力 | 必测 | 必测 | 必测 | 必测 | 不适用 |
| 长弓 | 释放 | 必测 | 必测 | 必测 | 必测 | 必测 | 必测 |
| 弩 | 发射/装填 | 必测 | 必测 | 必测 | 必测 | 必测 | 必测 |
| 法杖 | 施法 | 必测 | 必测 | 必测 | 必测 | 必测 | 必测 |

建议分辨率：`1920x1080`、`2560x1440`、`1280x1024`。同时检查 70、90、110 三档 FOV，武器不得长期遮挡准心或超出视口到只剩不可辨认的局部。

## 9. 性能与联机约束

- 每帧最多更新少量 Node3D Transform，不在 `_process()` 中创建 Tween、Animation 或临时资源。
- 动画名使用 `StringName`，profile 映射在装备切换时解析并缓存，不在每帧重复扫描 tags。
- Bob/Sway 使用已有速度和摄像机变化量，不增加物理查询。
- 第一人称模型继续使用渲染层 1；第三人称本地角色继续使用现有隔离层。
- ViewModel 不加入 `SnapshotReplicator`，不生成网络命令。
- 服务端和远端客户端不需要实例化本地第一人称反馈逻辑。
- 动画资源缺失只降级视觉，不允许改变命中、冷却、装填或伤害结果。

## 10. 风险与规避

| 风险 | 后果 | 规避措施 |
|---|---|---|
| 多层 Transform 同时写入 | 抽动、跳位、无法复位 | 固定轨道所有权并用测试扫描动画轨道 |
| 动画时长与战斗时长不一致 | 视觉命中和实际命中错位 | 近战始终由归一化进度 `seek()` 采样 |
| 动态武器节点路径变化 | AnimationPlayer 轨道失效 | 只动画稳定的 `ActionPivot`，不动画 WeaponModel 子节点 |
| 换武器时旧动画仍在播放 | 新武器继承旧姿态 | 换武器前停止动画并复位所有 Pivot |
| 拉弓颤动覆盖关键帧 | 武器抖动或姿态漂移 | 颤动只写 BobPivot，ActionPivot 只由动画采样 |
| 命中停顿冻结全局 | 联机和物理异常 | 只冻结/延迟本地视觉采样，禁止改全局 time scale |
| 体素武器尺寸差异 | 同一动作穿过镜头或出框 | WeaponSocket profile 保存安装修正，预览场景逐类验收 |
| 测试只检查源码字符串 | 重构后误报或漏报 | 优先实例化场景并断言实际节点、动画和 Transform |

## 11. 完整验收标准

- [ ] 第一人称动作可以在 Godot `AnimationPlayer` 中打开、编辑和预览。
- [ ] 单手、重武器、匕首、长矛、长弓、弩和法杖具有可辨识的独立动作。
- [ ] 第一人称与第三人称动画互不依赖，但由同一个玩家状态同步触发。
- [ ] 伤害、投射物、冷却和装填逻辑不依赖动画回调。
- [ ] hip、aim、移动摇摆和攻击叠加时没有 Transform 抢写。
- [ ] 动作完成、中断、死亡、换武器后均能恢复正确姿态。
- [ ] 枪口随最终动画姿态移动，箭矢/弩箭从武器前端射出并朝向准心。
- [ ] 在目标分辨率和 FOV 下，武器不遮挡准心、不严重裁切、不穿过摄像机。
- [ ] 第一人称动画不进入网络同步路径，不影响服务端权威结果。
- [ ] 所有新增和修改代码均有 gdUnit4 测试，相关测试和全量测试通过。
- [ ] `docs/18-体素骨骼动画工作流.md` 已记录最终制作方法和命名规范。

## 12. 推荐提交拆分

为降低回归范围，按以下顺序分提交，不把全部改造塞进一次变更：

1. `viewmodel: add layered pivot hierarchy`
2. `viewmodel: add animator and animation library`
3. `viewmodel: migrate melee actions to sampled animations`
4. `viewmodel: migrate bow and crossbow actions`
5. `viewmodel: add bob sway and local hit feedback`
6. `tools: add view model animation preview scene`
7. `docs: document first person animation workflow`

每个提交必须同时包含对应测试，并在进入下一阶段前保持相关测试通过。
