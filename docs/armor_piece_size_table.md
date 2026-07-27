# 护甲部件尺寸表（成套可穿戴）

比例尺：`1m = 32px`，`1px = 1/32m`。
锚定角色：`voxel_player_54px` 包络 **24 × 54 × 14 px**（宽 × 高 × 深）。

本表是 leather_set / iron_set 四个槽位的**建模前尺寸源**。每个生成器必须在文件头写明
`TARGET_ENVELOPE_PX = (W, H, D)`，并由对应 gdUnit 按像素容差锁定。禁止先摆米制坐标。

## 1. 角色对照（裸模参考区）

| 区域 | 角色参考体量 (px) | 说明 |
|------|-------------------|------|
| 头颅 | W10–12 · H10 · D8–9 | cranium + face + jaw 合读 |
| 颈 | W4 · H3 · D4 | Neck 骨附近 |
| 躯干核心 | W12 · H12 · D8–9 | 衬衫/背心主体 |
| 肩宽跨度 | ~W18–20 | shoulder yoke 外缘 |
| 前臂 | W4 · L6 · D6 | LowerArm 皮肤段 |
| 足（含模自带靴形） | W5 · L9 · H5 | Foot 骨附近 |

## 2. 成套护甲目标包络（必须比角色对应区大一截）

“大一截”规则：相对上表参考区，主轴至少 **+4px**，次轴至少 **+3px**；
肩/盔/靴的外轮廓必须在三视图上压过裸模轮廓。过厚的 runtime scale（>1.3）禁止用来掩盖欠体量建模。

| 槽位 | 轻甲 ID | 重甲 ID | 目标包络 W×H×D (px) | 相对角色增量 | 主形体（≥80% 体量） |
|------|---------|---------|---------------------|--------------|---------------------|
| head | leather_helmet | iron_helmet | **16 × 14 × 14** / **32 × 22 × 16** | 头 +4~6；铁盔牛角外展总宽~32 | 皮：软帽/耳扇；铁：诺德穹盔+双牛角 |
| body | leather_armor | chain_armor | **22 × 26 × 14** / **24 × 28 × 14** | 躯干+肩 明显外扩 | 胸/腹叠层、肩甲、裙甲/哈伯克下摆 |
| hands | leather_bracers | iron_bracers | **9 × 12 × 9** / **10 × 13 × 10** | 前臂 +4~6 | 护臂筒（长轴）、外护板、束带 |
| feet | leather_boots | iron_boots | **9 × 13 × 11** / **10 × 14 × 12** | 足 +4~5 | 鞋底、鞋面、踝筒、后跟（铁靴含胫甲） |

> 包络轴约定（Blender 创作空间，与现有 plate/leather 躯干一致）：
> - **X = 宽**（左右）
> - **Y = 深**（**+Y 为角色正面**；靴例外：鞋头朝 **−Y**，以匹配 Foot 骨挂载）
> - **Z = 高**（向上）
> - 护腕长轴沿 **Z**（导出后为 Godot +Y，贴合 LowerArm 骨）

## 3. 分件细部尺寸（建模 checklist）

### 3.1 头盔 head（两套必须一眼可辨）

| 部件 | 轻甲 leather（斥候软帽） | 重甲 iron（诺德牛角盔 / 上古卷轴风） | 备注 |
|------|-------------------------|--------------------------------------|------|
| 主冠/盔穹 | 偏扁软皮冠 | 钢穹阶梯圆顶 | 皮=帽，铁=盔 |
| 额部 | 宽软檐 | 钢眉箍 + 眼缝 + 长鼻铠 | |
| 侧部 | 大耳扇下垂 | 短颊甲 | 皮耳扇身份锚 |
| 牛角（仅铁） | — | 双角根→柱→外展→尖，骨色+铁箍 | 总宽约 26；禁止短钉充数 |
| 顶饰 | 中缝线脊 | 无软檐、有角 | |

### 3.2 胸甲 body

