extends Node

enum ImpactIntensity {LOW, MEDIUM, HIGH}

signal impact_felt(intensity: ImpactIntensity)
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

## 经营 HUD（吧台互动唤出的 tavern_ui）显隐信号。
## 由 TavernInterior.toggle_tavern_hud 发射，CombatHUD 监听后整层隐藏，
## 避免战斗 UI 泄露到经营界面上方、其边角 Control 拦截经营面板的鼠标点击。
signal tavern_hud_visibility_changed(is_visible: bool)

## 玩家攻击命中敌人信号：传递 { "damage": int, "is_crit": bool }，由准心 UI 监听以触发 Hitmarker 效果
signal player_hit_enemy(hit_data: Dictionary)
