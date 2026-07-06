extends Node

enum ImpactIntensity {LOW, MEDIUM, HIGH}

signal impact_felt(intensity: ImpactIntensity)
signal current_keys_changed(color: Door.KeyColor)
signal level_restarted
signal player_dead
signal player_hurt(player: Player)
signal player_spawned(player: Player)
signal item_detail_changed(detail: Dictionary, screen_position: Vector2)
signal subtitle_changed(text: String)
signal tutorial_hint_changed(text: String)
signal shield_changed(shield_data: Resource)
signal weapon_changed(weapon_data: WeaponData)
## 交互悬浮窗信号：hint_type="pickup"|"interact"|"chest"|"door"，空文本表示隐藏
signal interaction_hint_changed(hint_type: String, text: String, screen_position: Vector2)

## 宝箱交互开启信号：传递宝箱实例，由 UI 层接收并展示战利品面板
signal chest_opened(chest: Node)
