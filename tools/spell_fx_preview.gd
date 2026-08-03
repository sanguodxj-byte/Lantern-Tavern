extends SceneTree
const SpellFx := preload("res://fx/pixel_spell_fx.gd")
const OUT := "res://reports/ui_preview/spell_fx_1280x720.png"
func _init() -> void: call_deferred("_run")
func _run() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280,720)
	viewport.transparent_bg = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var world := Node3D.new()
	viewport.add_child(world)
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#080A10")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#404858")
	env.ambient_light_energy = 0.7
	environment.environment = env
	world.add_child(environment)
	var camera := Camera3D.new()
	camera.position = Vector3(0,0,5)
	world.add_child(camera)
	for entry in [
		{"imagery":"fireball","color":Color("#ff8c3a"),"phase":"hit","pos":Vector3(-1.5,0.8,0)},
		{"imagery":"chain_lightning","color":Color("#ffe45c"),"phase":"hit","pos":Vector3(0,0.8,0)},
		{"imagery":"poison_cloud","color":Color("#6fd98b"),"phase":"area","pos":Vector3(1.5,0.8,0)},
		{"imagery":"summon_portal","color":Color("#9d70cf"),"phase":"area","pos":Vector3(-0.8,-1.0,0)},
		{"imagery":"frost_barrier","color":Color("#75c7ff"),"phase":"cast","pos":Vector3(0.8,-1.0,0)},
	]:
		var event := {"imagery":entry.imagery,"color":entry.color,"phase":entry.phase}
		var fx := SpellFx.spawn(world,event,entry.pos,Vector3(0.25,0,-1))
		if fx != null: fx.set_process(false)
	await process_frame
	await process_frame
	var image := viewport.get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://reports/ui_preview"))
	var err := image.save_png(ProjectSettings.globalize_path(OUT))
	print("[SpellFxPreview] wrote %s" % OUT)
	quit(0 if err == OK else 1)
