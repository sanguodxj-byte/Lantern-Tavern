# 武器挥舞动画（第一人称层 + 世界层）

## 两层动画（关键架构）
- **第一人称 ViewModel 动作层**（`ViewModelAnimator` + `first_person_animation_library.gd`）
  只动第一人称自己的 `ActionPivot`、武器/盾牌副本和手臂骨架。由状态机按 `vm_*` 动作驱动，
  `first_person_arm_animator.gd` 同步采样手臂骨骼；它不写第三人称玩家骨骼，也不参与命中判定。
- **世界层武器弧线**（`CombatSlashAnimator.apply_weapon_arc`）
  作用于第三人称世界中真实武器占位网格（敌人/友军所见、决定命中方向与刀光）。由战斗状态
  `player_state_slashing` 驱动，第三人称 `AnimationPlayer` 仍负责状态退出信号。

## 第一人称动作（按 `resolve_melee_action()` 的武器 profile 解析）
| profile | 动画 | 时长 | 运动类型 |
|---|---|---|---|
| dagger | `vm_stab_dagger` | 0.28s | 位移前刺 z -0.22 |
| spear | `vm_thrust_spear` | 0.52s | 位移长矛前刺 z -0.42 |
| greatsword / axe / warhammer / spear | `vm_<style>_heavy_swing` | style-specific | 双手武器被动重型挥舞 |
| 其余流派 | `vm_<style>_attack` | style-specific | 各流派独立的攻击轨迹 |

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
- 第一人称：`scenes/characters/player/view_model.gd`、`view_model_animator.gd`、
  `first_person_animation_library.gd`、`first_person_arm_animator.gd`
- 世界层：`globals/combat/combat_slash_animator.gd`、`scenes/characters/player/state/player_state_slashing.gd`
