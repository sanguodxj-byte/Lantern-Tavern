# 第一人称武器 / 盾牌表现规范

第一人称 ViewModel 只呈现武器与盾牌本体。不得实例化、显示或驱动手臂、手、身体或
其他角色部位；第三人称角色 rig 继续承担世界层动画和战斗时序。

## 节点层级

```text
ViewModel
└─ BobPivot                         程序化装备运动 + 近墙收纳
   └─ AimPivot                      平滑 hip/aim 姿态
      ├─ ActionPivot                武器作者化动作
      │  └─ WeaponSocket
      │     └─ WeaponOrientation
      └─ ShieldActionPivot          盾牌作者化动作
         └─ ShieldImpactPivot       独立格挡冲击弹簧
            └─ ShieldSocket
               └─ ShieldOrientation
```

`ActionPivot` 与 `ShieldActionPivot` 分离，保证举盾不会错误拖动主手武器；
`ShieldImpactPivot` 只处理格挡瞬间的位移与角动量，不会改写持续格挡动作。

## 动作资源

- 每种武器拥有 `standard / alternate / heavy` 三套可编辑 `AnimationLibrary`。
- 攻击动作使用六阶段：持握、预备、蓄力、命中、随动、复位。
- 装备轨道使用三次插值；动作库只允许 `ActionPivot`、`WeaponSocket`、
  `ShieldActionPivot`、`ShieldImpactPivot`、`ShieldSocket` 和 `ShieldOrientation` 路径。
- 第一人称表现是本地视觉层；命中窗口、伤害、状态退出和联网请求仍由 PlayerState 与
  `CombatSlashAnimator` 决定。

## 程序化附加运动

`first_person_equipment_motion.gd` 叠加以下只读反馈：

- 静止呼吸、行走/奔跑步态与横移倾斜；
- 鼠标视角惯性、加速度滞后和重型装备质量差异；
- 冲刺低持、腾空偏移与落地回弹；
- 弓/弩/法器后坐，以及盾牌格挡冲击；
- 瞄准和攻击承诺阶段自动减弱附加运动，避免干扰准星。

## 渲染与遮挡

武器/盾牌由独立 SubViewport 叠加相机渲染，并在靠近实体表面时平滑后收和下压。
渲染副本保留纹理与逐像素光照，不使用自发光或无光照材质冒充可见度。

## 验证

动作资源由 `first_person_weapon_animation_catalog_test.gd` 验证三套变体、六阶段、三次插值
和无角色骨骼轨道；运行时由 `view_model_test.gd` 与
`first_person_equipment_motion_test.gd` 验证纯装备节点、瞄准、后坐、落地与盾牌冲击。
真实 3D 动作序列使用 `tools/sword_first_person_animation_capture.gd` 生成并逐帧检查。
