extends TileMapLayer
class_name RuntimeTileMap
## Procedurally paints the Hearthholm town layout at runtime.
## Attaches to the GroundLayer TileMapLayer node and creates a TileSet
## with atlas sources from the generated pixel-art tilesets.

## Map dimensions in tiles.
const MAP_COLS: int = 80
const MAP_ROWS: int = 60
const TILE_SIZE: int = 32

## Atlas grid size (each tileset PNG is 128x128 = 4x4 tiles).
const ATLAS_COLS: int = 4
const ATLAS_ROWS: int = 4

## Source IDs assigned during TileSet creation.
var grass_source_id: int = -1
var cobble_source_id: int = -1
var buildings_source_id: int = -1


func _ready() -> void:
	_build_tileset()
	_paint_map()


## Build the TileSet with clean procedural retro-style tiles.
## Uses hand-crafted pixel patterns instead of AI-generated tilesets
## for a consistent classic RPG look (SNES/GBA style).
func _build_tileset() -> void:
	var ts := TileSet.new()
	ts.tile_size = Vector2i(TILE_SIZE, TILE_SIZE)

	grass_source_id = _add_retro_source(ts, "grass")
	cobble_source_id = _add_retro_source(ts, "cobble")
	buildings_source_id = _add_retro_source(ts, "building")

	tile_set = ts

	var parent_node := get_parent()
	if parent_node:
		var building_layer := parent_node.get_node_or_null("BuildingLayer") as TileMapLayer
		if building_layer:
			building_layer.tile_set = ts
		var deco_layer := parent_node.get_node_or_null("DecorationLayer") as TileMapLayer
		if deco_layer:
			deco_layer.tile_set = ts


## Create a 4x4 atlas of retro-style tiles for the given type.
func _add_retro_source(ts: TileSet, tile_type: String) -> int:
	var img := Image.create(128, 128, false, Image.FORMAT_RGBA8)

	for ty in range(ATLAS_ROWS):
		for tx in range(ATLAS_COLS):
			var tile_idx: int = ty * ATLAS_COLS + tx
			_draw_retro_tile(img, tx * TILE_SIZE, ty * TILE_SIZE, tile_type, tile_idx)

	var tex := ImageTexture.create_from_image(img)
	var source := TileSetAtlasSource.new()
	source.texture = tex
	source.texture_region_size = Vector2i(TILE_SIZE, TILE_SIZE)

	for y in range(ATLAS_ROWS):
		for x in range(ATLAS_COLS):
			source.create_tile(Vector2i(x, y))

	return ts.add_source(source)


## Draw a single 32x32 retro-style tile at the given position.
func _draw_retro_tile(img: Image, ox: int, oy: int, tile_type: String, variant: int) -> void:
	match tile_type:
		"grass":
			_draw_grass_tile(img, ox, oy, variant)
		"cobble":
			_draw_cobble_tile(img, ox, oy, variant)
		"building":
			_draw_building_tile(img, ox, oy, variant)


func _draw_grass_tile(img: Image, ox: int, oy: int, variant: int) -> void:
	# Base green with subtle noise.
	var base := Color(0.22, 0.52, 0.18)
	var light := Color(0.30, 0.60, 0.22)
	var dark := Color(0.16, 0.42, 0.12)
	var accent := Color(0.35, 0.65, 0.20)  # Bright grass blades

	for py in range(TILE_SIZE):
		for px in range(TILE_SIZE):
			var noise: int = ((px * 7 + py * 13 + variant * 37) % 10)
			var c: Color
			if noise < 5:
				c = base
			elif noise < 8:
				c = light
			else:
				c = dark
			img.set_pixel(ox + px, oy + py, c)

	# Scatter a few bright grass blade pixels.
	var rng_base: int = variant * 53
	for i in range(6):
		var bx: int = (rng_base + i * 17) % TILE_SIZE
		var by: int = (rng_base + i * 23 + 7) % TILE_SIZE
		img.set_pixel(ox + bx, oy + by, accent)
		if by + 1 < TILE_SIZE:
			img.set_pixel(ox + bx, oy + by + 1, accent)

	# Occasional tiny flower (on certain variants).
	if variant % 5 == 0:
		var fx: int = 10 + (variant * 3) % 14
		var fy: int = 10 + (variant * 7) % 14
		img.set_pixel(ox + fx, oy + fy, Color(0.9, 0.85, 0.2))  # Yellow
	elif variant % 7 == 0:
		var fx: int = 8 + (variant * 11) % 16
		var fy: int = 8 + (variant * 5) % 16
		img.set_pixel(ox + fx, oy + fy, Color(0.85, 0.3, 0.3))  # Red


