extends Node
## Bakes dev/world_map.txt into the TileSet (assets/tiles/tileset.tres) and the
## world scene (scenes/world/world.tscn), using the atlas manifest written by
## tools/generate_assets.py. The map is validated first; a broken map is
## reported and nothing is written.
##
## Run headless:  godot --headless --path . res://dev/build_world.tscn

const MAP_PATH := "res://dev/world_map.txt"
const MANIFEST_PATH := "res://assets/tiles/tiles.json"
const TILESET_PATH := "res://assets/tiles/tileset.tres"
const WORLD_PATH := "res://scenes/world/world.tscn"
const ROOM := Vector2i(16, 11)
const OVERWORLD_ROOMS := Vector2i(3, 3)
const CAVE_ROOM := Vector2i(4, 1)
const CELL := 16

const GATE := preload("res://scenes/objects/locked_gate.tscn")
const PICKUP := preload("res://scenes/objects/pickup.tscn")
const SAGE := preload("res://scenes/objects/sage.tscn")
const FIRE := preload("res://scenes/objects/fire.tscn")
const WARP := preload("res://scenes/objects/warp.tscn")

## Terrain character -> base tile name (variants are resolved in _tile_for).
const TERRAIN := {
	".": "grass", "\"": "flowers", "S": "sand", "T": "tree", "R": "rock", "M": "cliff",
	"W": "water", "C": "cave_entrance", "F": "stone_floor", "X": "stone_wall", "^": "statue",
	"H": "grave", "#": "cave_wall", ":": "cave_floor",
}
## Marker character -> terrain placed underneath when the neighbours disagree.
const MARKERS := {
	"P": ".", "s": ".", "o": ".", "K": ".", "@": ".", "G": "F", "*": "F",
	"N": ":", "f": ":", "w": ":", "A": ":", "E": ":",
}
## Marker character -> node name prefix in the baked scene.
const NODE_NAMES := {
	"s": "Spawn", "o": "Spawn", "K": "KeySpot", "N": "Sage", "f": "Fire", "w": "Sword", "C": "CaveDoor",
}
const WALKABLE_TERRAIN := ".\"SFC:"
const SOLID_MARKERS := "Nf"
const SIDES: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]

var _grid := {}      # Vector2i -> map character, in row-major order
var _terrain := {}   # Vector2i -> terrain character (markers resolved)
var _errors: PackedStringArray = []


func _ready() -> void:
	var sections := _read_sections(FileAccess.get_file_as_string(MAP_PATH))
	_place(sections.get("overworld", []), Vector2i.ZERO, OVERWORLD_ROOMS * ROOM, "overworld")
	_place(sections.get("cave", []), CAVE_ROOM * ROOM, ROOM, "cave")
	if _errors.is_empty():
		_resolve_terrain()
		_validate()
	if not _errors.is_empty():
		for message in _errors:
			printerr("world_map: ", message)
		printerr("World NOT written: %d problem(s)." % _errors.size())
		get_tree().quit(1)
		return
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
	ResourceSaver.save(_build_tileset(manifest), TILESET_PATH)
	# Reload so the world references tileset.tres instead of embedding a copy.
	var tileset: TileSet = ResourceLoader.load(TILESET_PATH, "", ResourceLoader.CACHE_MODE_REPLACE)
	var world := _build_world(manifest, tileset)
	var packed := PackedScene.new()
	packed.pack(world)
	ResourceSaver.save(packed, WORLD_PATH)
	print("World written: %d tiles, %d objects, %d spawn markers -> %s" % [
		_terrain.size(), world.get_node("Objects").get_child_count(),
		world.get_node("Spawns").get_child_count(), WORLD_PATH])
	world.free()
	get_tree().quit()


# --------------------------------------------------------------- parsing

func _read_sections(text: String) -> Dictionary:
	var sections := {}
	var current := ""
	for line in text.split("\n"):
		line = line.strip_edges(false, true)
		# Comments are "# ..." lines; map rows never contain spaces (and cave walls are '#').
		if line.is_empty() or line == "#" or line.begins_with("# "):
			continue
		if line.begins_with("[") and line.ends_with("]"):
			current = line.substr(1, line.length() - 2)
			sections[current] = []
		elif current != "":
			sections[current].append(line)
	return sections


