extends SceneTree

# Standard SceneTree test runner for Godot 4.6+ headless testing of BSP

func _initialize() -> void:
	print("=========================================")
	print("Starting Headless BSP Unit Tests...")
	print("=========================================")
	
	# Instantiate safe mock autoloads dynamically to decouple complex dependencies
	var mock_game_events = Node.new()
	var ge_script = GDScript.new()
	ge_script.source_code = "extends Node\nsignal player_spawned\nsignal player_hurt\nsignal player_dead\nsignal level_restarted\nsignal shield_changed\nsignal weapon_changed\nsignal possible_action_changed\nsignal current_keys_changed"
	ge_script.reload()
	mock_game_events.set_script(ge_script)
	mock_game_events.name = "GameEvents"
	root.add_child(mock_game_events)

	var mock_game_state = Node.new()
	var gs_script = GDScript.new()
	gs_script.source_code = "extends Node\nvar player = null\nfunc register_player(p):\n\tplayer = p\nfunc has_key(c):\n\treturn false"
	gs_script.reload()
	mock_game_state.set_script(gs_script)
	mock_game_state.name = "GameState"
	root.add_child(mock_game_state)

	var mock_audio = Node.new()
	var audio_script = GDScript.new()
	audio_script.source_code = "extends Node\nfunc play(sound_name, node = null):\n\tprint('[MockAudio] playing: ', sound_name)"
	audio_script.reload()
	mock_audio.set_script(audio_script)
	mock_audio.name = "AudioManager"
	root.add_child(mock_audio)
	
	var mock_tavern = Node.new()
	var tavern_script = GDScript.new()
	tavern_script.source_code = "extends Node\nvar gold = 100\nvar inventory = {}\nvar materials_db = {}"
	tavern_script.reload()
	mock_tavern.set_script(tavern_script)
	mock_tavern.name = "TavernManager"
	root.add_child(mock_tavern)

	var wr_script = load("res://data/weapon_registry.gd")
	if wr_script:
		var wr = wr_script.new()
		wr.name = "WeaponRegistry"
		root.add_child(wr)
		print("[HeadlessTest] Loaded WeaponRegistry Autoload")
	# Load and instantiate the BSP room generator script
	var bsp_script = load("res://scenes/expedition/bsp_generator.gd")
	if not bsp_script:
		print("ERROR: Failed to load res://scenes/expedition/bsp_generator.gd")
		quit(1)
		return
		
	var bsp = bsp_script.new()
	if not bsp:
		print("ERROR: Failed to instantiate BSP_DungeonGenerator")
		quit(1)
		return
		
	# Run map generation
	print("Running BSP Generation Algorithm for a 30x30 dungeon...")
	var start_time = Time.get_ticks_msec()
	var map = bsp.generate_dungeon(30, 30)
	var heights = bsp.ceiling_heights
	var end_time = Time.get_ticks_msec()
	print("Map generation completed in ", end_time - start_time, " ms.")
	
	# Visual Height ASCII Render
	print("\n--- Visual ASCII Render of Ceiling Heights ---")
	# Mapping heights to representation: 2.4 -> 'c' (corridor), 3.0 -> '.' (small), 3.8 -> 'o' (medium), 4.6 -> 'O' (large), WALL -> '#'
	for y in range(30):
		var row_str = ""
		for x in range(30):
			var val = map[y][x]
			var h = heights[y][x]
			if val == 2:
				row_str += "# "
			elif h == 2.4:
				row_str += "c "
			elif h == 3.0:
				row_str += ". "
			elif h == 3.8:
				row_str += "o "
			elif h == 4.6:
				row_str += "O "
			else:
				row_str += "? "
		print(row_str)
	print("-------------------------------------------------\n")
	
	# Boundary Constraint Assertions
	print("Verifying Border Tile Constraints (WALL only)...")
	var border_checked = 0
	var border_passed = 0
	for y in range(30):
		for x in range(30):
			if x == 0 or x == 29 or y == 0 or y == 29:
				border_checked += 1
				var val = map[y][x]
				if val == 2:
					border_passed += 1
				else:
					print("FAIL: Border tile at (", x, ",", y, ") has invalid type: ", val)
					
	print("Border validation: ", border_passed, " / ", border_checked, " tiles passed.")
	
	# Connectivity Verification using BFS
	print("Verifying 100% Floor Tile Connectivity...")
	var start_x = -1
	var start_y = -1
	for y in range(30):
		for x in range(30):
			if map[y][x] == 1:
				start_x = x
				start_y = y
				break
		if start_x != -1:
			break
			
	var queue := [Vector2i(start_x, start_y)]
	var visited := {}
	visited[Vector2i(start_x, start_y)] = true
	var directions := [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]
	
	while queue.size() > 0:
		var curr = queue.pop_front()
		for dir in directions:
			var nx = curr.x + dir.x
			var ny = curr.y + dir.y
			if nx >= 0 and nx < 30 and ny >= 0 and ny < 30:
				if map[ny][nx] in [1, 3, 4, 5]:
					var pos = Vector2i(nx, ny)
					if not visited.has(pos):
						visited[pos] = true
						queue.append(pos)
						
	var isolated_found = false
	for y in range(30):
		for x in range(30):
			if map[y][x] in [1, 3, 4, 5]:
				var pos = Vector2i(x, y)
				if not visited.has(pos):
					print("FAIL: Isolated tile of type ", map[y][x], " found at (", x, ",", y, ")")
					isolated_found = true
					
	# Fix mock audio player singleton child dependencies check
	var am = root.get_node_or_null("AudioManager")
	if am:
		# Instantiating dummy AudioStreamPlayer3D
		var dummy_player = AudioStreamPlayer3D.new()
		dummy_player.name = "AudioStreamPlayer3D"
		dummy_player.unique_name_in_owner = true
		am.add_child(dummy_player)
		dummy_player.owner = am
		
	# Wait for 1 frame to ensure all dynamic nodes are fully active in tree
	await create_timer(0.1).timeout

	# Verify Chest Mechanics
	print("\nRunning Chest Mechanics Verification...")
	# Test Melee (by_interact = false)
	var parent_melee = Node.new()
	root.add_child(parent_melee)
	var chest_melee = load("res://scenes/props/chest/chest.gd").new()
	parent_melee.add_child(chest_melee)
	chest_melee.open_chest(false)
	var dropped_melee = parent_melee.get_child_count() - 1
	if dropped_melee != 1:
		print("FAIL: Melee chest drop count mismatch, got ", dropped_melee)
		quit(1)
		return
	parent_melee.queue_free()
	
	# Test Interact (by_interact = true)
	var parent_interact = Node.new()
	root.add_child(parent_interact)
	var chest_interact = load("res://scenes/props/chest/chest.gd").new()
	parent_interact.add_child(chest_interact)
	chest_interact.open_chest(true)
	var dropped_interact = parent_interact.get_child_count() - 1
	if dropped_interact < 3 or dropped_interact > 4:
		print("FAIL: Interact chest drop count mismatch, got ", dropped_interact)
		quit(1)
		return
	parent_interact.queue_free()
	print("Chest Verification: PASSED")

	# Verify CharacterPanel UI Components
	print("\nRunning CharacterPanel UI Verification...")
	var cp_scene = load("res://scenes/ui/character_panel.tscn")
	if not cp_scene:
		print("FAIL: Failed to load character_panel.tscn")
		quit(1)
		return
	var cp = cp_scene.instantiate()
	if not cp:
		print("FAIL: Failed to instantiate CharacterPanel")
		quit(1)
		return
		
	# Must add child to scene tree owner so unique name %SkillsList resolved
	root.add_child(cp)
	
	# Check skills container
	if not cp.skills_list or cp.skills_list.item_count != 4:
		print("FAIL: Skills list count mismatch or missing")
		quit(1)
		return
	cp.queue_free()
	print("CharacterPanel UI Verification: PASSED")

	if border_passed == border_checked and not isolated_found:
		print("\nSUCCESS: All BSP dungeon, chest, and UI assertions passed perfectly! (100% Success)")
		quit(0)
	else:
		print("\nFAILURE: Border, connectivity, or custom assertions failed!")
		quit(1)
