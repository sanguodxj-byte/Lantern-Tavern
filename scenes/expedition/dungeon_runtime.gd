## DungeonRuntime — 地牢探险运行时模块（评审建议 D 阶段）。
#
# 职责：接管 ProceduralDungeon 的运行时行为——
#   spawn player / spawn enemies / spawn items
#   mount HUD / setup exploration pressure / connect extraction
#   handle overtime / handle extraction
#
# 不负责：生成地图 / 创建墙体 / 计算危险地形 / 管理 chunk / 读取 JSON / 管理酒馆仓库
#
# 严格约束：
#   - 不重新规划布局（layout 已含 spawn specs）
#   - 不创建地形节点（builder 已产 build_result）
#   - 不管理 streaming（controller 已接管）
#   - 信号接线（extraction_requested.connect / pressure.pressure_changed.connect）属本模块范畴
#
# 本会话先建框架 + 接口声明，真迁移放下回合（保 procedural 旧路径不破，避免单回合高风险大改）。
class_name DungeonRuntime
extends Node

# 配置（由 ProceduralDungeon._ready 注入）
var layout: DungeonLayout = null
var build_result: DungeonBuildResult = null
var expedition_finished: bool = false

## 配置：注入 layout + build_result，准备 runtime 启动。
func configure(p_layout: DungeonLayout, p_build_result: DungeonBuildResult) -> void:
	layout = p_layout
	build_result = p_build_result

## 启动 runtime：spawn player/enemies/items + mount HUD + setup pressure + connect extraction。
## 真迁移放下回合——本框架版暂空，procedural 仍持旧路径。
func start() -> void:
	pass

## 停止 runtime：handle extraction/overtime 收尾。
func stop() -> void:
	expedition_finished = true