func _place(lines: Array, origin: Vector2i, size: Vector2i, label: String) -> void:
	if lines.size() != size.y:
		_errors.append("[%s] expected %d rows, found %d" % [label, size.y, lines.size()])
		return
	for y in lines.size():
		var line: String = lines[y]
		if line.length() != size.x:
			_errors.append("[%s] row %d is %d wide, expected %d" % [label, y, line.length(), size.x])
			continue
		for x in line.length():
			_grid[origin + Vector2i(x, y)] = line[x]


func _resolve_terrain() -> void:
	for cell: Vector2i in _grid:
		var ch: String = _grid[cell]
		if TERRAIN.has(ch):
			_terrain[cell] = ch
		elif MARKERS.has(ch):
			_terrain[cell] = _vote(cell, MARKERS[ch])
		else:
			_errors.append("unknown character '%s' at %s" % [ch, _where(cell)])


## A marker sits on whatever terrain most of its neighbours are.
func _vote(cell: Vector2i, fallback: String) -> String:
	var votes := {}
	for side in SIDES:
		var ch: String = _grid.get(cell + side, "")
		if TERRAIN.has(ch):
			votes[ch] = votes.get(ch, 0) + 1
	var best := fallback
	var best_votes: int = votes.get(fallback, 0)
	for ch: String in votes:
		if votes[ch] > best_votes:
			best = ch
			best_votes = votes[ch]
	return best


# ------------------------------------------------------------ validation

func _passable(cell: Vector2i) -> bool:
	return _terrain.has(cell) and _terrain[cell] in WALKABLE_TERRAIN and not _grid[cell] in SOLID_MARKERS


func _validate() -> void:
	for ch in ["P", "N", "w", "A", "@"]:
		if _cells_of(ch).size() != 1:
			_errors.append("expected exactly one '%s', found %d" % [ch, _cells_of(ch).size()])
	for ch in ["C", "E", "G", "*", "K"]:
		if _cells_of(ch).is_empty():
			_errors.append("map needs at least one '%s'" % ch)
	if not _errors.is_empty():
		return
	# Room seams: an opening on one side of an edge must be open on the other.
	for ry in OVERWORLD_ROOMS.y:
		for rx in OVERWORLD_ROOMS.x:
			var base := Vector2i(rx, ry) * ROOM
			if rx + 1 < OVERWORLD_ROOMS.x:
				for y in ROOM.y:
					var a := base + Vector2i(ROOM.x - 1, y)
					if _passable(a) != _passable(a + Vector2i.RIGHT):
						_errors.append("seam mismatch between %s and %s" % [_where(a), _where(a + Vector2i.RIGHT)])
			if ry + 1 < OVERWORLD_ROOMS.y:
				for x in ROOM.x:
					var a := base + Vector2i(x, ROOM.y - 1)
					if _passable(a) != _passable(a + Vector2i.DOWN):
						_errors.append("seam mismatch between %s and %s" % [_where(a), _where(a + Vector2i.DOWN)])
	# The overworld's outer edge must be solid all the way round.
	var size := OVERWORLD_ROOMS * ROOM
	for x in size.x:
		for y in [0, size.y - 1]:
			if _passable(Vector2i(x, y)):
				_errors.append("hole in the world edge at %s" % _where(Vector2i(x, y)))
	for y in size.y:
		for x in [0, size.x - 1]:
			if _passable(Vector2i(x, y)):
				_errors.append("hole in the world edge at %s" % _where(Vector2i(x, y)))
	# Reachability: the key must be reachable without the gate; everything else with it.
	var start: Vector2i = _cells_of("P")[0]
	var before_gate := _flood(start, false)
	for cell in _cells_of("K"):
		if not before_gate.has(cell):
			_errors.append("key at %s can't be reached without opening the gate" % _where(cell))
	var everything := _flood(start, true)
	for ch in ["s", "o", "K", "w", "*", "A"]:
		for cell in _cells_of(ch):
			if not everything.has(cell):
				_errors.append("'%s' at %s is unreachable" % [ch, _where(cell)])


