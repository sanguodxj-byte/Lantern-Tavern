extends Node

enum ImpactIntensity {LOW, MEDIUM, HIGH}

signal impact_felt(intensity: ImpactIntensity)
signal level_restarted
signal player_dead
signal player_hurt(player: Player)
signal player_spawned(player: Player)
signal shield_changed(shield_data: ShieldData)
signal weapon_changed(weapon_data: WeaponData)
