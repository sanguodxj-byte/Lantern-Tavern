# Lantern Tavern — GDScript 代码图谱 (CODEMAP)

> 自动生成于 2026-07-21T16:31:11.970791+00:00 ｜ 生成器：`tools/gdscript_codemap.py`

> **用途**：替代 GitNexus 等不支持 GDScript 的通用代码图谱工具，为本项目提供可查询的类继承 / 文件依赖 / autoload 使用视图，供改前影响分析。

## 概览

- 扫描 `.gd` 文件：**555**（仅首方代码）
- 声明 `class_name`：**148**
- `signal` 总数：**69** ｜ `func` 总数：**6586**（其中 `@rpc`：**9**）
- `const`：**1581** ｜ `var`：**13991**
- 依赖边（preload/extends/autoload）：**1024**
- Autoload 单例：**32**

## Autoload 单例注册表

| 名称 | 脚本路径 |
| --- | --- |
| `TavernManager` | `res://globals/tavern/tavern_manager.gd` |
| `NetworkManager` | `res://globals/core/network_manager.gd` |
| `MultiplayerSession` | `res://globals/multiplayer/multiplayer_session.gd` |
| `PerfMonitor` | `res://globals/perf/perf_monitor.gd` |
| `GameState` | `uid://cty2vqawfdqbw` |
| `GameEvents` | `uid://eiirh6kbcpec` |
| `HitStopServer` | `uid://d00ngek5c8h4c` |
| `FxHelper` | `uid://c20hdi30em2yo` |
| `AudioManager` | `res://globals/core/audio_manager.tscn` |
| `LocalizationManager` | `res://globals/core/localization_manager.gd` |
| `WeaponRegistry` | `res://data/weapon_registry.gd` |
| `SetPieceRegistry` | `res://data/set_piece_registry.gd` |
| `BrewingData` | `res://globals/tavern/brewing_data.gd` |
| `TavernSettlement` | `res://globals/tavern/tavern_settlement.gd` |
| `FermentationSystem` | `res://globals/tavern/fermentation_system.gd` |
| `LootTable` | `res://globals/tavern/loot_table.gd` |
| `ZoneManager` | `res://globals/dungeon/zone_manager.gd` |
| `CombatEngine` | `res://globals/combat/combat_engine.gd` |
| `SkillData` | `res://globals/combat/skill_data.gd` |
| `AttrPanel` | `res://globals/combat/attr_panel.gd` |
| `SkillRuntime` | `res://globals/combat/skill_runtime.gd` |
| `ActionSkills` | `res://globals/combat/action_skills.gd` |
| `SkillIcons` | `res://globals/combat/skill_icons.gd` |
| `DungeonSpawner` | `res://globals/dungeon/dungeon_spawner.gd` |
| `PhysicsSetup` | `res://globals/core/physics_setup.gd` |
| `ItemSpawner` | `res://globals/equipment/item_spawner.gd` |
| `AffixSystem` | `res://globals/equipment/affix_system.gd` |
| `ProjectileService` | `res://globals/combat/projectile_service.gd` |
| `LightingController` | `res://globals/lighting/lighting_controller.gd` |
| `Settings` | `res://globals/settings.gd` |
| `SaveManager` | `res://globals/core/save_manager.gd` |
| `UiNavigation` | `res://globals/ui/ui_navigation.gd` |

## 类继承（custom extends）