func _flood(start: Vector2i, gate_open: bool) -> Dictionary:
	var seen := {start: true}
	var queue: Array[Vector2i] = [start]
	var cave_arrival: Vector2i = _cells_of("A")[0]
	var world_arrival: Vector2i = _cells_of("@")[0]
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_front()
		var next: Array[Vector2i] = []
		for side in SIDES:
			var n := cell + side
			if _passable(n) and (gate_open or _grid[n] != "G"):
				next.append(n)
		if _grid[cell] == "C":
			next.append(cave_arrival)
		elif _grid[cell] == "E":
			next.append(world_arrival)
		for n in next:
			if not seen.has(n):
				seen[n] = true
				queue.append(n)
	return seen


# -------------------------------------------------------------- building

func _build_tileset(manifest: Dictionary) -> TileSet:
	var tileset := TileSet.new()
	tileset.tile_size = Vector2i(CELL, CELL)
	tileset.add_physics_layer()
	tileset.set_physics_layer_collision_layer(0, 1)  # "world"
	tileset.set_physics_layer_collision_mask(0, 0)
	var atlas := TileSetAtlasSource.new()
	atlas.texture = load(manifest["texture"])
	atlas.texture_region_size = Vector2i(CELL, CELL)
	tileset.add_source(atlas, 0)
	var tiles: Dictionary = manifest["tiles"]
	for tile_name: String in tiles:
		var info: Dictionary = tiles[tile_name]
		var coords := _atlas_coords(info)
		atlas.create_tile(coords)
		if info.has("frames"):
			atlas.set_tile_animation_frames_count(coords, int(info["frames"]))
			for frame in int(info["frames"]):
				atlas.set_tile_animation_frame_duration(coords, frame, float(info["frame_duration"]))
		if info["solid"]:
			var data := atlas.get_tile_data(coords, 0)
			data.add_collision_polygon(0)
			data.set_collision_polygon_points(0, 0, _collision_shape(info["shape"]))
	return tileset


func _collision_shape(kind: String) -> PackedVector2Array:
	var h := CELL / 2.0
	if kind == "chamfer":  # trees and rocks: cut corners let the hero slide past
		var c := 3.0
		return PackedVector2Array([Vector2(-h + c, -h), Vector2(h - c, -h), Vector2(h, -h + c), Vector2(h, h - c),
			Vector2(h - c, h), Vector2(-h + c, h), Vector2(-h, h - c), Vector2(-h, -h + c)])
	return PackedVector2Array([Vector2(-h, -h), Vector2(h, -h), Vector2(h, h), Vector2(-h, h)])


func _build_world(manifest: Dictionary, tileset: TileSet) -> Node2D:
	var world := Node2D.new()
	world.name = "World"
	var ground := TileMapLayer.new()
	ground.name = "Ground"
	ground.tile_set = tileset
	_add(world, world, ground)
	var tiles: Dictionary = manifest["tiles"]
	for cell: Vector2i in _terrain:
		ground.set_cell(cell, 0, _atlas_coords(tiles[_tile_for(cell)]))

	var objects := Node2D.new()
	objects.name = "Objects"
	objects.y_sort_enabled = true
	_add(world, world, objects)
	var spawns := Node2D.new()
	spawns.name = "Spawns"
	_add(world, world, spawns)

	var start := Marker2D.new()
	start.name = "PlayerStart"
	start.position = _center(_cells_of("P")[0])
	_add(world, world, start)

	var cave_arrival := _center(_cells_of("A")[0])
	var world_arrival := _center(_cells_of("@")[0])
	var counts := {}
	for cell: Vector2i in _grid:
		var ch: String = _grid[cell]
		var node: Node2D = null
		var parent := objects
		match ch:
			"s", "o":
				node = Marker2D.new()
				node.set_meta(&"enemy", "slime" if ch == "s" else "spitter")
				parent = spawns
			"K":
				node = Marker2D.new()
				node.set_meta(&"key", true)
				parent = spawns
			"N":
				node = _instance(SAGE)
			"f":
				node = _instance(FIRE)
			"w":
				node = _instance(PICKUP)
				node.kind = Pickup.Kind.SWORD
			"C":
				node = _instance(WARP)
				node.target = cave_arrival
				node.arrive_facing = Vector2i.UP
		if node:
			var base: String = NODE_NAMES[ch]
			counts[base] = counts.get(base, 0) + 1
			node.name = base if base in ["Sage", "Sword"] else "%s%02d" % [base, counts[base]]
			node.position = _center(cell)
			_add(world, parent, node)
	for group in _groups("G"):
		var gate: Node2D = _instance(GATE)
		gate.name = "ShrineGate"
		gate.position = _group_center(group)
		_add(world, objects, gate)
	for group in _groups("*"):
		var relic: Pickup = _instance(PICKUP)
		relic.name = "Sunstone"
		relic.kind = Pickup.Kind.RELIC
		relic.position = _group_center(group)
		_add(world, objects, relic)
	for group in _groups("E"):
		var exit: Node2D = _instance(WARP)
		exit.name = "CaveExit"
		exit.position = _group_center(group)
		exit.target = world_arrival
		exit.arrive_facing = Vector2i.DOWN
		exit.size = Vector2(_group_extent(group).x * CELL - 2, 14)
		_add(world, objects, exit)
	return world


