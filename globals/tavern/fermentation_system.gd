extends Node
## 发酵时序系统（autoload: FermentationSystem）。
## 承载策划案《11-酿造时间时序与发酵博弈设计》全闭环：
## BrewingKeg 状态机 + 隔夜发酵 + 环境共振 + 陈酿桶位博弈。
## 依赖 BrewingData（口味加算）。

# 用 preload 脚本类访问静态常量与函数（autoload 名在编译期不可用）
const BD := preload("res://globals/tavern/brewing_data.gd")

# ============================================================================
# 1. Keg 状态机
# ============================================================================

enum KegState {
	EMPTY,        # 空桶，可下料
	FERMENTING,   # 发酵中（投入后第 1 天白天）
	READY,        # 发酵完成，可开缸取酒 或 选择陈酿
	AGING,        # 陈酿中（每 +1 天口味 +1，最多 3 天）
	AGED,         # 陈酿封顶（3 天到达，不再增长）
}

# 区域环境共振口味注入（策划案 11 §点子1）
# 注：策划案用"炎热"，BrewingData 无此键，映射到最接近的"温暖"
# 键用 BrewingData.Zone 枚举值（DUNGEON=0, FOREST=1, CAVES=2, GRAVEYARD=3, VOLCANO=4, RUINS=5）
const ZONE_RESONANCE: Dictionary = {
 4: {"温暖": 2, "辣口": 1},  # VOLCANO
 3: {"死寂": 2},             # GRAVEYARD
 5: {"清澈": 2, "寒凉": 1},  # RUINS
 0: {},                      # DUNGEON 无共振
 1: {},                      # FOREST 无共振
 2: {},                      # CAVES 无共振
}

# 陈酿上限（策划案 11 §点子2）
const AGING_MAX_DAYS: int = 3

class BrewingKeg:
	var state: int = KegState.EMPTY
	var ingredients: Dictionary = {}   # {material_id: count}
	var base_flavors: Dictionary = {}  # 下料时加算的口味（不含共振）
	var resonance_flavors: Dictionary = {} # 发酵期注入的共振口味
	var final_flavors: Dictionary = {} # 发酵完成时定型（base + resonance）
	var brew_day: int = -1             # 下料时的天数（day N）
	var ferment_complete_day: int = -1 # 发酵完成的天数（day N+1 白天结束）
	var aging_days: int = 0            # 已陈酿天数
	var recipe_id: String = ""         # 匹配的经典配方 id（空表示自定义）
	var recipe_name: String = ""       # 配方名（自定义则为 ""）
	var sealed: bool = false           # 是否封存陈酿中

# ============================================================================
# 2. 桶位管理
# ============================================================================

var kegs: Array[BrewingKeg] = []
var max_kegs: int = 1  # 酒馆 Lv1=1 桶，扩建可加

## 获取空桶数量
func free_keg_count() -> int:
	var count: int = 0
	for keg in kegs:
		if keg.state == KegState.EMPTY:
			count += 1
	return count

## 初始化桶位（酒馆升级时调用）
func setup_kegs(count: int) -> void:
	max_kegs = count
	kegs.clear()
	for i in range(count):
		kegs.append(BrewingKeg.new())

## 扩建增加桶位
func expand_kegs(additional: int) -> void:
	max_kegs += additional
	for i in range(additional):
		kegs.append(BrewingKeg.new())

# ============================================================================
# 3. 下料与发酵
# ============================================================================

## 夜晚下料。返回 keg 索引，-1 表示无空桶。
func start_brewing(ingredients: Dictionary, current_day: int) -> int:
	for i in range(kegs.size()):
		var keg: BrewingKeg = kegs[i]
		if keg.state != KegState.EMPTY:
			continue
		keg.state = KegState.FERMENTING
		keg.ingredients = ingredients.duplicate()
		keg.base_flavors = BD.compute_brew_flavors(ingredients)
		keg.resonance_flavors = {}
		keg.final_flavors = {}
		keg.brew_day = current_day
		keg.ferment_complete_day = current_day + 1
		keg.aging_days = 0
		keg.sealed = false
		# 匹配经典配方
		keg.recipe_id = BD.match_recipe(ingredients)
		if keg.recipe_id != "":
			keg.recipe_name = BD.get_recipe_name(keg.recipe_id)
		return i
	return -1

