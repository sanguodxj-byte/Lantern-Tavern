# 武器挥舞动画（第一人称层 + 世界层）

## 两层动画（关键架构）
- **第一人称 ViewModel 动作层**（`ViewModelAnimator` + `view_model_animation_library.tres`）
  只动玩家自己看到的 `ActionPivot` 旋转/位移。由 `arm_animation_enabled` 开关控制——**当前默认 false（上一轮需求关闭手臂动画），此层不播放，第一人称武器恒静态**。开启后由 `sample_action(action, progress)` 按挥砍进度 0→1 逐帧采样。
- **世界层武器弧线**（`CombatSlashAnimator.apply_weapon_arc`）
  作用于世界中真实武器占位网格（敌人/友军所见、决定命中方向与刀光）。由战斗状态 `player_state_slashing` 驱动，**不受第一人称开关影响，始终生效**。

## 第一人称动作（按 `resolve_melee_action()` 的武器 profile 解析）
| profile | 动画 | 时长 | 运动类型 |
|---|---|---|---|
| dagger | `vm_stab_dagger` | 0.28s | 位移前刺 z -0.22 |
| spear | `vm_thrust_spear` | 0.52s | 位移长矛前刺 z -0.42 |
| heavy (two_hand) | `vm_slash_heavy` | 0.78s | 旋转：举过头俯砍 pitch +38°→-49° |
| 其余 | `vm_slash_one_hand` | 0.46s | 旋转：斜向挥砍 |

### vm_slash_one_hand 关键帧（ActionPivot 旋转，弧度，顺序 XYZ=pitch/yaw/roll）
- 0%   (0, 0, 0)            静止
- 20%  (0.18, -0.36, -0.48) 蓄力：上抬(+10°)·左偏(-21°)·左倾(-28°)
- 50%  (-0.22, 0.42, 0.44)  挥击：下劈(-13°)·右扫(+24°)·右倾(+25°)
- 100% (0, 0, 0)            收回静止
→ 视觉：武器从左上往右下斜劈（对角挥砍）。

### vm_slash_heavy 关键帧
- 0%   (0,0,0)
- 28%  (0.66, -0.18, -0.24) 高举过头(+38°)
- 55%  (-0.86, 0.18, 0.16)  大力下劈(-49°)
- 100% (0,0,0)
→ 视觉：从上往下的重型劈砍。

## 世界层弧线（始终生效）
- 蓄力 0–28%：roll/yaw 由 0 插值到 `-ARC`（roll -24°≈-0.42rad，yaw -14°≈-0.24rad），武器后撤到身体左侧。
- 挥击（命中窗口）28–78%：roll/yaw 由 -ARC 扫到 +ARC（横跨到右侧）；前向位移 `z = -sin(progress·π)·0.08` 中段轻微前推。
- 收招 78–100%：roll/yaw 由 +ARC 回 0。
- **刀光（SlashTrail）**：加色发光橙 quad，命中窗口内出现，alpha 在挥击中点(50%)达峰 0.34（TRAIL_MAX_ALPHA），随 sin 曲线淡入淡出。

## 时间
- 挥砍总时长约 400ms（`slash_duration_msec` 默认）。
- 世界动画 `slash_one_hand` 长度 0.46s / 速度 1.12 ≈ 411ms。
- 命中活跃段 28%–78% ≈ 115–321ms。

## 源码位置
- 第一人称：`scenes/characters/player/view_model.gd`（sample_action/play_action/stop_action + arm_animation_enabled）、`view_model_animator.gd`、`view_model_animation_library.tres`
- 世界层：`globals/combat/combat_slash_animator.gd`、`scenes/characters/player/state/player_state_slashing.gd`
