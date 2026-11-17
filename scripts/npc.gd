extends CharacterBody2D
## Walking NPC.
## - Patrols back and forth between `patrol_points` (ping-pong) and, when
##   `road_only` is on, only steps on road tiles of the Ground TileMapLayer.
## - Collides with buildings, trees, benches, walls and the player
##   (it uses physics layer 1 / mask 1, the same layer as the tilemap and player).
## - When the player gets close it stops, faces the player and shows a speech
##   bubble with its own `dialogue`. When the player walks away the bubble
##   disappears and the NPC carries on patrolling.
##
## The node origin is at the NPC's FEET (see npc.tscn), so patrol points are
## the positions of the feet in world coordinates.

## Distance (px) at which a patrol point counts as reached.
const ARRIVE_DISTANCE := 4.0
## How far ahead (px) to look for road before taking a step.
const ROAD_PROBE := 24.0
## Centre of the body, relative to the feet (the node origin is at the feet).
const BODY_CENTER := Vector2(0, -46)
## Height of the bubble's bottom edge above the feet.
const BUBBLE_HEIGHT := 100.0
## Longer dialogue lines wrap at this width (px).
const BUBBLE_MAX_WIDTH := 360.0

@export_group("Dialogue")
## What this NPC says. Every NPC instance can have its own text.
@export_multiline var dialogue: String = "Hello!"
## Colour tint so the NPCs are easy to tell apart.
@export var tint: Color = Color.WHITE

@export_group("Patrol")
## World positions (of the feet) to walk between (ping-pong). Put every point
## on a road tile. With CampusMap scaled x3 one tile is 48 px, so the centre of
## tile (cx, cy) is ((cx + 0.5) * 48, (cy + 0.5) * 48).
@export var patrol_points: PackedVector2Array = PackedVector2Array()
@export var speed: float = 70.0
## Seconds to wait at each end of the patrol.
@export var wait_time: float = 1.5
## When true, the NPC never leaves the road tiles.
@export var road_only: bool = true
## The Ground TileMapLayer that holds the road tiles (path relative to this NPC).
@export var ground_path: NodePath = ^"../CampusMap/Ground"
## Atlas coordinates of the road tile in campus_tileset.tres (Ground layer).
@export var road_atlas_coords: Vector2i = Vector2i(1, 9)

@export_group("Interaction")
## The NPC stops and talks when the player is closer than this (px).
@export var talk_radius: float = 160.0
## ...and walks again once the player is farther than this (px).
@export var leave_radius: float = 210.0

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D

# The sprite sheet only has right / left / up rows (no front-facing row).
var facing: String = "right"

var _ground: TileMapLayer
var _player: Node2D
var _bubble: Label

var _index := 0
var _step := 1
var _wait_left := 0.0
var _blocked_time := 0.0
var _talking := false


func _ready() -> void:
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	sprite.modulate = tint
	# Hysteresis needs the leave distance to be larger than the talk distance.
	leave_radius = maxf(leave_radius, talk_radius + 20.0)

	_ground = get_node_or_null(ground_path) as TileMapLayer
	_build_bubble()
	_check_setup()

	if patrol_points.size() > 0:
		global_position = patrol_points[0]
		_index = 1 if patrol_points.size() > 1 else 0

	_play_idle()


func _physics_process(delta: float) -> void:
	_update_talking()

	if _talking:
		velocity = Vector2.ZERO
		_face_player()
		_play_idle()
		return

	if patrol_points.size() < 2:
		_play_idle()
		return

	if _wait_left > 0.0:
		_wait_left -= delta
		velocity = Vector2.ZERO
		_play_idle()
		return

	var to_target := patrol_points[_index] - global_position
	if to_target.length() <= ARRIVE_DISTANCE:
		_advance_index()
		_wait_left = wait_time
		velocity = Vector2.ZERO
		_play_idle()
		return

	var direction := to_target.normalized()

	# Road only: if the next step is not road, turn back instead of walking on.
	if road_only and not _is_road(global_position + direction * ROAD_PROBE):
		_advance_index()
		_wait_left = 0.5
		velocity = Vector2.ZERO
		_play_idle()
		return

	velocity = direction * speed
	update_facing(direction)
	_play_walk()
	move_and_slide()

	# Something solid is in the way (building, tree, bench, wall, the player):
	# give up on this point and head for the other one.
	if get_real_velocity().length() < speed * 0.2:
		_blocked_time += delta
		if _blocked_time > 0.6:
			_blocked_time = 0.0
			_advance_index()
	else:
		_blocked_time = 0.0


# ---------------------------------------------------------------- setup check

