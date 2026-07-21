#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
gdscript_codemap.py — Lantern Tavern GDScript 静态代码图谱生成器。

为什么需要它：
    GitNexus 等通用代码知识图谱工具基于 Tree-sitter，只支持 TS/JS/Python/C#/Go…
    等语言，**不含 GDScript**。本项目 99% 的逻辑是 .gd 文件，通用工具解析不了。
    本脚本用轻量正则 + 行扫描，提取 GDScript 的真实结构：
        class_name / extends / preload("res://...") / signal / enum /
        const / var(@export/@onready) / func(@rpc/@static) / 内部 class
    并构建可查询的依赖图谱（继承、文件依赖、autoload 使用），输出
    JSON 图谱 + 人类可读 Markdown 报告，供 AI 助手做"影响分析 / 改前定位"。

用法：
    python tools/gdscript_codemap.py [PROJECT_ROOT] [--include-addons] [--out-json X] [--out-md Y]

默认只扫描首方代码（globals/ scenes/ data/ fx/ 等），排除 addons/（第三方，
如 gdUnit4）。加 --include-addons 可一并纳入。
"""
import argparse
import json
import os
import re
import sys
from datetime import datetime, timezone

# ---- 正则（兼容 GDScript 4.x 语法；注释用 # / ## ） ----
RE_CLASS_NAME = re.compile(r"^\s*class_name\s+(\w+)")
RE_EXTENDS = re.compile(r"^\s*extends\s+(\S+)")
RE_INNER_CLASS = re.compile(r"^\s*class\s+(\w+)\s*:")
RE_SIGNAL = re.compile(r"^\s*(?:static\s+)?signal\s+(\w+)")
RE_ENUM = re.compile(r"^\s*enum\s+(\w+)")
RE_CONST = re.compile(r"^\s*const\s+(\w+)")
RE_VAR = re.compile(r"^\s*(?:var|@export\s+var|@onready\s+var)\s+(\w+)")
RE_FUNC = re.compile(r"^\s*(?:static\s+)?func\s+(\w+)\s*\(")
RE_PRELOAD = re.compile(r'(?:preload|load)\(\s*"([^"]+)"\s*\)')
RE_ANNOT = re.compile(r"^\s*@(\w+)")
RE_TOOL = re.compile(r"^\s*@tool\b")

BUILTIN_BASES = {
    "Node", "Node3D", "Node2D", "Control", "CanvasItem", "Object",
    "RefCounted", "Resource", "Reference", "ResourcePreloader", "AudioStreamPlayer",
    "CharacterBody3D", "CharacterBody2D", "RigidBody3D", "StaticBody3D",
    "Area3D", "Area2D", "CollisionObject3D", "Sprite3D", "Sprite2D",
    "MeshInstance3D", "CSGBox3D", "GPUParticles3D", "AnimationPlayer",
    "AnimationTree", "Timer", "HTTPRequest", "MultiplayerSpawner",
    "MultiplayerSynchronizer", "Camera3D", "Light3D", "OmniLight3D",
    "DirectionalLight3D", "SpotLight3D", "WorldEnvironment", "CSGMesh3D",
    "BoneAttachment3D", "Skeleton3D", "PhysicalBone3D", "MenuButton",
    "Button", "Label", "LineEdit", "TextureRect", "Panel", "Window",
    "AcceptDialog", "FileDialog", "OptionButton", "ItemList", "Tree",
    "GDScript", "PackedScene", "Dictionary", "Array", "Variant",
}


def read_text(path: str) -> str:
    """读取文件，兼容 UTF-8 BOM（GDScript 文件常见）。"""
    with open(path, "rb") as f:
        raw = f.read()
    if raw.startswith(b"\xef\xbb\xbf"):
        raw = raw[3:]
    # 容错：部分文件可能不是合法 UTF-8（极少见），用 errors="replace"
    return raw.decode("utf-8", errors="replace")


def resolve_dep_path(base_dir: str, project_root: str, res_path: str) -> str | None:
    """把 res://... 或相对路径解析为项目内相对路径。"""
    if res_path.startswith("res://"):
        cleaned = res_path[len("res://"):]
        rel = cleaned.replace("\\", "/")
        return rel
    if res_path.startswith("user://"):
        return None
    # 相对路径（极少数情况）
    cand = os.path.normpath(os.path.join(base_dir, res_path))
    try:
        rel = os.path.relpath(cand, project_root).replace("\\", "/")
        return rel if not rel.startswith("..") else None
    except ValueError:
        return None


