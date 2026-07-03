extends SceneTree

# Standard SceneTree test runner for Godot 4.6 headless testing

func _init():
	print("=========================================")
	print("Starting Headless WFC Unit Tests...")
	print("=========================================")
	
	# Load and instantiate the WFC room generator script
	var wfc_script = load("res://scenes/expedition/wfc_generator.gd")
	if not wfc_script:
		print("ERROR: Failed to load res://scenes/expedition/wfc_generator.gd")
		quit(1)
		return
		
	var wfc = wfc_script.new()
	if not wfc:
		print("ERROR: Failed to instantiate WFC_RoomGenerator")
		quit(1)
		return
		
	# Run map collapsing
	print("Running WFC Collapse Algorithm for a 10x10 template dungeon room...")
	var start_time = Time.get_ticks_msec()
	var map = wfc.collapse_room()
	var end_time = Time.get_ticks_msec()
	print("Map collapse completed in ", end_time - start_time, " ms.")
	
	# Visual ASCII Render
	print("\n--- Visual ASCII Render of the Collapsed Room ---")
	var chars = {
		0: ".", # EMPTY
		1: " ", # FLOOR
		2: "#", # WALL
		3: "L", # LOOT
		4: "R", # RESOURCE
		5: "P"  # PILLAR
	}
	
	for y in range(10):
		var row_str = ""
		for x in range(10):
			var val = map[y][x]
			row_str += chars.get(val, "?") + " "
		print(row_str)
	print("-------------------------------------------------\n")
	
	# Boundary Constraint Assertions
	print("Verifying 36 Border Tile Constraints (WALL/EMPTY only)...")
	var border_checked = 0
	var border_passed = 0
	for y in range(10):
		for x in range(10):
			if x == 0 or x == 9 or y == 0 or y == 9:
				border_checked += 1
				var val = map[y][x]
				# Border tiles must be either WALL (2) or EMPTY (0)
				if val == 2 or val == 0:
					border_passed += 1
				else:
					print("FAIL: Border tile at (", x, ",", y, ") has invalid type: ", val)
					
	print("Border validation: ", border_passed, " / ", border_checked, " tiles passed.")
	
	if border_passed == border_checked:
		print("\nSUCCESS: All WFC unit tests and boundary assertions passed perfectly! (100% Success)")
		quit(0)
	else:
		print("\nFAILURE: Border assertions failed!")
		quit(1)
