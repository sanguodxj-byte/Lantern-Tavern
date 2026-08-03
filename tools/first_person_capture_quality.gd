class_name FirstPersonCaptureQuality
extends RefCounted

## Deterministic image checks shared by first-person equipment review captures.
## Metrics are intentionally based on the flat review background so a successful
## render must contain a readable, safely framed, lit equipment silhouette.

const DEFAULT_BACKGROUND := Color("101722")
const DEFAULT_FOREGROUND_THRESHOLD := 0.055


static func configure_review_world(viewport: SubViewport) -> void:
	var environment_node := WorldEnvironment.new()
	environment_node.name = "FirstPersonReviewEnvironment"
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = DEFAULT_BACKGROUND
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.68, 0.75, 0.86)
	environment.ambient_light_energy = 1.05
	environment_node.environment = environment
	viewport.add_child(environment_node)

	var key_light := DirectionalLight3D.new()
	key_light.name = "FirstPersonReviewKeyLight"
	key_light.rotation_degrees = Vector3(-36.0, -32.0, 0.0)
	key_light.light_color = Color(1.0, 0.90, 0.76)
	key_light.light_energy = 2.45
	key_light.shadow_enabled = false
	viewport.add_child(key_light)

	var fill_light := DirectionalLight3D.new()
	fill_light.name = "FirstPersonReviewFillLight"
	fill_light.rotation_degrees = Vector3(-20.0, 140.0, 0.0)
	fill_light.light_color = Color(0.58, 0.72, 1.0)
	fill_light.light_energy = 1.05
	fill_light.shadow_enabled = false
	viewport.add_child(fill_light)

	var camera_fill := OmniLight3D.new()
	camera_fill.name = "FirstPersonReviewCameraFill"
	camera_fill.position = Vector3(0.24, 0.18, 0.10)
	camera_fill.light_color = Color(0.88, 0.93, 1.0)
	# A stronger camera-side fill keeps dark wood/leather faces readable without
	# making the equipment emissive or flattening the warm/cool key separation.
	camera_fill.light_energy = 2.45
	camera_fill.omni_range = 3.0
	camera_fill.omni_attenuation = 0.65
	camera_fill.shadow_enabled = false
	viewport.add_child(camera_fill)


static func analyze(
	image: Image,
	background: Color = DEFAULT_BACKGROUND,
	threshold: float = DEFAULT_FOREGROUND_THRESHOLD
) -> Dictionary:
	if image == null or image.is_empty():
		return _empty_metrics()
	var min_x := image.get_width()
	var min_y := image.get_height()
	var max_x := -1
	var max_y := -1
	var foreground_pixels := 0
	var luminance_sum := 0.0
	var background_rgb := Vector3(background.r, background.g, background.b)
	for y in image.get_height():
		for x in image.get_width():
			var color := image.get_pixel(x, y)
			if Vector3(color.r, color.g, color.b).distance_to(background_rgb) <= threshold:
				continue
			foreground_pixels += 1
			min_x = mini(min_x, x)
			min_y = mini(min_y, y)
			max_x = maxi(max_x, x)
			max_y = maxi(max_y, y)
			luminance_sum += color.r * 0.2126 + color.g * 0.7152 + color.b * 0.0722
	if foreground_pixels == 0:
		return _empty_metrics()
	var bounds := Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1)
	return {
		"foreground_pixels": foreground_pixels,
		"bounds": bounds,
		"mean_luminance": luminance_sum / float(foreground_pixels),
		"long_edge": maxi(bounds.size.x, bounds.size.y),
		"margins": Vector4(
			float(min_x),
			float(min_y),
			float(image.get_width() - 1 - max_x),
			float(image.get_height() - 1 - max_y)
		),
	}


static func validate(
	metrics: Dictionary,
	minimum_foreground_pixels: int = 1200,
	minimum_long_edge: int = 220,
	minimum_mean_luminance: float = 0.30,
	minimum_edge_margin: int = 12
) -> Array[String]:
	var issues: Array[String] = []
	var foreground_pixels := int(metrics.get("foreground_pixels", 0))
	if foreground_pixels < minimum_foreground_pixels:
		issues.append("foreground is missing or too small (%d px)" % foreground_pixels)
		return issues
	var long_edge := int(metrics.get("long_edge", 0))
	if long_edge < minimum_long_edge:
		issues.append("equipment silhouette is too small (%d px long edge)" % long_edge)
	var luminance := float(metrics.get("mean_luminance", 0.0))
	if luminance < minimum_mean_luminance:
		issues.append("equipment is underexposed (mean luminance %.3f)" % luminance)
	var margins: Vector4 = metrics.get("margins", Vector4.ZERO)
	if minf(minf(margins.x, margins.y), minf(margins.z, margins.w)) < float(minimum_edge_margin):
		issues.append("equipment touches capture safe edge (%s)" % margins)
	return issues


static func describe(metrics: Dictionary) -> String:
	return "pixels=%d bounds=%s luminance=%.3f margins=%s" % [
		int(metrics.get("foreground_pixels", 0)),
		str(metrics.get("bounds", Rect2i())),
		float(metrics.get("mean_luminance", 0.0)),
		str(metrics.get("margins", Vector4.ZERO)),
	]


static func _empty_metrics() -> Dictionary:
	return {
		"foreground_pixels": 0,
		"bounds": Rect2i(),
		"mean_luminance": 0.0,
		"long_edge": 0,
		"margins": Vector4.ZERO,
	}
