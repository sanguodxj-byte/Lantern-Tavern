extends Node
## 运行时 60 FPS 性能预算控制器。
##
## 只调节可逆的视觉成本，不改变敌人数量、AI、命中、伤害或联机频率。
## 使用定长采样窗口、降级/升级滞回和最小保持时间，避免瞬时卡顿导致质量档抖动。

signal quality_tier_changed(tier: int, render_scale: float)

enum QualityTier { FULL, BALANCED, PERFORMANCE, EMERGENCY }

const TARGET_FRAME_MS := 1000.0 / 60.0
const SAMPLE_INTERVAL_SECONDS := 0.25
const WINDOW_SIZE := 20
const DEGRADE_FRAME_MS := 18.0
const EMERGENCY_FRAME_MS := 24.0
const RECOVER_FRAME_MS := 14.5
const DEGRADE_WINDOWS_REQUIRED := 2
const RECOVER_WINDOWS_REQUIRED := 8
const MIN_TIER_HOLD_SECONDS := 4.0
const RENDER_SCALES := [1.0, 0.9, 0.78, 0.67]

var quality_tier: int = QualityTier.FULL
var adaptive_enabled := true
var _sample_elapsed := 0.0
var _sample_frame_total_ms := 0.0
var _sample_frame_count := 0
var _tier_hold_elapsed := MIN_TIER_HOLD_SECONDS
var _slow_windows := 0
var _fast_windows := 0
var _frame_samples: Array[float] = []
var _last_window_average_ms := TARGET_FRAME_MS
## P1-2：视觉成本协调器实例（原始值快照随实例生命周期保存，变档只降不升/还原原始）。
var _visual_coordinator: VisualQualityCoordinator = null

func _ready() -> void:
	_apply_quality_tier(quality_tier, true)
	# P1（2331 审查）：场景切换后以【当前档位】重应用环境预算——新加载场景的环境雾/
	# 主光阴影不会因「档位未再变化」而保留高档成本。SceneTree 无 current_scene_changed
	# 信号，改在 _process 每帧对比当前场景引用（变化即重应用）。
	_last_known_scene = get_tree().current_scene if get_tree() != null else null

var _last_known_scene: Node = null

func _process(delta: float) -> void:
	if not adaptive_enabled or delta <= 0.0:
		return
	# P1（2331 审查）：场景切换检测——引用变化时用当前档位重应用环境预算。
	var tree := get_tree()
	var scene: Node = tree.current_scene if tree != null else null
	if scene != null and scene != _last_known_scene:
		_last_known_scene = scene
		if _visual_coordinator == null:
			_visual_coordinator = VisualQualityCoordinator.new()
		_visual_coordinator.apply_to_scene(scene, quality_tier)
	_tier_hold_elapsed += delta
	_sample_elapsed += delta
	_sample_frame_total_ms += delta * 1000.0
	_sample_frame_count += 1
	if _sample_elapsed < SAMPLE_INTERVAL_SECONDS:
		return
	var average_frame_ms := _sample_frame_total_ms / float(maxi(_sample_frame_count, 1))
	_sample_elapsed = 0.0
	_sample_frame_total_ms = 0.0
	_sample_frame_count = 0
	_record_frame_sample(average_frame_ms)

func submit_frame_time_ms(frame_ms: float) -> void:
	## 测试与平台探针入口；生产运行由 _process 自动采样。
	if not adaptive_enabled or frame_ms <= 0.0:
		return
	_record_frame_sample(frame_ms)

func set_adaptive_enabled(enabled: bool) -> void:
	adaptive_enabled = enabled
	if not enabled:
		_reset_window_counters()

func force_quality_tier(tier: int) -> void:
	_apply_quality_tier(clampi(tier, QualityTier.FULL, QualityTier.EMERGENCY), true)

func get_render_scale() -> float:
	return float(RENDER_SCALES[quality_tier])

func get_last_window_average_ms() -> float:
	return _last_window_average_ms

func _record_frame_sample(frame_ms: float) -> void:
	_frame_samples.append(frame_ms)
	if _frame_samples.size() < WINDOW_SIZE:
		return
	var total := 0.0
	for sample in _frame_samples:
		total += sample
	_last_window_average_ms = total / float(_frame_samples.size())
	_frame_samples.clear()
	_evaluate_window(_last_window_average_ms)

func _evaluate_window(average_ms: float) -> void:
	if average_ms >= EMERGENCY_FRAME_MS:
		_slow_windows += 2
		_fast_windows = 0
	elif average_ms >= DEGRADE_FRAME_MS:
		_slow_windows += 1
		_fast_windows = 0
	elif average_ms <= RECOVER_FRAME_MS:
		_fast_windows += 1
		_slow_windows = 0
	else:
		_slow_windows = 0
		_fast_windows = 0
	if _tier_hold_elapsed < MIN_TIER_HOLD_SECONDS:
		return
	if _slow_windows >= DEGRADE_WINDOWS_REQUIRED and quality_tier < QualityTier.EMERGENCY:
		_apply_quality_tier(quality_tier + 1)
	elif _fast_windows >= RECOVER_WINDOWS_REQUIRED and quality_tier > QualityTier.FULL:
		_apply_quality_tier(quality_tier - 1)

func _apply_quality_tier(tier: int, force: bool = false) -> void:
	var next_tier := clampi(tier, QualityTier.FULL, QualityTier.EMERGENCY)
	if not force and next_tier == quality_tier:
		return
	quality_tier = next_tier
	_tier_hold_elapsed = 0.0
	_reset_window_counters()
	var viewport := get_viewport()
	if viewport != null:
		viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR
		viewport.scaling_3d_scale = get_render_scale()
	# P1-2：视觉成本统一协调——环境雾/环境光/主光阴影跟随档位（只降不升、还原原始；
	# LightingController 自行订阅处理动态光源，二者互不重叠）。
	if _visual_coordinator == null:
		_visual_coordinator = VisualQualityCoordinator.new()
	_visual_coordinator.apply_to_scene(get_tree().current_scene, quality_tier)
	quality_tier_changed.emit(quality_tier, get_render_scale())

func _reset_window_counters() -> void:
	_frame_samples.clear()
	_sample_elapsed = 0.0
	_sample_frame_total_ms = 0.0
	_sample_frame_count = 0
	_slow_windows = 0
	_fast_windows = 0