## Prints a warning in the Output panel for the usual configuration mistakes.
func _check_setup() -> void:
	if patrol_points.size() < 2:
		push_warning("%s: needs at least 2 patrol_points to patrol." % name)
	if not road_only:
		return
	if _ground == null:
		push_warning("%s: road_only is on but ground_path '%s' is not a TileMapLayer - roads are NOT checked." % [name, ground_path])
		return
	for i in patrol_points.size():
		if not _is_road(patrol_points[i]):
			push_warning("%s: patrol point %d at %s is not on a road tile." % [name, i, patrol_points[i]])


# ---------------------------------------------------------------- patrol

func _advance_index() -> void:
	var next := _index + _step
	if next < 0 or next >= patrol_points.size():
		_step = -_step
		next = _index + _step
	_index = clampi(next, 0, patrol_points.size() - 1)


func _is_road(world_pos: Vector2) -> bool:
	if _ground == null:
		return true
	var cell := _ground.local_to_map(_ground.to_local(world_pos))
	return _ground.get_cell_atlas_coords(cell) == road_atlas_coords


# ---------------------------------------------------------------- talking

func _update_talking() -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node2D
		if _player == null:
			# No player in the scene: never stay stuck in a conversation.
			if _talking:
				_set_talking(false)
			return

	var distance := (global_position + BODY_CENTER).distance_to(_player.global_position)

	if _talking and distance > leave_radius:
		_set_talking(false)
	elif not _talking and distance < talk_radius:
		_set_talking(true)


func _set_talking(value: bool) -> void:
	_talking = value
	if value:
		_open_bubble()
	else:
		_bubble.visible = false
		_wait_left = 0.5


func _face_player() -> void:
	if _player == null:
		return
	var diff := _player.global_position - (global_position + BODY_CENTER)
	if absf(diff.x) >= absf(diff.y) or diff.y > 0.0:
		facing = "right" if diff.x >= 0.0 else "left"
	else:
		facing = "up"


func _build_bubble() -> void:
	_bubble = Label.new()
	_bubble.text = dialogue
	_bubble.visible = false
	_bubble.z_index = 100
	_bubble.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_bubble.add_theme_font_size_override("font_size", 20)
	_bubble.add_theme_color_override("font_color", Color.BLACK)

	var style := StyleBoxFlat.new()
	style.bg_color = Color.WHITE
	style.border_color = Color(0.1, 0.1, 0.1)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(8)
	_bubble.add_theme_stylebox_override("normal", style)

	add_child(_bubble)


## Fills the bubble with this NPC's dialogue and centres it above the head.
func _open_bubble() -> void:
	_bubble.text = dialogue
	_bubble.autowrap_mode = TextServer.AUTOWRAP_OFF
	_bubble.custom_minimum_size = Vector2.ZERO
	_bubble.reset_size()

	var natural := _bubble.get_minimum_size()
	if natural.x > BUBBLE_MAX_WIDTH:
		# Long line: wrap it at BUBBLE_MAX_WIDTH, then take the wrapped height.
		_bubble.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_bubble.custom_minimum_size.x = BUBBLE_MAX_WIDTH
		_bubble.size = Vector2(BUBBLE_MAX_WIDTH, 0.0)
		_bubble.size = Vector2(BUBBLE_MAX_WIDTH, _bubble.get_minimum_size().y)
	else:
		_bubble.size = natural

	_bubble.position = Vector2(-_bubble.size.x / 2.0, -BUBBLE_HEIGHT - _bubble.size.y)
	_bubble.visible = true


# ---------------------------------------------------------------- animation

func update_facing(direction: Vector2) -> void:
	if absf(direction.x) > absf(direction.y):
		facing = "right" if direction.x > 0.0 else "left"
	elif direction.y < 0.0:
		facing = "up"
	elif facing == "up":
		# Walking down: the sheet has no front view, so use the side view.
		facing = "right"


func _play_walk() -> void:
	# walk_<facing>, or idle_<facing> if the walk animation does not exist.
	var anim_name := _pick_animation("walk_" + facing, "idle_" + facing)
	if anim_name == "":
		return
	if sprite.animation != anim_name or not sprite.is_playing():
		sprite.play(anim_name)


func _play_idle() -> void:
	var anim_name := _pick_animation("idle_" + facing, "idle")
	if anim_name == "":
		return
	if sprite.sprite_frames.get_frame_count(anim_name) > 1:
		# A multi-frame idle would look like walking on the spot: hold frame 0.
		if sprite.animation != anim_name or sprite.is_playing():
			sprite.play(anim_name)
			sprite.stop()
			sprite.frame = 0
	elif sprite.animation != anim_name or not sprite.is_playing():
		sprite.play(anim_name)


## Returns `anim` if the sprite has it, else `fallback` if the sprite has that,
## else "" (so a missing animation never raises an error).
func _pick_animation(anim: String, fallback: String) -> String:
	var frames := sprite.sprite_frames
	if frames == null:
		return ""
	if frames.has_animation(anim):
		return anim
	if frames.has_animation(fallback):
		return fallback
	return ""
