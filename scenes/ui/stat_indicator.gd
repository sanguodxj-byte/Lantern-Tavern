class_name StatIndicator
extends ColorRect

## 武器 / 盾牌 / 钥匙耐久度条 —— 远端旧版实现（取自 commit 77a30b1b）。
## 渲染宽度 168 像素（用 40..208 区域，108 像素是 ProgressBar 默认宽度）。
## 进度条采用 tick.png（条纹），颜色按百分比档 modulate 切换：
##   >75 亮绿 / >50 黄绿 / >25 暗橙 / 否则 暗红
## CombatHUD 通过 refresh(condition, max_condition) 推数据。

@onready var progress_bar: TextureRect = %ProgressBar


func refresh(current_value: int, max_value: int) -> void:
	if current_value <= 0:
		progress_bar.size.x = 0

	var prct := (float(current_value) / float(max_value)) * 100.0
	progress_bar.size.x = prct
	if prct > 75:
		progress_bar.modulate = Color.LIME_GREEN
	elif prct > 50:
		progress_bar.modulate = Color.GREEN_YELLOW
	elif prct > 25:
		progress_bar.modulate = Color.DARK_ORANGE
	else:
		progress_bar.modulate = Color.DARK_RED