| 部件 | 轻甲 leather 22×26×14 | 重甲 chain 24×28×14 | 备注 |
|------|----------------------|---------------------|------|
| 领圈 | 10×6×4 | 10×6×4 | 最上沿 |
| 肩带 | 20×10×5 | 22×10×6 | 最宽主形体 |
| 胸层 | 18×10×6 | 20×10×6 | 阶梯收腰 |
| 腰层 | 16×8×5 | 16×8×6 | |
| 下摆/裙甲 | 14×8×6 | 14×8×6 | 盖过腰带 |
| 肩甲 pauldron | 外贴 3–4 厚 | 外贴 4 厚 | 侧视必须有肩体积 |
| 前胸板（外贴） | 两层阶梯 | 链环外贴层 | 禁止只有薄贴片无主体 |

### 3.3 护腕 hands（单只；L/R 挂载镜像）

| 部件 | 轻甲 9×12×9 | 重甲 10×13×10 | 备注 |
|------|-------------|---------------|------|
| 主筒 | 7×7×10 | 6×6×11 + 金属边 | 长轴 Z=12/13 总包络 |
| 外护板 | 5×2×7 | 三段薄甲片 | 在 +Y 外侧面 |
| 束带 | 1–2 厚环 | 同左 | 禁止陷入主筒 |
| 口缘 | 上下各 1px 加宽 | 金属口缘 | 阶梯轮廓 |

### 3.4 靴 feet（单只；L/R 挂载）

| 部件 | 轻甲 9×13×11 | 重甲 10×14×12 | 备注 |
|------|--------------|---------------|------|
| 鞋底 | 8×12×2 | 9×13×2 | 长轴 Y，鞋头 −Y |
| 鞋面 vamp | 8×9×4 | 甲面 8×10×3 | |
| 踝筒 | 8×7×4 | 9×7×4 | |
| 靴口 cuff | 9×7×2 | 皮口 + 胫甲 | 总高到 11/12 |
| 后跟 | 8×2×3 | 甲跟 | +Y 侧 |
| 鞋头盖 | 8×2×2 |  sabaton 趾甲 | −Y 端 |

## 4. 挂载尺度（runtime，建模体量到位后）

角色 `voxel_player_54px` **面朝 world −Z**（鼻尖/鞋头在 −Z）。Body/头盔 Blender **+Y 正面**经 glTF Y-up 后为 mesh **−Z**；Head/Torso 骨 rest 已含 Y 翻转效应，挂载需 **Y180** 才能让盔甲正面与脸同向。靴 mesh **+Z = 鞋头** → 挂载映射到 world −Z。



网格本身已含“大一截”时，挂载 scale 只做微调：

| 槽位 | scale | 旋转要点 |
|------|-------|----------|
| head | 1.12–1.20 | 正面 +Y 创作 → 近 identity |
| body | 1.10–1.18 | 同头 |
| hands | 1.15–1.22 | 筒沿骨 +Y；L 侧 X 镜像 |
| feet | 1.18–1.28 | 分侧欧拉；鞋底原点下沉到踝下 |

禁止再用 ≥1.7 的 scale 去“撑大”欠体量模型。

## 5. 质量门槛

- Barony 式成组体素 + 阶梯轮廓；禁止大方盒 + 微贴片凑数。
- 主形体承担约 80% 体量；铆钉/缝线/环纹只做身份锚点。
- 只允许面接触；`assert_parts_no_positive_volume_overlap` + `assert_parts_voxel_assembly_valid`。
- 每件独立 `tools/generate_voxel_<id>.py`，禁止 batch。
- 每件改完：单件生成 → 资产测试 → `voxel_prop_three_view_capture.gd --asset=<id>` → 成套穿戴截图。

## 6. 输出路径

| ID | GLB |
|----|-----|
| leather_helmet | `assets/meshes/armor/armor_voxel_leather_helmet.glb` |
| leather_armor | `assets/meshes/armor/armor_voxel_leather_armor.glb` |
| leather_bracers | `assets/meshes/armor/armor_voxel_leather_bracers.glb` |
| leather_boots | `assets/meshes/armor/armor_voxel_leather_boots.glb` |
| iron_helmet | `assets/meshes/armor/armor_voxel_iron_helmet.glb` |
| chain_armor | `assets/meshes/armor/armor_voxel_chain_armor.glb` |
| iron_bracers | `assets/meshes/armor/armor_voxel_iron_bracers.glb` |
| iron_boots | `assets/meshes/armor/armor_voxel_iron_boots.glb` |