| 文件 | extends |
| --- | --- |
| `scenes/characters/enemies/state/enemy_state_blocking.gd` | `EnemyState` |
| `scenes/characters/enemies/state/enemy_state_dead.gd` | `EnemyState` |
| `scenes/characters/enemies/state/enemy_state_dying.gd` | `EnemyState` |
| `scenes/characters/enemies/state/enemy_state_hurt.gd` | `EnemyState` |
| `scenes/characters/enemies/state/enemy_state_impaling.gd` | `EnemyState` |
| `scenes/characters/enemies/state/enemy_state_launched.gd` | `EnemyState` |
| `scenes/characters/enemies/state/enemy_state_moving.gd` | `EnemyState` |
| `scenes/characters/enemies/state/enemy_state_slashing.gd` | `EnemyState` |
| `scenes/characters/enemies/state/enemy_state_stunned.gd` | `EnemyState` |
| `scenes/characters/player/state/player_state_aiming.gd` | `PlayerState` |
| `scenes/characters/player/state/player_state_attack_preparing.gd` | `PlayerState` |
| `scenes/characters/player/state/player_state_blocking.gd` | `PlayerState` |
| `scenes/characters/player/state/player_state_charging.gd` | `PlayerState` |
| `scenes/characters/player/state/player_state_dying.gd` | `PlayerState` |
| `scenes/characters/player/state/player_state_grabbing.gd` | `PlayerState` |
| `scenes/characters/player/state/player_state_hurt.gd` | `PlayerState` |
| `scenes/characters/player/state/player_state_kicking.gd` | `PlayerState` |
| `scenes/characters/player/state/player_state_moving.gd` | `PlayerState` |
| `scenes/characters/player/state/player_state_picking_up.gd` | `PlayerState` |
| `scenes/characters/player/state/player_state_shooting.gd` | `PlayerState` |
| `scenes/characters/player/state/player_state_slashing.gd` | `PlayerState` |
| `scenes/characters/player/state/player_state_throwing.gd` | `PlayerState` |
| `scenes/expedition/procedural_dungeon.gd` | `BaseLevel` |
| `scenes/expedition/wfc_visual_test.gd` | `BaseLevel` |
| `scenes/ui/interact_hint.gd` | `InteractionHintBase` |
| `scenes/ui/lobby_menu.gd` | `UiScreen` |
| `scenes/ui/main_menu.gd` | `UiScreen` |
| `scenes/ui/model_viewer.gd` | `UiScreen` |
| `scenes/ui/pickup_hint.gd` | `InteractionHintBase` |
| `scenes/ui/settings_menu.gd` | `UiScreen` |
| `scenes/ui/zone_select.gd` | `UiScreen` |

## 被依赖最多的文件（改前重点排查）

| 文件 | 被依赖次数 |
| --- | --- |
| `globals/multiplayer/network_protocol.gd` | 34 |
| `tests/gdunit/support/voxel_model_test_support.gd` | 27 |
| `globals/core/service.gd` | 24 |
| `globals/visual/voxel_lighting_adapter.gd` | 21 |
| `data/character_model_tiers.gd` | 20 |
| `scenes/expedition/dungeon_layout.gd` | 18 |
| `scenes/expedition/dungeon_scene_builder.gd` | 18 |
| `scenes/characters/player/player.gd` | 18 |
| `globals/combat/combat_engine.gd` | 17 |
| `globals/combat/combat_bridge.gd` | 16 |
| `globals/tavern/brewing_data.gd` | 15 |
| `globals/combat/skill_data.gd` | 15 |
| `scenes/characters/player/state/player_state.gd` | 14 |
| `scenes/expedition/procedural_dungeon.gd` | 14 |
| `globals/combat/action_skills.gd` | 12 |

## 体量最大的文件（按行数）

| 文件 | 行数 | func | signal |
| --- | --- | --- | --- |
| `scenes/ui/tavern_equipment_panel.gd` | 1619 | 117 | 0 |
| `scenes/expedition/isaac_room_dungeon_generator.gd` | 1265 | 92 | 0 |
| `scenes/expedition/dungeon_scene_builder.gd` | 1173 | 60 | 0 |
| `scenes/props/voxel_prop.gd` | 1070 | 51 | 0 |
| `scenes/characters/player/player.gd` | 979 | 80 | 0 |
| `scenes/ui/model_viewer.gd` | 865 | 43 | 0 |
| `globals/multiplayer/session_root.gd` | 820 | 46 | 4 |
| `tests/gdunit/session_root_test.gd` | 781 | 63 | 0 |
| `tests/gdunit/voxel_prop_scene_test.gd` | 766 | 42 | 0 |
| `globals/equipment/item_spawner.gd` | 730 | 40 | 1 |
| `scenes/characters/enemies/enemy.gd` | 706 | 52 | 2 |
| `tests/gdunit/perf_optimization_test.gd` | 661 | 36 | 0 |
| `tests/gdunit/combat_hud_test.gd` | 659 | 57 | 0 |
| `tests/gdunit/procedural_dungeon_test.gd` | 639 | 35 | 0 |
| `tests/gdunit/view_model_test.gd` | 624 | 72 | 0 |