func _draw_cobble_tile(img: Image, ox: int, oy: int, variant: int) -> void:
	# Gray cobblestone with stone pattern.
	var base := Color(0.55, 0.52, 0.48)
	var light := Color(0.65, 0.62, 0.58)
	var dark := Color(0.40, 0.38, 0.35)
	var grout := Color(0.32, 0.30, 0.28)  # Dark lines between stones

	# Fill base.
	for py in range(TILE_SIZE):
		for px in range(TILE_SIZE):
			var noise: int = ((px * 11 + py * 7 + variant * 31) % 8)
			if noise < 4:
				img.set_pixel(ox + px, oy + py, base)
			elif noise < 6:
				img.set_pixel(ox + px, oy + py, light)
			else:
				img.set_pixel(ox + px, oy + py, dark)

	# Draw stone grid lines (grout).
	var offset_x: int = (variant * 3) % 4
	var offset_y: int = (variant * 5) % 4
	for py in range(TILE_SIZE):
		for px in range(TILE_SIZE):
			var gx: int = (px + offset_x) % 8
			var gy: int = (py + offset_y) % 8
			# Horizontal grout every 8 pixels, vertical offset per row.
			if gy == 0 or gx == 0:
				img.set_pixel(ox + px, oy + py, grout)


func _draw_building_tile(img: Image, ox: int, oy: int, variant: int) -> void:
	var is_wall: bool = (variant < 8)  # First 2 rows = walls
	var is_roof: bool = (variant < 4)   # First row = roof

	if is_roof:
		# Dark brown roof shingles.
		var roof_base := Color(0.45, 0.25, 0.12)
		var roof_light := Color(0.55, 0.32, 0.16)
		for py in range(TILE_SIZE):
			for px in range(TILE_SIZE):
				var stripe: int = (py + variant * 3) % 6
				if stripe < 4:
					img.set_pixel(ox + px, oy + py, roof_base)
				else:
					img.set_pixel(ox + px, oy + py, roof_light)
	elif is_wall:
		# Wooden wall planks.
		var plank := Color(0.60, 0.42, 0.22)
		var plank_dark := Color(0.48, 0.32, 0.16)
		var plank_line := Color(0.38, 0.25, 0.12)
		for py in range(TILE_SIZE):
			for px in range(TILE_SIZE):
				var plank_row: int = py % 8
				if plank_row == 0:
					img.set_pixel(ox + px, oy + py, plank_line)
				elif (px + (py / 8) * 4) % 8 == 0:
					img.set_pixel(ox + px, oy + py, plank_line)
				elif plank_row < 3:
					img.set_pixel(ox + px, oy + py, plank)
				else:
					img.set_pixel(ox + px, oy + py, plank_dark)
	else:
		# Interior floor (lighter wood).
		var floor_base := Color(0.65, 0.50, 0.30)
		var floor_dark := Color(0.55, 0.40, 0.22)
		for py in range(TILE_SIZE):
			for px in range(TILE_SIZE):
				var board: int = px % 8
				if board == 0:
					img.set_pixel(ox + px, oy + py, Color(0.45, 0.32, 0.18))
				elif (px + py) % 7 < 4:
					img.set_pixel(ox + px, oy + py, floor_base)
				else:
					img.set_pixel(ox + px, oy + py, floor_dark)


## Paint the entire Hearthholm town map.
func _paint_map() -> void:
	# Step 1: Fill everything with grass.
	_fill_grass()

	# Step 2: Paint cobblestone roads and town square.
	_paint_roads()

	# Step 3: Paint building footprints on the BuildingLayer.
	_paint_buildings()


## Fill the entire map with grass tiles.
## Uses only 2-3 clean grass tiles to avoid visual chaos from the
## AI-generated tileset which has very different tiles per cell.
func _fill_grass() -> void:
	# Pick 2 clean tile coords from the grass atlas for variety.
	var grass_tiles: Array[Vector2i] = [
		Vector2i(2, 2),  # Cleanest solid green
		Vector2i(2, 3),  # Slight variation
		Vector2i(3, 2),  # Another variation
	]
	for row in range(MAP_ROWS):
		for col in range(MAP_COLS):
			# Simple hash to pick from our 3 clean tiles.
			var idx: int = ((col * 7 + row * 13) % grass_tiles.size())
			set_cell(Vector2i(col, row), grass_source_id, grass_tiles[idx])


