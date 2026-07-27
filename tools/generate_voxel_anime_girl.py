from __future__ import annotations

"""二次元日漫风格体素美少女生成器 (anime_girl)。

比例尺：1m = 32px（docs/17）。高度 48px（中型人形）。

设计语言：Barony 风格集群体素（clustered voxel masses）
  - 每个部件 >= 2px 三轴，禁止薄片/碎片
  - 阶梯式轮廓（stepped/broken contour），头发超出头部、裙摆超出腰际
  - 4-6 级色阶表达体积转折和光照层次
  - 头发是最大视觉主体（~14 部件，占据轮廓主导）
  - 面部使用大色块雕刻（socket→bright→spark 链），拒绝贴纸式细节
  - 零 location 覆盖 hack，所有位置通过面接触计算
  - 多子部件共享同一宿主面时，必须通过不同轴或偏移避免三轴穿透
  - 每个 fa 返回值必须捕获，供下游链式面接触使用

运行：
  D:/123/blender/blender.exe --background --python tools/generate_voxel_anime_girl.py
"""

import math
import sys
from pathlib import Path

import bpy

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))

from voxel_model_primitives import (
    cube_px,
    make_material,
    make_root,
    export_glb as export_static_glb,
    reset_scene,
    configure_real_render,
    render_real_views,
    setup_lights_and_camera,
    bounds_center_scale,
)
from voxel_humanoid_rig import (
    PX,
    create_voxel_humanoid_armature,
    parent_parts_by_bone,
)
from voxel_character_rig import (
    build_all_actions,
    build_weapon_actions,
    export_glb as export_rig_glb,
)
from voxel_overlap_guard import (
    assert_parts_voxel_assembly_valid,
    exterior_plate_center,
)
from voxel_single_model_cli import reject_target_override

MODEL_ID = "anime_girl"
HEIGHT_PX = 48.0
STATIC_OUTPUT = ROOT / "assets" / "meshes" / "characters" / f"voxel_{MODEL_ID}_{int(HEIGHT_PX)}px.glb"
RIG_OUTPUT = ROOT / "assets" / "meshes" / "characters" / f"voxel_{MODEL_ID}_{int(HEIGHT_PX)}px_rig.glb"
PREVIEW_DIR = ROOT / "reports" / "characters_preview"
GROUND_OFFSET_PX = 1.0

# ======================================================================
# Z 布局 (px, ground Z=0) -- 48px 总高
# ======================================================================
# Foot:        0.0  ~  3.0
# LowerLeg:    3.0  ~  9.0
# UpperLeg:    9.0  ~ 14.0
# Pelvis:     14.0  ~ 18.0
# Belt:       18.0  ~ 20.0
# Torso:      20.0  ~ 30.0
# Neck:       30.0  ~ 32.0
# Head:       32.0  ~ 44.0
# Hair top:   44.0  ~ 48.0
# ======================================================================