## 函数最多的文件（按 func 数）

| 文件 | func | rpc | 行数 |
| --- | --- | --- | --- |
| `scenes/ui/tavern_equipment_panel.gd` | 117 | 0 | 1619 |
| `scenes/expedition/isaac_room_dungeon_generator.gd` | 92 | 0 | 1265 |
| `scenes/characters/player/player.gd` | 80 | 0 | 979 |
| `tests/gdunit/view_model_test.gd` | 72 | 0 | 624 |
| `tests/gdunit/session_root_test.gd` | 63 | 0 | 781 |
| `scenes/expedition/dungeon_scene_builder.gd` | 60 | 0 | 1173 |
| `tests/gdunit/skill_runtime_test.gd` | 58 | 0 | 420 |
| `tests/gdunit/combat_hud_test.gd` | 57 | 0 | 659 |
| `scenes/characters/component/equipment_component.gd` | 52 | 0 | 495 |
| `scenes/characters/enemies/enemy.gd` | 52 | 0 | 706 |
| `globals/core/network_manager.gd` | 51 | 7 | 576 |
| `scenes/props/voxel_prop.gd` | 51 | 0 | 1070 |
| `globals/combat/skill_runtime.gd` | 49 | 0 | 607 |
| `tests/gdunit/projectile_service_test.gd` | 49 | 0 | 462 |
| `tests/gdunit/combat_engine_test.gd` | 47 | 0 | 435 |

## 使用 autoload 的脚本（部分，限依赖边）

