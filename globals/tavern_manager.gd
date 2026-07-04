extends Node

enum Phase { DAY_EXPEDITION, NIGHT_TAVERN }

var current_phase: int = Phase.DAY_EXPEDITION
var day: int = 1
var gold: int = 100

# Inventory of brewing materials collected
var inventory: Dictionary = {}

# Alias used by UI scripts
var materials_inventory: Dictionary:
	get:
		return inventory
	set(value):
		inventory = value

# Active brews waiting for sale (brewed previous night, available tonight)
var current_brews: Array = []

# Materials database with flavors
var materials_db: Dictionary = {
	"wild_glowcap": {"name": "Wild Glowcap", "type": "gather", "flavors": {"earthy": 3, "bitter": 1}},
	"frost_berry": {"name": "Frost Berry", "type": "gather", "flavors": {"sour": 2, "sweet": 4}},
	"fire_bloom": {"name": "Fire Bloom", "type": "gather", "flavors": {"spicy": 5}},
	"cave_lichen": {"name": "Cave Lichen", "type": "gather", "flavors": {"salty": 2, "earthy": 2}},
	"honeycomb": {"name": "Honeycomb", "type": "gather", "flavors": {"sweet": 5, "floral": 2}},
	"sweet_grass": {"name": "Sweet Grass", "type": "gather", "flavors": {"sweet": 2, "fresh": 3}},
	"bitter_root": {"name": "Bitter Root", "type": "gather", "flavors": {"bitter": 5}},
	"mountain_barley": {"name": "Mountain Barley", "type": "gather", "flavors": {"earthy": 4}},
	"witch_plum": {"name": "Witch Plum", "type": "gather", "flavors": {"sour": 4, "sweet": 1}},
	"shadow_lotus": {"name": "Shadow Lotus", "type": "gather", "flavors": {"umami": 3, "floral": 3}},
	"sunflower_seed": {"name": "Sunflower Seed", "type": "gather", "flavors": {"nutty": 3, "sweet": 1}},
	"ironwood_bark": {"name": "Ironwood Bark", "type": "gather", "flavors": {"woody": 4, "bitter": 2}},
	"amber_resin": {"name": "Amber Resin", "type": "gather", "flavors": {"sweet": 3, "smoky": 2}},
	"acid_grape": {"name": "Acid Grape", "type": "gather", "flavors": {"sour": 5}},
	"rock_salt": {"name": "Rock Salt", "type": "gather", "flavors": {"salty": 5}},
	"goblin_ear": {"name": "Goblin Ear", "type": "drop", "flavors": {"gaminess": 2, "bitter": 2}},
	"spider_poison_sac": {"name": "Spider Poison Sac", "type": "drop", "flavors": {"spicy": 4, "bitter": 3}},
	"slime_jelly": {"name": "Slime Jelly", "type": "drop", "flavors": {"sweet": 2, "fresh": 4}},
	"bat_wing": {"name": "Bat Wing", "type": "drop", "flavors": {"leathery": 2, "sour": 1}},
	"skeleton_dust": {"name": "Skeleton Dust", "type": "drop", "flavors": {"dry": 4, "earthy": 1}},
	"imp_horn_dust": {"name": "Imp Horn Dust", "type": "drop", "flavors": {"smoky": 4, "spicy": 2}},
}

# Brewing recipes
var brewing_recipes: Dictionary = {
	"glowberry_ale": {
		"name": "Glowcap Berry Ale",
		"required_ingredients": ["wild_glowcap", "frost_berry", "mountain_barley"],
		"rating_bonus": 50,
		"description": "A refreshing ale with a faint glow and icy chill."
	},
	"sweet_slime_nectar": {
		"name": "Sweet Slime Nectar",
		"required_ingredients": ["sweet_grass", "slime_jelly", "honeycomb"],
		"rating_bonus": 45,
		"description": "An incredibly thick and sweet nectar."
	},
	"goblin_bitter_brew": {
		"name": "Goblin Bitter Brew",
		"required_ingredients": ["goblin_ear", "bitter_root", "rock_salt"],
		"rating_bonus": 40,
		"description": "A strong, gamey brew with extreme bitterness."
	},
	"fiery_imp_infusion": {
		"name": "Fiery Imp Infusion",
		"required_ingredients": ["fire_bloom", "imp_horn_dust", "cave_lichen"],
		"rating_bonus": 60,
		"description": "Scorching hot demonic drink."
	},
	"shadow_lotus_tea": {
		"name": "Shadow Lotus Tea",
		"required_ingredients": ["shadow_lotus", "sweet_grass", "witch_plum"],
		"rating_bonus": 55,
		"description": "A high-meditation tea with floral aroma."
	}
}

func add_material(material_id: String, amount: int = 1):
	if amount <= 0:
		return
	inventory[material_id] = int(inventory.get(material_id, 0)) + amount

## 记录本局地牢撤离携带物品统计（供 procedural_dungeon._settle_extraction_loot 调用）
func record_expedition_loot(materials_count: int, weapons_count: int, shields_count: int) -> void:
	print("[TavernManager] Expedition loot recorded: %d materials, %d weapons, %d shields" % [materials_count, weapons_count, shields_count])

func remove_from_inventory(material_id: String, amount: int = 1) -> bool:
	if inventory.has(material_id) and inventory[material_id] >= amount:
		inventory[material_id] -= amount
		if inventory[material_id] == 0:
			inventory.erase(material_id)
		return true
	return false

# Brew a drink from ingredients
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
		
	# Check for recipe match
	var recipe_matched = ""
	var recipe_display_name = "Generic Brew"
	var rating_bonus = 0
	var rating_class = "C"
	
	for r_id in brewing_recipes:
		var recipe = brewing_recipes[r_id]
		var reqs = recipe["required_ingredients"]
		var match_count = 0
		var temp_ingredients = valid_ingredients.duplicate()
		for req in reqs:
			if req in temp_ingredients:
				temp_ingredients.erase(req)
				match_count += 1
		if match_count == reqs.size():
			recipe_matched = r_id
			recipe_display_name = recipe["name"]
			rating_bonus = recipe["rating_bonus"]
			break
			
	var quality = compute_drink_quality(drink_flavors)
	if recipe_matched != "":
		quality += int(rating_bonus / 10.0)
		
	if quality >= 12:
		rating_class = "SS"
	elif quality >= 8:
		rating_class = "S"
	elif quality >= 5:
		rating_class = "A"
	elif quality >= 3:
		rating_class = "B"
	else:
		rating_class = "C"
		
	var drink = {
		"ingredients": valid_ingredients,
		"flavors": drink_flavors,
		"quality": quality,
		"recipe_id": recipe_matched,
		"recipe_name": recipe_display_name,
		"rating_class": rating_class
	}
	current_brews.append(drink)
	return drink

func compute_drink_quality(flavors: Dictionary) -> int:
	var total_points = 0
	for f in flavors:
		total_points += flavors[f]
	return int(total_points / 2.0) + 1

# Extract from dungeon → go to tavern night phase
func extract_to_tavern():
	print("[TavernManager] Extraction! Day=%d Materials=%d" % [day, inventory.size()])
	current_phase = Phase.NIGHT_TAVERN
	get_tree().change_scene_to_file("res://scenes/tavern/tavern.tscn")

# Next day: go back to dungeon
func start_next_day():
	day += 1
	current_phase = Phase.DAY_EXPEDITION
	# Clear tonight's brews (they were sold)
	current_brews.clear()
	get_tree().change_scene_to_file("res://scenes/expedition/procedural_dungeon.tscn")
