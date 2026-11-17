extends Node2D
## Main world: campus map, player, world boundaries, and camera limits.

const WALL_THICKNESS := 512.0
const TOP_INSET := 80.0
const SIDE_INSET := 16.0

@onready var ground: TileMapLayer = $CampusMap/Ground
@onready var player: CharacterBody2D = $player

var camera: Camera2D


func _ready() -> void:
	# Find the player's camera or create one if it is missing.
	camera = player.get_node_or_null("Camera2D") as Camera2D

	if camera == null:
		camera = Camera2D.new()
		camera.name = "Camera2D"
		player.add_child(camera)

	camera.enabled = true
	camera.make_current()

	# Calculate the campus map boundaries.
	var rect := get_map_rect()

	var play_rect := Rect2(
		rect.position + Vector2(SIDE_INSET, TOP_INSET),
		rect.size - Vector2(SIDE_INSET * 2.0, TOP_INSET)
	)

	_build_world_bounds(play_rect)
	_limit_camera(rect)


## Returns the map's rectangle in world coordinates.
func get_map_rect() -> Rect2:
	var used: Rect2i = ground.get_used_rect()
	var cell_size := Vector2(ground.tile_set.tile_size) * ground.global_scale

	return Rect2(
		ground.to_global(Vector2(used.position) * Vector2(ground.tile_set.tile_size)),
		Vector2(used.size) * cell_size
	)


## Creates invisible walls around the campus map.
func _build_world_bounds(rect: Rect2) -> void:
	var t := WALL_THICKNESS

	var walls: Dictionary = {
		"WallTop": Rect2(
			rect.position.x - t,
			rect.position.y - t,
			rect.size.x + t * 2.0,
			t
		),
		"WallBottom": Rect2(
			rect.position.x - t,
			rect.end.y,
			rect.size.x + t * 2.0,
			t
		),
		"WallLeft": Rect2(
			rect.position.x - t,
			rect.position.y - t,
			t,
			rect.size.y + t * 2.0
		),
		"WallRight": Rect2(
			rect.end.x,
			rect.position.y - t,
			t,
			rect.size.y + t * 2.0
		)
	}

	for wall_name in walls:
		var wall_rect: Rect2 = walls[wall_name]

		var body := StaticBody2D.new()
		body.name = wall_name
		body.collision_layer = 1
		body.collision_mask = 0

		var shape := CollisionShape2D.new()
		var box := RectangleShape2D.new()
		box.size = wall_rect.size

		shape.shape = box
		body.add_child(shape)

		add_child(body)
		body.global_position = wall_rect.get_center()


## Restricts the camera view to the campus map.
func _limit_camera(rect: Rect2) -> void:
	camera.limit_left = int(rect.position.x)
	camera.limit_top = int(rect.position.y)
	camera.limit_right = int(rect.end.x)
	camera.limit_bottom = int(rect.end.y)

	camera.limit_smoothed = true