def build_anime_girl() -> tuple[
    bpy.types.Object, list[bpy.types.Object], dict[str, list[bpy.types.Object]]
]:
    root = make_root(f"voxel_{MODEL_ID}")
    armature = create_voxel_humanoid_armature(
        HEIGHT_PX, f"VoxelHumanoidRig_{MODEL_ID}"
    )
    armature.parent = root

    # ================================================================
    # Materials — 每个区域 4-6 级色阶
    # ================================================================
    # 皮肤 5 级 (暖桃色)
    skin_xhi  = make_material("skin_xhi",  (1.00, 0.90, 0.84, 1.0), roughness=0.72)
    skin_hi   = make_material("skin_hi",   (0.97, 0.84, 0.75, 1.0), roughness=0.76)
    skin_base = make_material("skin_base", (0.92, 0.76, 0.65, 1.0), roughness=0.80)
    skin_mid  = make_material("skin_mid",  (0.80, 0.60, 0.48, 1.0), roughness=0.84)
    skin_sh   = make_material("skin_sh",   (0.66, 0.46, 0.34, 1.0), roughness=0.88)

    # 头发 6 级 (樱花粉)
    hair_xhi  = make_material("hair_xhi",  (1.00, 0.95, 0.96, 1.0), roughness=0.60)
    hair_hi   = make_material("hair_hi",   (1.00, 0.85, 0.90, 1.0), roughness=0.66)
    hair_lgt  = make_material("hair_lgt",  (0.98, 0.72, 0.82, 1.0), roughness=0.72)
    hair_mid  = make_material("hair_mid",  (0.92, 0.56, 0.70, 1.0), roughness=0.78)
    hair_sh   = make_material("hair_sh",   (0.78, 0.40, 0.56, 1.0), roughness=0.84)
    hair_dk   = make_material("hair_dk",   (0.60, 0.28, 0.44, 1.0), roughness=0.88)

    # 眼睛 4 级
    eye_wht   = make_material("eye_wht",   (0.97, 0.97, 1.00, 1.0), roughness=0.30)
    eye_iris  = make_material("eye_iris",  (0.18, 0.48, 0.96, 1.0), roughness=0.22)
    eye_pupil = make_material("eye_pupil", (0.05, 0.10, 0.35, 1.0), roughness=0.32)
    eye_spark = make_material("eye_spark", (1.00, 1.00, 1.00, 1.0), emission=2.8, roughness=0.12)

    # 水手服 5 级 (海军蓝)
    uni_xhi   = make_material("uni_xhi",   (0.30, 0.42, 0.64, 1.0), roughness=0.70)
    uni_hi    = make_material("uni_hi",    (0.24, 0.34, 0.54, 1.0), roughness=0.74)
    uni_mid   = make_material("uni_mid",   (0.18, 0.25, 0.42, 1.0), roughness=0.78)
    uni_dk    = make_material("uni_dk",    (0.11, 0.16, 0.30, 1.0), roughness=0.82)
    uni_deep  = make_material("uni_deep",  (0.06, 0.09, 0.20, 1.0), roughness=0.86)

    # 白色 2 级
    wht       = make_material("wht",        (0.96, 0.96, 1.00, 1.0), roughness=0.62)
    wht_sh    = make_material("wht_sh",     (0.82, 0.82, 0.90, 1.0), roughness=0.72)

    # 丝带 3 级 (红)
    rib_hi    = make_material("rib_hi",     (0.96, 0.20, 0.26, 1.0), roughness=0.52)
    rib_mid   = make_material("rib_mid",    (0.78, 0.12, 0.16, 1.0), roughness=0.62)
    rib_dk    = make_material("rib_dk",     (0.56, 0.06, 0.10, 1.0), roughness=0.72)

    # 袜子 3 级
    sock_hi   = make_material("sock_hi",    (1.00, 1.00, 1.00, 1.0), roughness=0.62)
    sock      = make_material("sock",       (0.94, 0.94, 0.98, 1.0), roughness=0.68)
    sock_sh   = make_material("sock_sh",    (0.78, 0.78, 0.86, 1.0), roughness=0.76)

    # 鞋 3 级 (棕色)
    shoe_hi   = make_material("shoe_hi",   (0.50, 0.32, 0.18, 1.0), roughness=0.68)
    shoe_mid  = make_material("shoe_mid",  (0.38, 0.22, 0.12, 1.0), roughness=0.76)
    shoe_dk   = make_material("shoe_dk",    (0.24, 0.14, 0.06, 1.0), roughness=0.84)

    # 面部细节
    lip       = make_material("lip",        (0.90, 0.48, 0.48, 1.0), roughness=0.76)

    parts: list[bpy.types.Object] = []
    parts_by_bone: dict[str, list[bpy.types.Object]] = {
        "Head": [], "Neck": [], "Torso": [], "Pelvis": [],
        "UpperArm.L": [], "LowerArm.L": [], "Hand.L": [],
        "UpperArm.R": [], "LowerArm.R": [], "Hand.R": [],
        "UpperLeg.L": [], "LowerLeg.L": [], "Foot.L": [],
        "UpperLeg.R": [], "LowerLeg.R": [], "Foot.R": [],
    }

    def reg(bone, name, cx, cy, cz, sx, sy, sz, mat) -> None:
        p = cube_px(name, (cx, cy, cz), (sx, sy, sz), mat)
        p.parent = root
        parts.append(p)
        parts_by_bone[bone].append(p)

    def fa(hc, hs, name, ps, mat, axis, side, bone, **kw) -> tuple[float, float, float]:
        """Face-attach a plate to a host. Returns plate center tuple."""
        pc = list(exterior_plate_center(hc, hs, ps, axis, side))
        if "dx" in kw:
            pc[0] = kw["dx"]
        if "dy" in kw:
            pc[1] = kw["dy"]
        if "dz" in kw:
            pc[2] = kw["dz"]
        reg(bone, name, pc[0], pc[1], pc[2], ps[0], ps[1], ps[2], mat)
        return (pc[0], pc[1], pc[2])

    # ================================================================
    # 1. 玛丽珍鞋 (Foot.L/R)  Z: 0 ~ 3.0
    # ================================================================
    for side, s in [("left", -1), ("right", 1)]:
        su = side[0].upper()
        bx = s * 3.2
        shoe_c = (bx, 0.0, 1.5)
        shoe_s = (5.0, 7.0, 3.0)
        reg(f"Foot.{su}", f"{side}_shoe_body", *shoe_c, *shoe_s, shoe_mid)
        fa(shoe_c, shoe_s, f"{side}_shoe_toe",
           (5.0, 4.0, 2.5), shoe_hi, "y", "neg", f"Foot.{su}")
        fa(shoe_c, shoe_s, f"{side}_shoe_heel",
           (3.5, 3.0, 2.5), shoe_dk, "y", "pos", f"Foot.{su}")

    # ================================================================
    # 2. 过膝袜 (LowerLeg.L/R)  Z: 3.0 ~ 9.0
    # ================================================================
    for side, s in [("left", -1), ("right", 1)]:
        su = side[0].upper()
        bx = s * 3.0
        sock_c = (bx, 0.0, 6.0)
        sock_s = (4.0, 4.0, 6.0)
        reg(f"LowerLeg.{su}", f"{side}_sock_main",
           *sock_c, *sock_s, sock)
        fa(sock_c, sock_s, f"{side}_sock_front",
           (3.0, 2.0, 4.5), sock_hi, "y", "neg", f"LowerLeg.{su}")
        fa(sock_c, sock_s, f"{side}_sock_back",
           (3.5, 2.0, 5.0), sock_sh, "y", "pos", f"LowerLeg.{su}")

    # ================================================================
    # 3. 大腿 (UpperLeg.L/R)  Z: 9.0 ~ 14.0
    # ================================================================
    for side, s in [("left", -1), ("right", 1)]:
        su = side[0].upper()
        bx = s * 2.8
        thigh_c = (bx, 0.0, 11.5)
        thigh_s = (4.0, 4.0, 5.0)
        reg(f"UpperLeg.{su}", f"{side}_thigh_main",
           *thigh_c, *thigh_s, skin_base)
        fa(thigh_c, thigh_s, f"{side}_thigh_hl",
           (3.0, 2.0, 3.5), skin_hi, "y", "neg", f"UpperLeg.{su}")

    # ================================================================
    # 4. 骨盆 (Pelvis)  Z: 14.0 ~ 18.0
    # ================================================================
    pel_c = (0.0, 0.0, 16.0)
    pel_s = (8.0, 6.0, 4.0)
    reg("Pelvis", "pelvis_main", *pel_c, *pel_s, uni_dk)
    pel_f_c = fa(pel_c, pel_s, "pelvis_front",
                 (7.0, 2.0, 3.0), uni_mid, "y", "neg", "Pelvis")
    pel_b_c = fa(pel_c, pel_s, "pelvis_back",
                 (7.0, 3.0, 3.0), uni_deep, "y", "pos", "Pelvis")

    # ================================================================
    # 5. 腰带 (Pelvis)  Z: 18.0 ~ 20.0
    # ================================================================
    reg("Pelvis", "belt", 0.0, 0.0, 19.0, 9.0, 7.0, 2.0, wht)

    # ================================================================
    # 6. 百褶裙 (Pelvis)  Z: ~9.5 ~ 19.5
    # ================================================================
    sk_f_s = (10.0, 3.0, 7.0)
    sk_f_c = fa(pel_f_c, (7.0, 2.0, 3.0), "skirt_front",
                 sk_f_s, uni_mid, "y", "neg", "Pelvis")
    fa(sk_f_c, sk_f_s, "skirt_hem_f",
       (12.0, 4.0, 3.0), uni_dk, "z", "neg", "Pelvis")

    sk_b_s = (10.0, 3.0, 7.0)
    sk_b_c = fa(pel_b_c, (7.0, 3.0, 3.0), "skirt_back",
                 sk_b_s, uni_mid, "y", "pos", "Pelvis")
    fa(sk_b_c, sk_b_s, "skirt_hem_b",
       (12.0, 4.0, 3.0), uni_dk, "z", "neg", "Pelvis")

    for dx in (-3.0, 3.0):
        fa(sk_f_c, sk_f_s, f"pleat_f{dx:+.0f}".replace(".", ""),
           (2.0, 2.0, 5.0), wht, "y", "neg", "Pelvis", dx=dx)
        fa(sk_b_c, sk_b_s, f"pleat_b{dx:+.0f}".replace(".", ""),
           (2.0, 2.0, 5.0), wht_sh, "y", "pos", "Pelvis", dx=dx)

    # ================================================================
    # 7. 躯干/水手服 (Torso)  Z: 20.0 ~ 30.0
    # ================================================================
    tor_c = (0.0, 0.0, 25.0)
    tor_s = (8.0, 6.0, 10.0)
    reg("Torso", "torso_core", *tor_c, *tor_s, uni_dk)

    tor_f_c = fa(tor_c, tor_s, "torso_front",
                 (7.0, 2.0, 9.0), uni_mid, "y", "neg", "Torso")
    tor_b_c = fa(tor_c, tor_s, "torso_back",
                 (7.0, 4.0, 7.0), uni_deep, "y", "pos", "Torso")

    # 水手领后片
    col_b_c = fa(tor_b_c, (7.0, 4.0, 7.0), "collar_back",
                 (12.0, 3.0, 5.0), wht, "y", "pos", "Torso")
    fa(col_b_c, (12.0, 3.0, 5.0), "collar_stripe",
       (10.0, 2.0, 2.0), uni_dk, "z", "pos", "Torso")

    # 翻领
    flap_l_c = fa(tor_f_c, (7.0, 2.0, 9.0), "collar_flap_l",
                   (3.5, 3.0, 5.0), wht, "y", "neg", "Torso", dx=-2.5)
    fa(flap_l_c, (3.5, 3.0, 5.0), "collar_stripe_l",
       (3.0, 2.0, 3.5), uni_dk, "y", "neg", "Torso")

    flap_r_c = fa(tor_f_c, (7.0, 2.0, 9.0), "collar_flap_r",
                   (3.5, 3.0, 5.0), wht, "y", "neg", "Torso", dx=2.5)
    fa(flap_r_c, (3.5, 3.0, 5.0), "collar_stripe_r",
       (3.0, 2.0, 3.5), uni_dk, "y", "neg", "Torso")

    # 红丝带 — 单一结, Y-attach torso_front front, X=0, sz=2
    # flap_l X=-4.25~-0.75, flap_r X=0.75~4.25
    # ribbon_knot X=-1~1 → X overlap with flap = 0.25px < VOLUME_EPS ✓
    fa(tor_f_c, (7.0, 2.0, 9.0), "ribbon_knot",
       (2.0, 2.0, 2.0), rib_hi, "y", "neg", "Torso")

    # 肩膀
    sh_l_c = fa(tor_c, tor_s, "shoulder_l",
                (5.0, 5.0, 3.0), uni_hi, "x", "neg", "Torso")
    fa(sh_l_c, (5.0, 5.0, 3.0), "shoulder_wht_l",
       (3.5, 2.0, 2.0), wht, "y", "neg", "Torso")
    sh_r_c = fa(tor_c, tor_s, "shoulder_r",
                (5.0, 5.0, 3.0), uni_hi, "x", "pos", "Torso")
    fa(sh_r_c, (5.0, 5.0, 3.0), "shoulder_wht_r",
       (3.5, 2.0, 2.0), wht, "y", "neg", "Torso")

    # ================================================================
    # 8. 手臂 — 链式 Z-stack: shoulder → sleeve → cuff → upper_arm
    #         → forearm → hand
    # ================================================================
    for side, s in [("left", -1), ("right", 1)]:
        su = side[0].upper()
        skin_arm = skin_hi if side == "left" else skin_base
        uni_arm = uni_hi if side == "left" else uni_mid

        sh_c = sh_l_c if side == "left" else sh_r_c
        sh_s = (5.0, 5.0, 3.0)
        slv_c = fa(sh_c, sh_s, f"{side}_sleeve",
                   (4.0, 4.0, 5.0), uni_arm, "z", "neg", f"UpperArm.{su}")

        cuff_c = fa(slv_c, (4.0, 4.0, 5.0), f"{side}_sleeve_cuff",
                   (4.0, 5.0, 2.5), wht, "z", "neg", f"UpperArm.{su}")

        ua_c = fa(cuff_c, (4.0, 5.0, 2.5), f"{side}_upper_arm",
                 (3.0, 3.0, 4.0), skin_arm, "z", "neg", f"UpperArm.{su}")

        fa_c = fa(ua_c, (3.0, 3.0, 4.0), f"{side}_forearm",
                 (3.0, 3.0, 5.0), skin_arm, "z", "neg", f"LowerArm.{su}")

        fa(fa_c, (3.0, 3.0, 5.0), f"{side}_hand",
          (3.0, 2.5, 3.0), skin_hi, "z", "neg", f"Hand.{su}")

    # ================================================================
    # 9. 颈部 (Neck)  Z: 30.0 ~ 32.0
    # ================================================================
    reg("Neck", "neck_front", 0.0, -0.5, 31.0, 3.5, 3.0, 2.0, skin_sh)
    reg("Neck", "neck_back", 0.0, 2.0, 31.0, 3.0, 2.0, 2.0, skin_sh)

    # ================================================================
    # 10. 头部主体 (Head)  Z: 32.0 ~ 44.0
    # ================================================================
    hd_c = (0.0, 1.0, 38.0)
    hd_s = (10.0, 8.0, 12.0)
    reg("Head", "head_rear", *hd_c, *hd_s, skin_base)

    hd_f_c = fa(hd_c, hd_s, "head_front",
                (8.0, 4.0, 10.0), skin_hi, "y", "neg", "Head")

    # 下巴 (Z-stack on head_front bottom)
    chin_c = fa(hd_f_c, (8.0, 4.0, 10.0), "chin",
               (4.0, 3.0, 3.0), skin_mid, "z", "neg", "Head")

    # ================================================================
    # 11. 面部特征 (Head)
    #     socket→bright→spark 链式雕刻
    # ================================================================
    eye_sockets: dict[str, tuple[float, float, float]] = {}
    for side, s in [("left", -1), ("right", 1)]:
        bx = s * 2.5
        sk_c = fa(hd_f_c, (8.0, 4.0, 10.0), f"eye_socket_{side}",
                  (3.0, 2.0, 3.5), skin_sh, "y", "neg", "Head", dx=bx)
        eye_sockets[side] = sk_c
        br_c = fa(sk_c, (3.0, 2.0, 3.5), f"eye_iris_{side}",
                  (2.5, 2.0, 3.0), eye_iris, "y", "neg", "Head")
        fa(br_c, (2.5, 2.0, 3.0), f"eye_spark_{side}",
           (2.0, 2.0, 2.0), eye_spark, "y", "neg", "Head")

    # 眉毛 — Z-stack on 各自 eye_socket 顶面 (链式面接触)
    for side, s in [("left", -1), ("right", 1)]:
        bx = s * 2.5
        fa(eye_sockets[side], (3.0, 2.0, 3.5), f"brow_{side}",
           (3.0, 2.0, 2.0), hair_dk, "z", "pos", "Head", dx=bx)

    # 鼻子 — Y-attach head_front front, dz=36 定位到面部中部
    # Y 面接触 head_front → Y 轴 flush → 不会三轴穿透
    fa(hd_f_c, (8.0, 4.0, 10.0), "nose",
       (2.0, 2.0, 2.0), skin_xhi, "y", "neg", "Head", dz=36.0)

    # 嘴巴 — Y-attach chin front (链式面接触)
    fa(chin_c, (4.0, 3.0, 3.0), "mouth",
       (2.5, 2.0, 2.0), lip, "y", "neg", "Head")

    # ================================================================
    # 12. 头发 (Head)  ~13 部件 — 模型最大视觉主体
    # ================================================================
    # 背发主块 (Y-attach head_rear back)
    hb_c = fa(hd_c, hd_s, "hair_back_main",
               (11.0, 5.0, 12.0), hair_sh, "y", "pos", "Head")

    # 背发高光 — Z-stack on 背发顶部 (不再 Y-attach 同面)
    fa(hb_c, (11.0, 5.0, 12.0), "hair_back_hl",
       (8.0, 3.0, 8.0), hair_hi, "z", "pos", "Head")

    # hair_accent — Y-attach 背发背面 (背发背面唯一子部件)
    fa(hb_c, (11.0, 5.0, 12.0), "hair_accent",
       (3.0, 3.0, 5.0), hair_lgt, "y", "pos", "Head")

    # 头顶 (Z-stack on head_rear top)
    ht_c = fa(hd_c, hd_s, "hair_top",
               (12.0, 9.0, 3.0), hair_lgt, "z", "pos", "Head")

    # 头冠 (Z-stack on hair_top top) — 必须捕获返回值供 ahoge 使用
    hr_c = fa(ht_c, (12.0, 9.0, 3.0), "hair_crown",
               (8.0, 5.5, 2.0), hair_xhi, "z", "pos", "Head")

    # 呆毛 — Z-stack on hair_crown top (链式)
    fa(hr_c, (8.0, 5.5, 2.0), "ahoge",
       (2.0, 2.0, 3.0), hair_hi, "z", "pos", "Head")

    # 侧发 (X-attach head_rear 侧面)
    hair_sides: dict[str, tuple[float, float, float]] = {}
    for side, s in [("left", -1), ("right", 1)]:
        hs_c = fa(hd_c, hd_s, f"hair_side_{side}",
                   (4.0, 5.0, 5.0), hair_mid, "x",
                   "neg" if side == "left" else "pos", "Head")
        hair_sides[side] = hs_c
        # 侧发阴影 — Z-stack on 侧发底部 (链式)
        fa(hs_c, (4.0, 5.0, 5.0), f"hair_side_sh_{side}",
           (3.0, 3.0, 4.0), hair_sh, "z", "neg", "Head")

    # 耳朵 — Z-stack on 侧发顶部 (不与 hair_top 重叠，因为侧发 Z < hair_top Z)
    for side, s in [("left", -1), ("right", 1)]:
        hs_c = hair_sides[side]
        fa(hs_c, (4.0, 5.0, 5.0), f"ear_{side}",
           (3.0, 3.0, 2.0), skin_mid, "z", "pos", "Head")

    # 刘海 — Z-stack on head_front 顶面 (不与 eye_socket 共享前面 Y 坐标)
    fa(hd_f_c, (8.0, 4.0, 10.0), "hair_bangs_l",
       (3.0, 3.0, 2.0), hair_mid, "z", "pos", "Head", dx=-3.5)
    fa(hd_f_c, (8.0, 4.0, 10.0), "hair_bangs_r",
       (3.0, 3.0, 2.0), hair_mid, "z", "pos", "Head", dx=3.5)
    fa(hd_f_c, (8.0, 4.0, 10.0), "hair_bangs_c",
       (2.0, 3.0, 2.0), hair_hi, "z", "pos", "Head")

    # ------------------------------------------------------------------
    # Validate
    # ------------------------------------------------------------------
    assert_parts_voxel_assembly_valid(parts, label=MODEL_ID)

    # Bind bones
    parent_parts_by_bone(parts_by_bone, armature)
    build_all_actions(armature)
    build_weapon_actions(armature)

    return root, parts, parts_by_bone


def main() -> None:
    reject_target_override(MODEL_ID)
    reset_scene()
    root, parts, parts_by_bone = build_anime_girl()

    root.location.z += PX * GROUND_OFFSET_PX

    STATIC_OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    root.rotation_euler.z = math.pi
    bpy.context.view_layer.update()
    bpy.ops.object.select_all(action="DESELECT")
    root.select_set(True)
    for child in root.children_recursive:
        child.select_set(True)
    bpy.context.view_layer.objects.active = root
    bpy.ops.export_scene.gltf(
        filepath=str(STATIC_OUTPUT),
        export_format="GLB",
        use_selection=True,
        export_yup=True,
        export_apply=True,
    )
    root.rotation_euler.z = 0.0
    bpy.context.view_layer.update()

    export_rig_glb(RIG_OUTPUT)

    center, scale = bounds_center_scale(root)
    camera = setup_lights_and_camera(center, scale)
    configure_real_render()
    render_real_views(PREVIEW_DIR, f"voxel_{MODEL_ID}", center, scale, camera)

    print(f"Wrote {STATIC_OUTPUT}")
    print(f"Wrote {RIG_OUTPUT}")
    print(f"Total parts: {len(parts)}")
    print("Done.")


if __name__ == "__main__":
    main()
