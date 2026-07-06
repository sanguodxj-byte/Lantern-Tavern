class_name PickupHint
extends InteractionHintBase
## 拾取提示悬浮窗。指向可拾取物品/素材时显示在物体右侧。
## text 由 player.gd 统一构建（含 [E] 前缀与物品名），此处原样显示。

func show_for_item(text: String, screen_position: Vector2, auto_position := true) -> void:
	show_hint(text, screen_position, auto_position)
