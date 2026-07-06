class_name InteractHint
extends InteractionHintBase
## 交互提示悬浮窗。指向可交互物体/宝箱/门时显示在物体右侧。
## text 由 player.gd 统一构建（含动作前缀与物体名），此处原样显示。

func show_for_object(text: String, screen_position: Vector2, auto_position := true) -> void:
	show_hint(text, screen_position, auto_position)
