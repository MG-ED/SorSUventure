extends CharacterBody2D

const SPEED = 300.0

const WALK_PREFIX = "walk_"
const IDLE_PREFIX = "idle_"

# true  = freeze on the first frame when no key is pressed
# false = keep looping the idle animation when stopped
const FREEZE_ON_STOP = true

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D

var facing: String = "down"
var was_moving: bool = false


func _ready() -> void:
	# Top-down game: no floor / ceiling, so slide along walls in every direction
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	# NPCs look the player up through this group
	add_to_group("player")
	play_idle()


func _physics_process(_delta: float) -> void:
	var direction := process_movement()
	move_and_slide()
	update_animation(direction)


func process_movement() -> Vector2:
	var direction := Input.get_vector("left", "right", "up", "down")
	velocity = direction * SPEED
	return direction


func update_animation(direction: Vector2) -> void:
	var is_moving := direction != Vector2.ZERO

	if is_moving:
		update_facing(direction)
		play_walk()
	elif was_moving:
		# The player just stopped, so switch to idle once
		play_idle()

	was_moving = is_moving


func update_facing(direction: Vector2) -> void:
	if abs(direction.x) > abs(direction.y):
		facing = "right" if direction.x > 0 else "left"
	else:
		facing = "down" if direction.y > 0 else "up"


func play_walk() -> void:
	var walk_anim := WALK_PREFIX + facing
	if animated_sprite.sprite_frames.has_animation(walk_anim):
		_play(walk_anim)
	else:
		# No walk animation yet, so use the idle one while moving
		_play(IDLE_PREFIX + facing)


func play_idle() -> void:
	animated_sprite.play(IDLE_PREFIX + facing)
	if FREEZE_ON_STOP:
		animated_sprite.stop()
		animated_sprite.frame = 0


func _play(anim_name: String) -> void:
	# Only restart when the animation changes or was stopped
	if animated_sprite.animation != anim_name or not animated_sprite.is_playing():
		animated_sprite.play(anim_name)