## Instance with edit state so packing stores only the properties we change,
## not a frozen copy of every property of the sub-scene.
func _instance(scene: PackedScene) -> Node2D:
	return scene.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)


func _add(owner_root: Node, parent: Node, node: Node) -> void:
	parent.add_child(node)
	node.owner = owner_root


func _tile_for(cell: Vector2i) -> String:
	var ch: String = _terrain[cell]
	var h := posmod((cell.x * 73856093) ^ (cell.y * 19349663), 100)
	match ch:
		".":
			return "grass_0" if h < 70 else "grass_1" if h < 85 else "grass_2"
		"S":
			return "sand_%d" % (h % 2)
		"T":
			return "tree_%d" % (h % 2)
		"M":
			var below: String = _terrain.get(cell + Vector2i.DOWN, "M")
			return "cliff" if below in "MC" else "cliff_face"
		"W":
			var mask := 0
			for i in SIDES.size():  # bits: N=1 E=2 S=4 W=8, set where land borders the water
				var n: String = _terrain.get(cell + SIDES[i], "W")
				if n != "W":
					mask |= 1 << i
			return "water_%d" % mask
	return TERRAIN[ch]


func _atlas_coords(info: Dictionary) -> Vector2i:
	return Vector2i(int(info["atlas"][0]), int(info["atlas"][1]))


func _cells_of(ch: String) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for cell: Vector2i in _grid:
		if _grid[cell] == ch:
			cells.append(cell)
	return cells


## Connected (4-neighbour) groups of one marker, e.g. the two halves of the gate.
func _groups(ch: String) -> Array:
	var groups := []
	var seen := {}
	for cell in _cells_of(ch):
		if seen.has(cell):
			continue
		var group: Array[Vector2i] = []
		var stack: Array[Vector2i] = [cell]
		seen[cell] = true
		while not stack.is_empty():
			var c: Vector2i = stack.pop_back()
			group.append(c)
			for side in SIDES:
				var n := c + side
				if _grid.get(n, "") == ch and not seen.has(n):
					seen[n] = true
					stack.append(n)
		groups.append(group)
	return groups


func _center(cell: Vector2i) -> Vector2:
	return Vector2(cell * CELL) + Vector2(CELL, CELL) / 2.0


func _group_center(group: Array) -> Vector2:
	var sum := Vector2.ZERO
	for cell: Vector2i in group:
		sum += _center(cell)
	return sum / group.size()


func _group_extent(group: Array) -> Vector2i:
	var lo: Vector2i = group[0]
	var hi: Vector2i = group[0]
	for cell: Vector2i in group:
		lo = lo.min(cell)
		hi = hi.max(cell)
	return hi - lo + Vector2i.ONE


func _where(cell: Vector2i) -> String:
	var r := Vector2i(floori(cell.x / float(ROOM.x)), floori(cell.y / float(ROOM.y)))
	return "room %s tile (%d,%d)" % [r, cell.x - r.x * ROOM.x, cell.y - r.y * ROOM.y]
