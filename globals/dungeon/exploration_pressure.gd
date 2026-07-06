class_name ExplorationPressure
extends Node

signal pressure_changed(snapshot: Dictionary)
signal extraction_decision_recommended(snapshot: Dictionary)
signal expedition_overtime(snapshot: Dictionary)

const ACTION_OPEN_DOOR := "open_door"
const ACTION_BREAK_DOOR := "break_door"
const START_HOUR := 10
const DEADLINE_HOUR := 18
const MINUTES_PER_HOUR := 60
const MAX_THREAT := 100.0
const RECOMMEND_THREAT := 55.0
const RECOMMEND_REMAINING_MINUTES := 90

@export var minutes_per_real_second := 1.0
@export var open_door_threat := 8.0
@export var break_door_threat := 18.0
@export var open_door_minutes := 18
@export var break_door_minutes := 32
@export var passive_threat_per_minute := 0.08

var elapsed_minutes := 0
var threat_level := 0.0
var opened_doors := 0
var broken_doors := 0
var _second_accumulator := 0.0
var _recommendation_sent := false
var _overtime_sent := false


func _ready() -> void:
	_emit_pressure_changed()


func _process(delta: float) -> void:
	if _overtime_sent:
		return
	_second_accumulator += maxf(delta, 0.0)
	var minutes_to_advance := int(floor(_second_accumulator * minutes_per_real_second))
	if minutes_to_advance <= 0:
		return
	_second_accumulator -= float(minutes_to_advance) / minutes_per_real_second
	advance_minutes(minutes_to_advance)


func record_door_action(action: String) -> void:
	match action:
		ACTION_BREAK_DOOR:
			broken_doors += 1
			_add_pressure(break_door_threat)
			advance_minutes(break_door_minutes)
		_:
			opened_doors += 1
			_add_pressure(open_door_threat)
			advance_minutes(open_door_minutes)


func advance_minutes(minutes: int) -> void:
	if minutes <= 0:
		return
	elapsed_minutes += minutes
	_add_pressure(float(minutes) * passive_threat_per_minute)
	_emit_pressure_changed()
	_check_decision_points()


func get_current_clock_minutes() -> int:
	return START_HOUR * MINUTES_PER_HOUR + elapsed_minutes


func get_deadline_clock_minutes() -> int:
	return DEADLINE_HOUR * MINUTES_PER_HOUR


func get_remaining_minutes() -> int:
	return maxi(0, get_deadline_clock_minutes() - get_current_clock_minutes())


func is_overtime() -> bool:
	return get_current_clock_minutes() >= get_deadline_clock_minutes()


func should_recommend_extraction() -> bool:
	return threat_level >= RECOMMEND_THREAT or get_remaining_minutes() <= RECOMMEND_REMAINING_MINUTES


func get_vision_range_multiplier() -> float:
	var ratio := threat_level / MAX_THREAT
	return clampf(1.0 - ratio * 0.45, 0.55, 1.0)


func get_environment_activity_multiplier() -> float:
	var ratio := threat_level / MAX_THREAT
	return clampf(1.0 + ratio * 0.75, 1.0, 1.75)


func get_pressure_band() -> String:
	if threat_level >= 75.0 or is_overtime():
		return "critical"
	if threat_level >= RECOMMEND_THREAT or get_remaining_minutes() <= RECOMMEND_REMAINING_MINUTES:
		return "leave_soon"
	if threat_level >= 30.0:
		return "tense"
	return "safe"


func make_snapshot() -> Dictionary:
	return {
		"elapsed_minutes": elapsed_minutes,
		"clock_minutes": get_current_clock_minutes(),
		"remaining_minutes": get_remaining_minutes(),
		"threat_level": threat_level,
		"pressure_band": get_pressure_band(),
		"vision_range_multiplier": get_vision_range_multiplier(),
		"environment_activity_multiplier": get_environment_activity_multiplier(),
		"opened_doors": opened_doors,
		"broken_doors": broken_doors,
		"should_extract": should_recommend_extraction(),
		"overtime": is_overtime(),
	}


func build_extraction_result(voluntary: bool) -> Dictionary:
	return {
		"arrival_minutes": get_current_clock_minutes(),
		"deadline_minutes": get_deadline_clock_minutes(),
		"missed_tavern": is_overtime(),
		"voluntary": voluntary,
		"threat_level": threat_level,
		"opened_doors": opened_doors,
		"broken_doors": broken_doors,
	}


func _add_pressure(amount: float) -> void:
	threat_level = clampf(threat_level + maxf(amount, 0.0), 0.0, MAX_THREAT)


func _check_decision_points() -> void:
	var snapshot := make_snapshot()
	if not _recommendation_sent and bool(snapshot["should_extract"]):
		_recommendation_sent = true
		extraction_decision_recommended.emit(snapshot)
	if not _overtime_sent and bool(snapshot["overtime"]):
		_overtime_sent = true
		expedition_overtime.emit(snapshot)


func _emit_pressure_changed() -> void:
	pressure_changed.emit(make_snapshot())