def parse_file(path: str, project_root: str) -> dict:
    text = read_text(path)
    lines = text.splitlines()
    base_dir = os.path.dirname(path)

    info = {
        "rel": os.path.relpath(path, project_root).replace("\\", "/"),
        "lines": len(lines),
        "class_name": None,
        "extends": None,
        "extends_kind": None,      # builtin | custom | path | none
        "signals": [],
        "enums": [],
        "consts": 0,
        "vars": 0,
        "funcs": 0,
        "static_funcs": 0,
        "rpc_funcs": 0,
        "export_vars": 0,
        "onready_vars": 0,
        "inner_classes": [],
        "has_tool": False,
        "preloads": [],             # 解析后的相对路径
        "autoload_refs": [],       # 使用的 autoload 单例名
    }

    prev_annot = None  # 上一行的 @ 注解
    for ln in lines:
        if RE_TOOL.match(ln):
            info["has_tool"] = True

        m = RE_CLASS_NAME.match(ln)
        if m and info["class_name"] is None:
            info["class_name"] = m.group(1)

        m = RE_EXTENDS.match(ln)
        if m and info["extends"] is None:
            info["extends"] = m.group(1).strip().strip('"')

        m = RE_INNER_CLASS.match(ln)
        if m:
            info["inner_classes"].append(m.group(1))

        m = RE_SIGNAL.match(ln)
        if m:
            info["signals"].append(m.group(1))

        m = RE_ENUM.match(ln)
        if m:
            info["enums"].append(m.group(1))

        if RE_CONST.match(ln):
            info["consts"] += 1

        mv = re.match(r"^\s*@export\b", ln)
        mo = re.match(r"^\s*@onready\b", ln)
        if RE_VAR.match(ln):
            info["vars"] += 1
            if mv:
                info["export_vars"] += 1
            if mo:
                info["onready_vars"] += 1

        mf = RE_FUNC.match(ln)
        if mf:
            info["funcs"] += 1
            if re.match(r"^\s*static\s+func", ln):
                info["static_funcs"] += 1
            if prev_annot and "rpc" in prev_annot:
                info["rpc_funcs"] += 1

        ma = RE_ANNOT.match(ln)
        prev_annot = ma.group(1).lower() if ma else None

        for pm in RE_PRELOAD.finditer(ln):
            dep = resolve_dep_path(base_dir, project_root, pm.group(1))
            if dep and dep not in info["preloads"]:
                info["preloads"].append(dep)

    return info


def load_autoloads(project_root: str) -> list[dict]:
    """从 project.godot 的 [autoload] 段解析单例名 → 脚本路径。"""
    pg = os.path.join(project_root, "project.godot")
    if not os.path.isfile(pg):
        return []
    text = read_text(pg)
    autoloads = []
    in_section = False
    for ln in text.splitlines():
        if ln.strip().startswith("[") and not ln.strip().startswith("[autoload]"):
            in_section = False
        if ln.strip() == "[autoload]":
            in_section = True
            continue
        if in_section:
            m = re.match(r'\s*(\w+)\s*=\s*"\*?((?:res|uid)://[^"]+)"', ln)
            if m:
                name = m.group(1)
                target = m.group(2).replace("\\", "/")
                autoloads.append({"name": name, "path": target})
    return autoloads


