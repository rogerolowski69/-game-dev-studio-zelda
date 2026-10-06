extends CanvasLayer
## The status bar across the top of the screen: overworld minimap, gem and key
## counters, the equipped item and the life hearts. Drawn by hand so every
## element lands on exact pixels.

const ICONS := preload("res://assets/ui/hud.png")
const SWORD_TEXTURE := preload("res://assets/sprites/sword.png")
const SIZE := Vector2(256, 48)
const BACKGROUND := Color("141420")
const MAP_ORIGIN := Vector2(14, 12)
const MAP_CELL := Vector2(14, 8)
const MAP_GAP := 2.0
const MAP_ROOMS := Vector2i(3, 3)
const HEARTS_ORIGIN := Vector2(170, 22)
const HEARTS_PER_ROW := 8

## Icon regions inside hud.png (8x8 cells).
const HEART_FULL := Rect2(0, 0, 8, 8)
const HEART_HALF := Rect2(8, 0, 8, 8)
const HEART_EMPTY := Rect2(16, 0, 8, 8)
const GEM := Rect2(24, 0, 8, 8)
const KEY := Rect2(32, 0, 8, 8)

var _room := Vector2i(1, 1)
var _in_overworld := true
var _visited := {}

@onready var panel: Control = $Panel


func _ready() -> void:
	panel.draw.connect(_draw_panel)
	for changed in [Game.gems_changed, Game.keys_changed, Game.sword_changed]:
		changed.connect(panel.queue_redraw.unbind(1))
	Game.hp_changed.connect(panel.queue_redraw.unbind(2))


func set_room(room: Vector2i, in_overworld: bool) -> void:
	_room = room
	_in_overworld = in_overworld
	if in_overworld:
		_visited[room] = true
	panel.queue_redraw()


func _draw_panel() -> void:
	var font := panel.get_theme_default_font()
	var font_size := panel.get_theme_default_font_size()
	panel.draw_rect(Rect2(Vector2.ZERO, SIZE), BACKGROUND)

	# Minimap: visited rooms are lighter; a dot marks the hero (gold inside the cave).
	for y in MAP_ROOMS.y:
		for x in MAP_ROOMS.x:
			var cell := Vector2i(x, y)
			var color := Color("5a5a72") if _visited.has(cell) else Color("2b2b45")
			panel.draw_rect(Rect2(_map_cell_origin(cell), MAP_CELL), color)
	var here := _room if _in_overworld else Vector2i(1, 1)
	var dot := Color("4ac8c8") if _in_overworld else Color("ffd648")
	panel.draw_rect(Rect2(_map_cell_origin(here) + MAP_CELL / 2.0 - Vector2(2, 2), Vector2(4, 4)), dot)

	# Counters
	panel.draw_texture_rect_region(ICONS, Rect2(70, 12, 8, 8), GEM)
	panel.draw_string(font, Vector2(80, 19), "x%03d" % Game.gems, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	panel.draw_texture_rect_region(ICONS, Rect2(70, 27, 8, 8), KEY)
	panel.draw_string(font, Vector2(80, 34), "x%d" % Game.keys, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)

	# Equipped item ("A" button slot)
	panel.draw_string(font, Vector2(125, 10), "A", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color("94b0c2"))
	panel.draw_rect(Rect2(118, 13, 20, 26), Color("3b5dc9"), false)
	if Game.has_sword:
		panel.draw_texture(SWORD_TEXTURE, Vector2(120, 18))

	# Life
	panel.draw_string(font, Vector2(186, 15), "-LIFE-", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color("ce3a3a"))
	var heart := 0
	for half in range(0, Game.max_hp, 2):
		var remaining := Game.hp - half
		var icon := HEART_FULL if remaining >= 2 else HEART_HALF if remaining == 1 else HEART_EMPTY
		var row := floorf(heart / float(HEARTS_PER_ROW))
		var pos := HEARTS_ORIGIN + Vector2((heart % HEARTS_PER_ROW) * 9, row * 9)
		panel.draw_texture_rect_region(ICONS, Rect2(pos, Vector2(8, 8)), icon)
		heart += 1


func _map_cell_origin(cell: Vector2i) -> Vector2:
	return MAP_ORIGIN + Vector2(cell) * (MAP_CELL + Vector2(MAP_GAP, MAP_GAP))