| 脚本 | 使用的 autoload |
| --- | --- |
| `data/weapon_registry.gd` | `AttrPanel` |
| `data/weapon_registry.gd` | `SkillData` |
| `globals/combat/action_skills.gd` | `SkillData` |
| `globals/combat/attr_panel.gd` | `CombatEngine` |
| `globals/combat/combat_bridge.gd` | `CombatEngine` |
| `globals/combat/milestone_effects.gd` | `AttrPanel` |
| `globals/combat/projectile_service.gd` | `ProjectileService` |
| `globals/combat/skill_data.gd` | `CombatEngine` |
| `globals/combat/skill_runtime.gd` | `SkillData` |
| `globals/core/fx_helper.gd` | `GameState` |
| `globals/core/game_state.gd` | `GameEvents` |
| `globals/core/game_state.gd` | `WeaponRegistry` |
| `globals/core/hit_stop_server.gd` | `GameEvents` |
| `globals/core/player_context.gd` | `GameState` |
| `globals/core/state/save_game_adapter.gd` | `GameState` |
| `globals/core/state/save_game_adapter.gd` | `TavernManager` |
| `globals/dungeon/zone_manager.gd` | `BrewingData` |
| `globals/dungeon/zone_manager.gd` | `LootTable` |
| `globals/equipment/item_spawner.gd` | `BrewingData` |
| `globals/equipment/item_spawner.gd` | `PhysicsSetup` |
| `globals/multiplayer/multiplayer_scene_bridge.gd` | `GameState` |
| `globals/multiplayer/multiplayer_scene_bridge.gd` | `NetworkManager` |
| `globals/multiplayer/multiplayer_session.gd` | `NetworkManager` |
| `globals/multiplayer/player_registry.gd` | `GameState` |
| `globals/multiplayer/session_root.gd` | `GameState` |
| `globals/perf/perf_monitor.gd` | `NetworkManager` |
| `globals/tavern/fermentation_system.gd` | `BrewingData` |
| `globals/tavern/loot_table.gd` | `BrewingData` |
| `globals/tavern/loot_table.gd` | `ZoneManager` |
| `globals/tavern/tavern_manager.gd` | `BrewingData` |
| `globals/tavern/tavern_manager.gd` | `FermentationSystem` |
| `globals/tavern/tavern_settlement.gd` | `BrewingData` |
| `scenes/characters/component/equipment_component.gd` | `GameEvents` |
| `scenes/characters/component/equipment_component.gd` | `GameState` |
| `scenes/characters/component/equipment_component.gd` | `WeaponRegistry` |
| `scenes/characters/enemies/enemy.gd` | `AudioManager` |
| `scenes/characters/enemies/enemy.gd` | `CombatEngine` |
| `scenes/characters/enemies/enemy.gd` | `FxHelper` |
| `scenes/characters/enemies/enemy.gd` | `GameEvents` |
| `scenes/characters/enemies/enemy.gd` | `GameState` |
| `scenes/characters/enemies/enemy.gd` | `PhysicsSetup` |
| `scenes/characters/enemies/state/enemy_state_blocking.gd` | `AudioManager` |
| `scenes/characters/enemies/state/enemy_state_blocking.gd` | `FxHelper` |
| `scenes/characters/enemies/state/enemy_state_blocking.gd` | `GameEvents` |
| `scenes/characters/enemies/state/enemy_state_dying.gd` | `AudioManager` |
| `scenes/characters/enemies/state/enemy_state_dying.gd` | `FxHelper` |
| `scenes/characters/enemies/state/enemy_state_dying.gd` | `GameEvents` |
| `scenes/characters/enemies/state/enemy_state_hurt.gd` | `AudioManager` |
| `scenes/characters/enemies/state/enemy_state_hurt.gd` | `FxHelper` |
| `scenes/characters/enemies/state/enemy_state_hurt.gd` | `GameEvents` |
| `scenes/characters/enemies/state/enemy_state_impaling.gd` | `AudioManager` |
| `scenes/characters/enemies/state/enemy_state_impaling.gd` | `FxHelper` |
| `scenes/characters/enemies/state/enemy_state_impaling.gd` | `GameEvents` |
| `scenes/characters/enemies/state/enemy_state_slashing.gd` | `AudioManager` |
| `scenes/characters/enemies/state/enemy_state_slashing.gd` | `PhysicsSetup` |
| `scenes/characters/player/main_camera.gd` | `GameEvents` |
| `scenes/characters/player/player.gd` | `AudioManager` |
| `scenes/characters/player/player.gd` | `CombatEngine` |
| `scenes/characters/player/player.gd` | `FxHelper` |
| `scenes/characters/player/player.gd` | `GameEvents` |
| `scenes/characters/player/player.gd` | `PhysicsSetup` |
| `scenes/characters/player/player_aim_helper.gd` | `PhysicsSetup` |
| `scenes/characters/player/player_skill_dispatcher.gd` | `AudioManager` |
| `scenes/characters/player/player_skill_dispatcher.gd` | `FxHelper` |
| `scenes/characters/player/state/player_state_charging.gd` | `AudioManager` |
| `scenes/characters/player/state/player_state_dying.gd` | `AudioManager` |
| `scenes/characters/player/state/player_state_dying.gd` | `GameEvents` |
| `scenes/characters/player/state/player_state_dying.gd` | `GameState` |
| `scenes/characters/player/state/player_state_grabbing.gd` | `AudioManager` |
| `scenes/characters/player/state/player_state_grabbing.gd` | `GameState` |
| `scenes/characters/player/state/player_state_hurt.gd` | `AudioManager` |
| `scenes/characters/player/state/player_state_hurt.gd` | `FxHelper` |
| `scenes/characters/player/state/player_state_hurt.gd` | `GameEvents` |
| `scenes/characters/player/state/player_state_kicking.gd` | `AudioManager` |
| `scenes/characters/player/state/player_state_moving.gd` | `AudioManager` |
| `scenes/characters/player/state/player_state_picking_up.gd` | `AudioManager` |
| `scenes/characters/player/state/player_state_picking_up.gd` | `GameState` |
| `scenes/characters/player/state/player_state_picking_up.gd` | `WeaponRegistry` |
| `scenes/characters/player/state/player_state_shooting.gd` | `AudioManager` |
| `scenes/characters/player/state/player_state_slashing.gd` | `AudioManager` |
| `scenes/characters/player/state/player_state_slashing.gd` | `PhysicsSetup` |
| `scenes/door/door.gd` | `GameEvents` |
| `scenes/equipment/pickable_item.gd` | `GameState` |
| `scenes/equipment/pickable_item.gd` | `PhysicsSetup` |
| `scenes/equipment/projectile_entity.gd` | `AudioManager` |
| `scenes/equipment/projectile_entity.gd` | `FxHelper` |
| `scenes/equipment/projectile_entity.gd` | `PhysicsSetup` |
| `scenes/equipment/projectile_entity.gd` | `ProjectileService` |
| `scenes/equipment/thrown_item.gd` | `AudioManager` |
| `scenes/equipment/thrown_item.gd` | `GameState` |
| `scenes/equipment/thrown_item.gd` | `PhysicsSetup` |
| `scenes/expedition/dungeon_door.gd` | `PhysicsSetup` |
| `scenes/expedition/dungeon_generation_config.gd` | `BrewingData` |
| `scenes/expedition/dungeon_runtime.gd` | `AudioManager` |
| `scenes/expedition/dungeon_runtime.gd` | `GameState` |
| `scenes/expedition/dungeon_runtime.gd` | `TavernManager` |
| `scenes/expedition/dungeon_scene_builder.gd` | `PhysicsSetup` |
| `scenes/expedition/dungeon_spawn_planner.gd` | `DungeonSpawner` |
| `scenes/expedition/extraction_portal.gd` | `GameState` |
| `scenes/expedition/procedural_dungeon.gd` | `BrewingData` |
| `scenes/expedition/procedural_dungeon.gd` | `GameEvents` |
| `scenes/expedition/procedural_dungeon.gd` | `GameState` |
| `scenes/intro/new_game_intro.gd` | `GameEvents` |
| `scenes/intro/new_game_intro.gd` | `TavernManager` |
| `scenes/levels/base_level.gd` | `GameState` |
| `scenes/multiplayer/client_command_driver.gd` | `GameState` |
| `scenes/multiplayer/client_command_driver.gd` | `NetworkManager` |
| `scenes/multiplayer/dedicated_server.gd` | `MultiplayerSession` |
| `scenes/multiplayer/dedicated_server.gd` | `NetworkManager` |
| `scenes/multiplayer/dungeon_session_controller.gd` | `GameState` |
| `scenes/multiplayer/dungeon_session_controller.gd` | `NetworkManager` |
| `scenes/props/chest/chest.gd` | `BrewingData` |
| `scenes/props/chest/chest.gd` | `GameEvents` |
| `scenes/props/destructible_item.gd` | `AudioManager` |
| `scenes/props/destructible_item.gd` | `GameEvents` |
| `scenes/props/voxel_prop.gd` | `GameEvents` |
| `scenes/props/voxel_prop.gd` | `LightingController` |
| `scenes/tavern/customer_entity.gd` | `TavernSettlement` |
| `scenes/tavern/tavern_dungeon_entrance.gd` | `TavernManager` |
| `scenes/tavern/tavern_manager_node.gd` | `GameEvents` |
| `scenes/tavern/tavern_manager_node.gd` | `GameState` |
| `scenes/tavern/tavern_manager_node.gd` | `LightingController` |
| `scenes/tavern/tavern_manager_node.gd` | `TavernManager` |
| `scenes/tavern/tutorial_tavern_coordinator.gd` | `GameEvents` |
| `scenes/tavern/tutorial_tavern_coordinator.gd` | `TavernManager` |
| `scenes/ui/character_name_prompt.gd` | `TavernManager` |
| `scenes/ui/character_panel.gd` | `GameState` |
| `scenes/ui/character_panel.gd` | `TavernManager` |
| `scenes/ui/chest_loot_panel.gd` | `WeaponRegistry` |
| `scenes/ui/combat_hud.gd` | `GameEvents` |
| `scenes/ui/combat_log.gd` | `GameEvents` |
| `scenes/ui/core/ui_screen.gd` | `UiNavigation` |
| `scenes/ui/crosshair.gd` | `GameEvents` |
| `scenes/ui/crosshair.gd` | `PhysicsSetup` |
| `scenes/ui/enemy_health_bar.gd` | `PhysicsSetup` |
| `scenes/ui/expedition_hud.gd` | `GameState` |
| `scenes/ui/expedition_hud.gd` | `TavernManager` |
| `scenes/ui/fps_overlay.gd` | `Settings` |
| `scenes/ui/lobby_menu.gd` | `MultiplayerSession` |
| `scenes/ui/main_menu.gd` | `TavernManager` |
| `scenes/ui/model_viewer.gd` | `WeaponRegistry` |
| `scenes/ui/pause_menu.gd` | `UiNavigation` |
| `scenes/ui/save_load_panel.gd` | `SaveManager` |
| `scenes/ui/settings_menu.gd` | `Settings` |
| `scenes/ui/tavern_equipment_panel.gd` | `GameEvents` |
| `scenes/ui/tavern_equipment_panel.gd` | `GameState` |
| `scenes/ui/tavern_equipment_panel.gd` | `SkillRuntime` |
| `scenes/ui/tavern_equipment_panel.gd` | `WeaponRegistry` |
| `scenes/ui/tavern_hud.gd` | `TavernManager` |
| `scenes/ui/ui.gd` | `GameEvents` |
| `scenes/ui/zone_select.gd` | `TavernManager` |
| `scenes/world/world.gd` | `AudioManager` |
| `scenes/world/world.gd` | `GameEvents` |
| `scenes/world/world.gd` | `GameState` |
| `scenes/world/world.gd` | `Settings` |
| `tests/gdunit/base_level_test.gd` | `GameState` |
| `tests/gdunit/bugfix_equipment_panel_test.gd` | `GameState` |
| `tests/gdunit/bugfix_equipment_panel_test.gd` | `SkillRuntime` |
| `tests/gdunit/character_name_prompt_test.gd` | `TavernManager` |
| `tests/gdunit/chest_loot_panel_test.gd` | `GameEvents` |
| `tests/gdunit/chest_loot_panel_test.gd` | `GameState` |
| `tests/gdunit/chest_loot_panel_test.gd` | `TavernManager` |
| `tests/gdunit/chest_test.gd` | `PhysicsSetup` |
| `tests/gdunit/combat_bridge_test.gd` | `WeaponRegistry` |
| `tests/gdunit/combat_feel_test.gd` | `GameEvents` |
| `tests/gdunit/combat_hud_test.gd` | `PhysicsSetup` |
| `tests/gdunit/complete_tutorial_verification_test.gd` | `GameEvents` |
| `tests/gdunit/complete_tutorial_verification_test.gd` | `TavernManager` |
| `tests/gdunit/crosshair_aim_test.gd` | `GameEvents` |
| `tests/gdunit/current_level_null_test.gd` | `GameState` |
| `tests/gdunit/damage_number_test.gd` | `FxHelper` |
| `tests/gdunit/damage_number_test.gd` | `GameState` |
| `tests/gdunit/dark_erosion_dungeon_test.gd` | `GameState` |
| `tests/gdunit/death_screen_reset_test.gd` | `GameEvents` |
| `tests/gdunit/diagnostic_pickup_ui_test.gd` | `GameEvents` |
| `tests/gdunit/dungeon_decor_models_test.gd` | `PhysicsSetup` |
| `tests/gdunit/dungeon_door_test.gd` | `PhysicsSetup` |
| `tests/gdunit/dungeon_player_spawn_physics_regression_test.gd` | `PhysicsSetup` |
| `tests/gdunit/dungeon_runtime_behavior_test.gd` | `GameState` |
| `tests/gdunit/dungeon_session_multiplayer_test.gd` | `NetworkManager` |
| `tests/gdunit/dungeon_streaming_physics_test.gd` | `PhysicsSetup` |
| `tests/gdunit/enemy_detection_test.gd` | `GameState` |
| `tests/gdunit/enemy_detection_test.gd` | `PhysicsSetup` |
| `tests/gdunit/enemy_dying_defer_test.gd` | `GameState` |
| `tests/gdunit/entity_physics_test.gd` | `PhysicsSetup` |
| `tests/gdunit/equipment_transfer_test.gd` | `WeaponRegistry` |
| `tests/gdunit/expedition_failure_test.gd` | `GameEvents` |
| `tests/gdunit/expedition_failure_test.gd` | `GameState` |
| `tests/gdunit/extraction_loot_test.gd` | `GameState` |
| `tests/gdunit/extraction_loot_test.gd` | `TavernManager` |
| `tests/gdunit/fermentation_system_test.gd` | `BrewingData` |
| `tests/gdunit/fps_settings_test.gd` | `Settings` |
| `tests/gdunit/full_flow_integration_test.gd` | `TavernManager` |
| `tests/gdunit/game_events_autoload_test.gd` | `GameEvents` |
| `tests/gdunit/has_method_null_guard_test.gd` | `GameState` |
| `tests/gdunit/hit_feedback_ui_test.gd` | `GameEvents` |
| `tests/gdunit/interaction_hint_test.gd` | `GameEvents` |
| `tests/gdunit/lighting_controller_test.gd` | `LightingController` |
| `tests/gdunit/loot_table_test.gd` | `BrewingData` |
| `tests/gdunit/loot_table_test.gd` | `ZoneManager` |
| `tests/gdunit/main_camera_test.gd` | `GameEvents` |
| `tests/gdunit/main_menu_test.gd` | `TavernManager` |
| `tests/gdunit/main_menu_tutorial_flow_test.gd` | `TavernManager` |
| `tests/gdunit/network_manager_integration_test.gd` | `NetworkManager` |
| `tests/gdunit/new_game_intro_test.gd` | `GameEvents` |
| `tests/gdunit/new_game_intro_test.gd` | `TavernManager` |
| `tests/gdunit/perf_optimization_test.gd` | `GameState` |
| `tests/gdunit/perf_optimization_test.gd` | `PhysicsSetup` |
| `tests/gdunit/perf_optimization_test.gd` | `ProjectileService` |
| `tests/gdunit/pickable_item_collection_test.gd` | `GameState` |
| `tests/gdunit/pickable_item_collection_test.gd` | `TavernManager` |
| `tests/gdunit/player_null_safety_test.gd` | `GameEvents` |
| `tests/gdunit/player_weapon_input_test.gd` | `WeaponRegistry` |
| `tests/gdunit/procedural_dungeon_runtime_real_run_test.gd` | `AudioManager` |
| `tests/gdunit/procedural_dungeon_runtime_real_run_test.gd` | `GameState` |
| `tests/gdunit/procedural_dungeon_test.gd` | `PhysicsSetup` |
| `tests/gdunit/projectile_service_test.gd` | `PhysicsSetup` |
| `tests/gdunit/projectile_service_test.gd` | `ProjectileService` |
| `tests/gdunit/ui_architecture_test.gd` | `UiNavigation` |
| `tests/gdunit/viewer_panel_integration_test.gd` | `WeaponRegistry` |
| `tests/gdunit/weapon_registry_test.gd` | `WeaponRegistry` |
| `tests/gdunit/world_transition_test.gd` | `TavernManager` |
| `tests/gdunit/zone_select_test.gd` | `BrewingData` |
| `tests/integration/mp_avatar_test.gd` | `NetworkManager` |
| `tests/integration/mp_client.gd` | `NetworkManager` |
| `tests/integration/mp_dedicated_server_test.gd` | `NetworkManager` |
| `tests/integration/mp_dungeon_test.gd` | `GameState` |
| `tests/integration/mp_dungeon_test.gd` | `NetworkManager` |
| `tests/integration/mp_host.gd` | `NetworkManager` |

----

_本文件由 `tools/gdscript_codemap.py` 生成，重新运行该脚本即可刷新。_