## Paint cobblestone roads connecting key locations.
func _paint_roads() -> void:
	# Main north-south road (cols 47-49, full height).
	_fill_rect_cobble(47, 0, 3, MAP_ROWS)

	# East-west road through town center (rows 29-31, full width).
	_fill_rect_cobble(0, 29, MAP_COLS, 3)

	# Town square (cols 38-55, rows 25-35).
	_fill_rect_cobble(38, 25, 18, 11)

	# Northern gate plaza (cols 44-52, rows 0-5).
	_fill_rect_cobble(44, 0, 9, 6)

	# Southern gate plaza (cols 44-52, rows 55-60).
	_fill_rect_cobble(44, 55, 9, 5)

	# Road to Guild Hall - north from square (cols 45-51, rows 15-25).
	_fill_rect_cobble(45, 15, 7, 10)

	# Road west to Blacksmith (rows 29-31 already covered by E-W road).
	# Side road to Blacksmith (cols 27-35, rows 29-31) - already covered.

	# Road west to Inn area (cols 18-38, rows 44-46).
	_fill_rect_cobble(18, 44, 20, 3)

	# Road east to Apothecary (cols 55-70, rows 44-46).
	_fill_rect_cobble(55, 44, 15, 3)

	# Road south to Shrine (cols 47-49, rows 35-50) - already covered by N-S road.

	# Side path to Training Yard (cols 12-18, rows 54-56).
	_fill_rect_cobble(12, 54, 7, 3)

	# Path connecting Inn road to Training Yard.
	_fill_rect_cobble(15, 46, 3, 9)

	# Small plaza in front of Guild Hall (cols 44-52, rows 19-22).
	_fill_rect_cobble(44, 19, 9, 4)

	# Path to Farmer Aldric (cols 14-20, rows 24-26).
	_fill_rect_cobble(14, 24, 7, 3)
	# Connect farmer path to E-W road.
	_fill_rect_cobble(16, 26, 3, 4)


## Paint cobblestone tiles in a rectangular region.
## Uses only 2-3 clean cobblestone tiles to keep roads uniform.
func _fill_rect_cobble(start_col: int, start_row: int, width: int, height: int) -> void:
	var cobble_tiles: Array[Vector2i] = [
		Vector2i(0, 0),  # Main cobblestone
		Vector2i(1, 0),  # Slight variation
		Vector2i(0, 1),  # Another variation
	]
	for row in range(start_row, mini(start_row + height, MAP_ROWS)):
		for col in range(start_col, mini(start_col + width, MAP_COLS)):
			var idx: int = ((col * 3 + row * 11) % cobble_tiles.size())
			set_cell(Vector2i(col, row), cobble_source_id, cobble_tiles[idx])


## Paint building footprints on the BuildingLayer.
func _paint_buildings() -> void:
	var building_layer := get_parent().get_node_or_null("BuildingLayer") as TileMapLayer
	if not building_layer or buildings_source_id < 0:
		return

	# Guild Hall (centered around marker at 1488, 688 -> tile 46, 21).
	_paint_building(building_layer, 42, 17, 10, 6)

	# Blacksmith (marker at 992, 976 -> tile 31, 30).
	_paint_building(building_layer, 27, 27, 8, 5)

	# General Store / Merchant Marta (marker at 1888, 976 -> tile 59, 30).
	_paint_building(building_layer, 56, 27, 8, 5)

	# Inn - The Sleeping Gryphon (marker at 736, 1456 -> tile 23, 45).
	_paint_building(building_layer, 19, 42, 9, 6)

	# Apothecary / Alchemist Elara (marker at 2128, 1456 -> tile 66, 45).
	_paint_building(building_layer, 63, 42, 8, 5)

	# Shrine of the Ancients (marker at 1568, 1616 -> tile 49, 50).
	_paint_building(building_layer, 46, 48, 7, 5)

	# Training Yard fence area (marker at 528, 1808 -> tile 16, 56).
	_paint_building(building_layer, 13, 54, 8, 4)

	# Farmer's cottage (marker at 528, 816 -> tile 16, 25).
	_paint_building(building_layer, 13, 22, 6, 5)

	# Guard post at north gate (marker at 1552, 80 -> tile 48, 2).
	_paint_building(building_layer, 46, 1, 6, 3)

	# Mysterious Stranger's corner (marker at 2400, 1200 -> tile 75, 37).
	_paint_building(building_layer, 73, 35, 5, 4)


## Paint a building footprint rectangle on the given layer.
## Uses consistent wall and floor tiles for clean building appearance.
func _paint_building(layer: TileMapLayer, start_col: int, start_row: int, width: int, height: int) -> void:
	var wall_tile := Vector2i(0, 0)    # One clean wall tile
	var floor_tile := Vector2i(3, 3)   # One clean floor/interior tile
	for row in range(start_row, mini(start_row + height, MAP_ROWS)):
		for col in range(start_col, mini(start_col + width, MAP_COLS)):
			var is_edge: bool = (row == start_row or row == start_row + height - 1
				or col == start_col or col == start_col + width - 1)
			if is_edge:
				layer.set_cell(Vector2i(col, row), buildings_source_id, wall_tile)
			else:
				layer.set_cell(Vector2i(col, row), buildings_source_id, floor_tile)
