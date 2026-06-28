extends Node

enum ImpactIntensity {LOW, MEDIUM, HIGH}

signal impact_felt(intensity: ImpactIntensity)
signal level_restarted()
signal player_hurt(player: Player)
signal player_dead()
