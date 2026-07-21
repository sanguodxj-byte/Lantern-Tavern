# 第一人称武器 / 盾牌持有姿态（现状）

基于 `scenes/characters/player/view_model.gd`、`.tscn`、`view_model_animator.gd` 的源码分析。

## 节点层级（挂在 MainCamera 下）

```
ViewModel (Node3D)
└─ BobPivot            每帧 y = sin(t*1.7) · ±0.004 · sway · aimDamp   ← 唯一持续运动
   ├─ ShieldSocket     盾牌挂点（左手侧固定位姿）
   └─ AimPivot         base = view↔aim 插值，由 _aim_weight 控制
      └─ ActionPivot   IDENTITY —— 手臂动画关闭后恒为静止
         └─ WeaponSocket   武器网格挂点
            └─ MuzzlePoint 枪口前推 z = -0.6
```

## 持握位姿（相机视图空间，单位 米 / 度）

### 非瞄准（默认 hip-fire）
- 武器（one_hand / 短剑）：pos `(0.22, -0.26, -0.45)`  rot `(12°, 4°, -4°)` → 屏幕右下、略低、前方
- 盾牌：pos `(-0.30, -0.22, -0.42)`  rot `(6°, -20°, 8°)` → 屏幕左下、前方、向左偏

### 瞄准（_aim_weight = 1）
- 武器：pos `(0.0, -0.16, -0.38)`  rot `(4°, 0°, -1°)` → 居中、抬起、拉近
- 盾牌位姿固定，不随瞄准变化

## 当前行为要点

- `arm_animation_enabled = false`（默认关闭）：挥砍 / 拉弓 / 后坐等动作动画全部不播放，
  武器与盾牌恒为静态持握位。仅保留 BobPivot 微摆与 AimPivot 瞄准位移。
- 独立武器相机（`use_weapon_camera = true`，仅游戏中生效）：武器 / 盾牌渲染在**第 11 层（1<<10）**，
  由专属 SubViewport 相机（near = 0.001）渲染；主相机 `cull_mask = 1` 不渲染该层 → 贴墙不穿模。
  headless / 无主相机时回退第 1 层，武器不会消失。
- 武器姿态按武器类型微调（`_apply_weapon_pose_offsets`）：弓 / 弩有独立 view / aim 偏移，其余用默认。

## 截图说明

沙箱 headless 使用 RendererDummy，无法将 3D 光栅化到帧缓冲，故本环境无法生成真实渲染截图；
本说明纯基于源码。如需本地真实截图，可在带 GPU 的机器上用 `--headless` + 真实渲染驱动运行同样探针。