## 白天探索结束后调用：对发酵中的酒桶注入环境共振口味。
## zone = 玩家白天探索的区域（BrewingData.Zone 枚举）。
func apply_environment_resonance(zone: int) -> void:
	var resonance: Dictionary = ZONE_RESONANCE.get(zone, {})
	if resonance.is_empty():
		return
	for keg in kegs:
		if keg.state != KegState.FERMENTING:
			continue
		for flavor_name in resonance:
			keg.resonance_flavors[flavor_name] = \
				keg.resonance_flavors.get(flavor_name, 0) + resonance[flavor_name]

## 白天结束（进入夜晚前）调用：推进所有 keg 的时序。
## - FERMENTING → 计算 final_flavors（base + resonance），转 READY
## - AGING → +1 天，口味 +1，达 3 天转 AGED
func advance_day() -> void:
	for keg in kegs:
		match keg.state:
			KegState.FERMENTING:
				# 发酵完成，定型 final_flavors
				keg.final_flavors = keg.base_flavors.duplicate()
				for fn in keg.resonance_flavors:
					keg.final_flavors[fn] = keg.final_flavors.get(fn, 0) + keg.resonance_flavors[fn]
				keg.state = KegState.READY
			KegState.AGING:
				keg.aging_days += 1
				# 所有已存在口味 +1
				for fn in keg.final_flavors:
					keg.final_flavors[fn] += 1
				if keg.aging_days >= AGING_MAX_DAYS:
					keg.state = KegState.AGED
					keg.sealed = false

# ============================================================================
# 4. 开缸与陈酿
# ============================================================================

## 开缸取酒。返回 final_flavors（定型口味），空字典表示该桶不可开缸。
func open_keg(keg_index: int) -> Dictionary:
	if keg_index < 0 or keg_index >= kegs.size():
		return {}
	var keg: BrewingKeg = kegs[keg_index]
	# READY / AGING / AGED 都可开缸
	if keg.state != KegState.READY and keg.state != KegState.AGING and keg.state != KegState.AGED:
		return {}
	var result: Dictionary = keg.final_flavors.duplicate()
	var matched_recipe: String = keg.recipe_id
	# 清空酒桶
	keg.state = KegState.EMPTY
	keg.ingredients.clear()
	keg.base_flavors.clear()
	keg.resonance_flavors.clear()
	keg.final_flavors.clear()
	keg.brew_day = -1
	keg.ferment_complete_day = -1
	keg.aging_days = 0
	keg.recipe_id = ""
	keg.recipe_name = ""
	keg.sealed = false
	# 附带配方 id（通过返回值的元信息传递需调用方处理，这里返回口味）
	if matched_recipe != "":
		result["__recipe_id__"] = matched_recipe
	return result

## 选择陈酿（封存）。仅 READY 状态可转入陈酿。
func seal_for_aging(keg_index: int) -> bool:
	if keg_index < 0 or keg_index >= kegs.size():
		return false
	var keg: BrewingKeg = kegs[keg_index]
	if keg.state != KegState.READY:
		return false
	keg.state = KegState.AGING
	keg.sealed = true
	keg.aging_days = 0
	return true

# ============================================================================
# 5. 查询
# ============================================================================

## 获取酒桶状态描述（供 UI 指示灯）
func get_keg_status_text(keg_index: int) -> String:
	if keg_index < 0 or keg_index >= kegs.size():
		return "无效桶位"
	var keg: BrewingKeg = kegs[keg_index]
	match keg.state:
		KegState.EMPTY: return "空桶"
		KegState.FERMENTING: return "发酵中"
		KegState.READY: return "已熟成"
		KegState.AGING: return "陈酿中 (%d/%d)" % [keg.aging_days, AGING_MAX_DAYS]
		KegState.AGED: return "陈酿封顶"
	return "未知"

## 获取所有可开缸的酒桶索引（READY/AGING/AGED）
func get_openable_kegs() -> Array:
	var result: Array = []
	for i in range(kegs.size()):
		var s: int = kegs[i].state
		if s == KegState.READY or s == KegState.AGING or s == KegState.AGED:
			result.append(i)
	return result

## 获取所有发酵中（共振生效）的酒桶索引
func get_fermenting_kegs() -> Array:
	var result: Array = []
	for i in range(kegs.size()):
		if kegs[i].state == KegState.FERMENTING:
			result.append(i)
	return result