def main() -> int:
    ap = argparse.ArgumentParser(description="GDScript 静态代码图谱生成器")
    ap.add_argument("project_root", nargs="?", default=".", help="项目根目录（含 project.godot）")
    ap.add_argument("--include-addons", action="store_true", help="一并扫描 addons/（第三方代码）")
    ap.add_argument("--out-json", default="gdscript_codemap.json")
    ap.add_argument("--out-md", default="docs/CODEMAP.md")
    args = ap.parse_args()

    project_root = os.path.abspath(args.project_root)
    if not os.path.isfile(os.path.join(project_root, "project.godot")):
        print(f"[ERR] 未在 {project_root} 找到 project.godot，请传入正确的项目根目录", file=sys.stderr)
        return 2

    autoloads = load_autoloads(project_root)
    autoload_names = {a["name"] for a in autoloads}
    autoload_by_path = {a["path"]: a["name"] for a in autoloads}

    # ---- 收集 .gd 文件 ----
    gd_files = []
    for root, dirs, files in os.walk(project_root):
        # 跳过隐藏/构建/第三方目录
        rel_root = os.path.relpath(root, project_root).replace("\\", "/")
        parts = rel_root.split("/")
        skip = False
        for p in parts:
            if p in (".git", ".godot", ".workbuddy", "__pycache__"):
                skip = True
                break
        if skip:
            dirs[:] = []
            continue
        if not args.include_addons and "addons" in parts:
            dirs[:] = []
            continue
        for fn in files:
            if fn.endswith(".gd"):
                gd_files.append(os.path.join(root, fn))

    gd_files.sort()
    print(f"[INFO] 扫描到 {len(gd_files)} 个 .gd 文件")

    files_info = []
    class_to_file = {}
    for fp in gd_files:
        info = parse_file(fp, project_root)
        if info["class_name"]:
            class_to_file[info["class_name"]] = info["rel"]
        files_info.append(info)

    # ---- 解析 extends 类型 ----
    for info in files_info:
        ext = info["extends"]
        if not ext:
            info["extends_kind"] = "none"
            continue
        if ext in BUILTIN_BASES:
            info["extends_kind"] = "builtin"
        elif ext in class_to_file:
            info["extends_kind"] = "custom"
        elif ext.endswith(".gd") or ext.startswith("res://"):
            info["extends_kind"] = "path"
        else:
            info["extends_kind"] = "builtin"  # 兜底：当作内置类

    # ---- autoload 使用检测 ----
    for info in files_info:
        text = read_text(os.path.join(project_root, info["rel"]))
        refs = set()
        for name in autoload_names:
            # 匹配 Name. 形式的使用（避免误伤子串）
            if re.search(r"\b" + re.escape(name) + r"\.", text):
                refs.add(name)
        # 自身就是该 autoload 脚本的，不算"使用"
        own = autoload_by_path.get(info["rel"])
        if own:
            refs.discard(own)
        info["autoload_refs"] = sorted(refs)

    # ---- 依赖边 ----
    dep_edges = []
    by_rel = {info["rel"]: info for info in files_info}
    for info in files_info:
        src = info["rel"]
        for dep in info["preloads"]:
            if dep in by_rel:
                dep_edges.append({"from": src, "to": dep, "type": "preload"})
        if info["extends_kind"] == "custom" and info["extends"] in class_to_file:
            dep_edges.append({"from": src, "to": class_to_file[info["extends"]], "type": "extends"})
        for a in info["autoload_refs"]:
            dep_edges.append({"from": src, "to": f"autoload:{a}", "type": "autoload"})

    # ---- 统计 ----
    total_signals = sum(len(i["signals"]) for i in files_info)
    total_funcs = sum(i["funcs"] for i in files_info)
    total_rpc = sum(i["rpc_funcs"] for i in files_info)
    total_consts = sum(i["consts"] for i in files_info)
    total_vars = sum(i["vars"] for i in files_info)

    # 被依赖最多（入度）的文件
    indeg = {}
    for e in dep_edges:
        if e["type"] in ("preload", "extends"):
            indeg[e["to"]] = indeg.get(e["to"], 0) + 1
    most_depended = sorted(indeg.items(), key=lambda kv: kv[1], reverse=True)[:15]

    # 行数 / 函数数 最多的文件
    largest_by_lines = sorted(files_info, key=lambda i: i["lines"], reverse=True)[:15]
    largest_by_funcs = sorted(files_info, key=lambda i: i["funcs"], reverse=True)[:15]

    graph = {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "project_root": project_root,
        "stats": {
            "gd_files": len(files_info),
            "classes": len(class_to_file),
            "signals": total_signals,
            "funcs": total_funcs,
            "rpc_funcs": total_rpc,
            "consts": total_consts,
            "vars": total_vars,
            "dependency_edges": len(dep_edges),
            "autoloads": len(autoloads),
        },
        "autoloads": autoloads,
        "classes": class_to_file,
        "files": files_info,
        "dependency_edges": dep_edges,
    }

    with open(args.out_json, "w", encoding="utf-8") as f:
        json.dump(graph, f, ensure_ascii=False, indent=2)
    print(f"[INFO] 图谱已写出：{args.out_json}")

    # ---- Markdown 报告 ----
    md = []
    md.append("# Lantern Tavern — GDScript 代码图谱 (CODEMAP)\n")
    md.append(f"> 自动生成于 {graph['generated_at']} ｜ 生成器：`tools/gdscript_codemap.py`\n")
    md.append("> **用途**：替代 GitNexus 等不支持 GDScript 的通用代码图谱工具，"
              "为本项目提供可查询的类继承 / 文件依赖 / autoload 使用视图，供改前影响分析。\n")
    md.append("## 概览\n")
    md.append(f"- 扫描 `.gd` 文件：**{len(files_info)}**（{'含 addons' if args.include_addons else '仅首方代码'}）")
    md.append(f"- 声明 `class_name`：**{len(class_to_file)}**")
    md.append(f"- `signal` 总数：**{total_signals}** ｜ `func` 总数：**{total_funcs}**（其中 `@rpc`：**{total_rpc}**）")
    md.append(f"- `const`：**{total_consts}** ｜ `var`：**{total_vars}**")
    md.append(f"- 依赖边（preload/extends/autoload）：**{len(dep_edges)}**")
    md.append(f"- Autoload 单例：**{len(autoloads)}**\n")

    md.append("## Autoload 单例注册表\n")
    md.append("| 名称 | 脚本路径 |")
    md.append("| --- | --- |")
    for a in autoloads:
        md.append(f"| `{a['name']}` | `{a['path']}` |")
    md.append("")

    md.append("## 类继承（custom extends）\n")
    custom = [i for i in files_info if i["extends_kind"] == "custom"]
    if custom:
        md.append("| 文件 | extends |")
        md.append("| --- | --- |")
        for i in custom:
            md.append(f"| `{i['rel']}` | `{i['extends']}` |")
    else:
        md.append("_（无跨 class_name 继承；多数脚本直接 extends 内置节点）_")
    md.append("")

    md.append("## 被依赖最多的文件（改前重点排查）\n")
    if most_depended:
        md.append("| 文件 | 被依赖次数 |")
        md.append("| --- | --- |")
        for rel, cnt in most_depended:
            md.append(f"| `{rel}` | {cnt} |")
    else:
        md.append("_（无内部 preload/extends 依赖）_")
    md.append("")

    md.append("## 体量最大的文件（按行数）\n")
    md.append("| 文件 | 行数 | func | signal |")
    md.append("| --- | --- | --- | --- |")
    for i in largest_by_lines:
        md.append(f"| `{i['rel']}` | {i['lines']} | {i['funcs']} | {len(i['signals'])} |")
    md.append("")

    md.append("## 函数最多的文件（按 func 数）\n")
    md.append("| 文件 | func | rpc | 行数 |")
    md.append("| --- | --- | --- | --- |")
    for i in largest_by_funcs:
        md.append(f"| `{i['rel']}` | {i['funcs']} | {i['rpc_funcs']} | {i['lines']} |")
    md.append("")

    md.append("## 使用 autoload 的脚本（部分，限依赖边）\n")
    used = [(e["from"], e["to"].split(":", 1)[1]) for e in dep_edges if e["type"] == "autoload"]
    if used:
        md.append("| 脚本 | 使用的 autoload |")
        md.append("| --- | --- |")
        seen = set()
        for frm, a in used:
            key = (frm, a)
            if key in seen:
                continue
            seen.add(key)
            md.append(f"| `{frm}` | `{a}` |")
    else:
        md.append("_（未检测到 autoload 使用）_")
    md.append("")

    md.append("----\n")
    md.append("_本文件由 `tools/gdscript_codemap.py` 生成，重新运行该脚本即可刷新。_")

    os.makedirs(os.path.dirname(args.out_md) or ".", exist_ok=True)
    with open(args.out_md, "w", encoding="utf-8") as f:
        f.write("\n".join(md) + "\n")
    print(f"[INFO] 报告已写出：{args.out_md}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
