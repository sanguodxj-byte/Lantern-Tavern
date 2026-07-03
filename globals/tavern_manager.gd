extends Node

enum Phase { DAY_EXPEDITION, NIGHT_TAVERN }
enum GamePhase { DAY_EXPEDITION, NIGHT_TAVERN }

var current_phase: GamePhase = GamePhase.DAY_EXPEDITION
var gold: int = 100

# Inventory of brewing materials collected
# Key: material_id (String), Value: quantity (int)
var inventory: Dictionary = {
	"wild_glowcap": 3,
	"frost_berry": 2,
	"sweet_grass": 5,
	"mountain_barley": 10
}

# Alias for materials_inventory used in UI scripts to prevent crashes
var materials_inventory: Dictionary:
	get:
		return inventory
	set(value):
		inventory = value

# Materials database with flavors
var materials_db: Dictionary = {
	"wild_glowcap": {"name": "野生荧光菇", "type": "gather", "flavors": {"earthy": 3, "bitter": 1}},
	"frost_berry": {"name": "霜冻浆果", "type": "gather", "flavors": {"sour": 2, "sweet": 4}},
	"fire_bloom": {"name": "烈焰花瓣", "type": "gather", "flavors": {"spicy": 5}},
	"cave_lichen": {"name": "洞穴苔藓", "type": "gather", "flavors": {"salty": 2, "earthy": 2}},
	"honeycomb": {"name": "野生蜂巢", "type": "gather", "flavors": {"sweet": 5, "floral": 2}},
	"sweet_grass": {"name": "甜心草", "type": "gather", "flavors": {"sweet": 2, "fresh": 3}},
	"bitter_root": {"name": "苦艾根", "type": "gather", "flavors": {"bitter": 5}},
	"mountain_barley": {"name": "高山大麦", "type": "gather", "flavors": {"earthy": 4}},
	"witch_plum": {"name": "女巫李", "type": "gather", "flavors": {"sour": 4, "sweet": 1}},
	"shadow_lotus": {"name": "暗影莲花", "type": "gather", "flavors": {"umami": 3, "floral": 3}},
	"sunflower_seed": {"name": "向日葵籽", "type": "gather", "flavors": {"nutty": 3, "sweet": 1}},
	"ironwood_bark": {"name": "铁木树皮", "type": "gather", "flavors": {"woody": 4, "bitter": 2}},
	"amber_resin": {"name": "琥珀树树脂", "type": "gather", "flavors": {"sweet": 3, "smoky": 2}},
	"acid_grape": {"name": "酸腺葡萄", "type": "gather", "flavors": {"sour": 5}},
	"rock_salt": {"name": "岩盐结晶", "type": "gather", "flavors": {"salty": 5}},
	"goblin_ear": {"name": "哥布林耳尖", "type": "drop", "flavors": {"gaminess": 2, "bitter": 2}},
	"spider_poison_sac": {"name": "蜘蛛毒囊", "type": "drop", "flavors": {"spicy": 4, "bitter": 3}},
	"slime_jelly": {"name": "史莱姆凝胶", "type": "drop", "flavors": {"sweet": 2, "fresh": 4}},
	"bat_wing": {"name": "蝙蝠翅膀", "type": "drop", "flavors": {"leathery": 2, "sour": 1}},
	"wolf_fang": {"name": "野狼犬齿", "type": "drop", "flavors": {"mineral": 2}},
	"boar_tusk": {"name": "野猪獠牙", "type": "drop", "flavors": {"earthy": 3}},
	"skeleton_dust": {"name": "白骨粉末", "type": "drop", "flavors": {"dry": 4, "earthy": 1}},
	"giant_rat_tail": {"name": "巨鼠尾巴", "type": "drop", "flavors": {"gaminess": 3, "bitter": 2}},
	"screaming_spores": {"name": "尖叫蕈孢子", "type": "drop", "flavors": {"spicy": 3, "umami": 4}},
	"imp_horn_dust": {"name": "小恶魔角粉", "type": "drop", "flavors": {"smoky": 4, "spicy": 2}},
	"troll_blood": {"name": "巨魔之血", "type": "drop", "flavors": {"metallic": 3, "salty": 2}},
	"zombie_flesh": {"name": "腐肉精华", "type": "drop", "flavors": {"pungent": 4, "bitter": 2}},
	"harpy_feather": {"name": "哈比羽毛粉", "type": "drop", "flavors": {"floral": 2, "fresh": 2}},
	"basilisk_scale": {"name": "蜥蜴人鳞片", "type": "drop", "flavors": {"salty": 3, "spicy": 1}},
	"drake_scale": {"name": "幼龙碎鳞", "type": "drop", "flavors": {"smoky": 5}}
}

# Active batch of beers brewed for tonight's sale
var current_brews: Array = []

func add_material(material_id: String, amount: int = 1):
	if material_id in materials_db:
		if inventory.has(material_id):
			inventory[material_id] += amount
		else:
			inventory[material_id] = amount
		print("Added to inventory: ", material_id, " x", amount)

func remove_from_inventory(material_id: String, amount: int = 1) -> bool:
	if inventory.has(material_id) and inventory[material_id] >= amount:
		inventory[material_id] -= amount
		if inventory[material_id] == 0:
			inventory.erase(material_id)
		return true
	return false

# Combine materials to brew a drink and return drink profile
func brew_drink(ingredients: Array) -> Dictionary:
	var drink_flavors = {}
	var valid_ingredients = []
	
	for ing in ingredients:
		if remove_from_inventory(ing, 1):
			valid_ingredients.append(ing)
			var m_data = materials_db[ing]
			for flavor in m_data["flavors"]:
				var val = m_data["flavors"][flavor]
				if drink_flavors.has(flavor):
					drink_flavors[flavor] += val
				else:
					drink_flavors[flavor] = val
	
	if valid_ingredients.is_empty():
		return {}
		
	var drink = {
		"ingredients": valid_ingredients,
		"flavors": drink_flavors,
		"quality": compute_drink_quality(drink_flavors)
	}
	current_brews.append(drink)
	return drink

func compute_drink_quality(flavors: Dictionary) -> int:
	var total_points = 0
	for f in flavors:
		total_points += flavors[f]
	return int(total_points / 2.0) + 1

# Start the night tavern management phase
func switch_to_night():
	current_phase = GamePhase.NIGHT_TAVERN
	print("Switched to Night Tavern Phase! Time to brew and serve.")

# Start the day expedition phase
func switch_to_day():
	current_phase = GamePhase.DAY_EXPEDITION
	print("Switched to Day Expedition Phase! Time to search, fight, and extract.")

# High-level entry point function for phase switching
func enter_phase(phase: int) -> void:
	if phase == Phase.DAY_EXPEDITION:
		current_phase = GamePhase.DAY_EXPEDITION
		get_tree().change_scene_to_file("res://scenes/expedition/procedural_dungeon.tscn")
	elif phase == Phase.NIGHT_TAVERN:
		current_phase = GamePhase.NIGHT_TAVERN
		get_tree().change_scene_to_file("res://scenes/ui/tavern_ui.tscn")
