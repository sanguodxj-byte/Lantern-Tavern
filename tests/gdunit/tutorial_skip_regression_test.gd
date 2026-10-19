extends GdUnitTestSuite
## 回归测试：开局选项"跳过教程"后，酒馆场景不得挂载教程弹窗；
## 选择"含教程"并完成 intro 进入酒馆时，必须挂载教程协调器。
## 修复背景：start_new_game(false) 与 complete_intro_and_enter_tavern()
## 的 tutorial_completed 均为 true，旧挂载条件无法区分二者，
## 导致跳过教程时教程弹窗（TutorialOverlayLayer）仍被挂载。

var _tm: Node
var _tutorial_active_before: bool
var _tutorial_completed_before: bool
var _name_confirmed_before: bool

func before_test() -> void:
	_tm = Engine.get_main_loop().root.get_node("TavernManager")
	_tutorial_active_before = _tm.tutorial_active
	_tutorial_completed_before = _tm.tutorial_completed
	_name_confirmed_before = _tm.has_confirmed_character_name

func after_test() -> void:
	_tm.tutorial_active = _tutorial_active_before
	_tm.tutorial_completed = _tutorial_completed_before
	_tm.has_confirmed_character_name = _name_confirmed_before


func _find_tutorial_overlay(tavern: Node) -> Node:
	# 协调器（无 class_name 的 script.new() 节点）是 tavern 的子节点，
	# TutorialOverlayLayer 挂在协调器之下，必须递归查找。
	return tavern.find_child("TutorialOverlayLayer", true, false)


func test_skip_tutorial_must_not_mount_tavern_tutorial() -> void:
	# 等价于主菜单"跳过教程"（start_new_game(false)）之后的状态
	_tm.tutorial_active = false
	_tm.tutorial_completed = true
	_tm.has_confirmed_character_name = false
	var tavern := load("res://scenes/tavern/tavern.tscn").instantiate() as Node3D
	add_child(tavern)
	await await_idle_frame()
	await await_idle_frame()
	assert_object(_find_tutorial_overlay(tavern)) \
		.override_failure_message("跳过教程后酒馆不得挂载教程弹窗（TutorialOverlayLayer）") \
		.is_null()
	tavern.queue_free()
	await await_idle_frame()


func test_with_tutorial_after_intro_mounts_tavern_tutorial() -> void:
	# 等价于 start_new_game(true) + complete_intro_and_enter_tavern() 之后的状态
	_tm.tutorial_active = true
	_tm.tutorial_completed = true
	_tm.has_confirmed_character_name = false
	var tavern := load("res://scenes/tavern/tavern.tscn").instantiate() as Node3D
	add_child(tavern)
	await await_idle_frame()
	await await_idle_frame()
	assert_object(_find_tutorial_overlay(tavern)) \
		.override_failure_message("含教程流程完成 intro 后应挂载酒馆教程协调器") \
		.is_not_null()
	tavern.queue_free()
	await await_idle_frame()


func test_tutorial_finished_clears_active_flag() -> void:
	# 教程收尾（取名确认/取消）必须把 tutorial_active 置回 false，
	# 否则酒馆重载会再次挂载教程。
	_tm.tutorial_active = true
	_tm.tutorial_completed = true
	_tm.has_confirmed_character_name = false
	var tavern := load("res://scenes/tavern/tavern.tscn").instantiate() as Node3D
	add_child(tavern)
	await await_idle_frame()
	await await_idle_frame()
	assert_object(_find_tutorial_overlay(tavern)) \
		.override_failure_message("含教程流程应挂载教程协调器") \
		.is_not_null()
	# 模拟教程完成：名称确认路径写入的最终状态
	_tm.tutorial_active = false
	_tm.has_confirmed_character_name = true
	tavern.queue_free()
	await await_idle_frame()
	# 重新进入酒馆：教程已收尾，不得再次挂载
	var tavern2 := load("res://scenes/tavern/tavern.tscn").instantiate() as Node3D
	add_child(tavern2)
	await await_idle_frame()
	await await_idle_frame()
	assert_object(_find_tutorial_overlay(tavern2)) \
		.override_failure_message("教程收尾后酒馆重载不得再次挂载教程弹窗") \
		.is_null()
	tavern2.queue_free()
	await await_idle_frame()
