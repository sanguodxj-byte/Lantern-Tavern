class_name DungeonRoomFocusPlanner
extends RefCounted

const KEY_CELL_LABELS := ["player_spawn_cell", "extraction_cell", "boss_cell", "stairs_cell", "reward_cell"]

func plan(layout: DungeonLayout) -> void:
	layout.room_focus_specs.clear()
	if layout == null or layout.is_empty():
		return
	for room_index in range(layout.rooms.size()):
		var room: Rect2i = layout.rooms[room_index]
		var focus_kind := _focus_kind_for_room(layout, room_index, room)
		if focus_kind.is_empty():
			continue
		var focus_cell := _pick_focus_cell(layout, room, focus_kind)
		if focus_cell.x < 0:
			continue
		layout.room_focus_specs.append({
			"focus_kind": focus_kind,
			"cell": focus_cell,
			"room_index": room_index,
		})

func _focus_kind_for_room(layout: DungeonLayout, room_index: int, room: Rect2i) -> String:
	if layout.room_roles.has("start") and room == (layout.room_roles["start"] as Rect2i):
		return ""
	if layout.room_roles.has("boss") and room == (layout.room_roles["boss"] as Rect2i):
		return "boss_altar"
	if layout.room_roles.has("stairs") and room == (layout.room_roles["stairs"] as Rect2i):
		return "stairs_shrine"
	if layout.room_roles.has("reward") and room == (layout.room_roles["reward"] as Rect2i):
		return "treasure_niche"
	if room_index < layout.room_metadata.size():
		match String(layout.room_metadata[room_index].get("theme", "")):
			"ritual":
				return "ritual_circle"
			"resource":
				return "resource_cluster"
			"pillars":
				return "guard_post"
			"mixed":
				return "battle_cross"
			"loot", "stash":
				return "treasure_niche"
	return "waystone"

func _pick_focus_cell(layout: DungeonLayout, room: Rect2i, focus_kind: String) -> Vector2i:
	var center := room.position + Vector2i(room.size.x / 2, room.size.y / 2)
	var candidates: Array[Vector2i] = [
		center,
		center + Vector2i(1, 0),
		center + Vector2i(-1, 0),
		center + Vector2i(0, 1),
		center + Vector2i(0, -1),
		room.position + Vector2i(1, 1),
	]
	for candidate in candidates:
		if not room.has_point(candidate) or not layout.is_floor_cell(candidate):
			continue
		if not _is_focus_cell_allowed(layout, room, candidate, focus_kind):
			continue
		return candidate
	return Vector2i(-1, -1)

func _is_focus_cell_allowed(layout: DungeonLayout, room: Rect2i, cell: Vector2i, focus_kind: String) -> bool:
	if int(layout.grid[cell.y][cell.x]) == 5:
		return false
	if room.size.x >= 5 and room.size.y >= 5 and not room.grow(-1).has_point(cell):
		return false
	for label in KEY_CELL_LABELS:
		var key_cell: Vector2i = layout.get(label)
		if not layout.is_key_cell_missing(key_cell) and key_cell == cell:
			return focus_kind == "boss_altar" and label != "boss_cell"
	for anchor in layout.hazard_anchors:
		if anchor.get("anchor_cell", Vector2i(-1, -1)) == cell:
			return false
	for spec in layout.enemy_spawn_specs:
		if spec.get("cell", Vector2i(-1, -1)) == cell:
			return false
	for spec in layout.item_spawn_specs:
		if spec.get("cell", Vector2i(-1, -1)) == cell:
			return false
	for spec in layout.chest_spawn_specs:
		if spec.get("cell", Vector2i(-1, -1)) == cell:
			return false
	return true
