extends Node3D
## Spawns and maintains a small population of bots for single player.
## Bots respawn after a delay so the match keeps going, but the count stays low.

const COUNT := 5
const RESPAWN_DELAY := 4.0

var bot_scene: PackedScene = preload("res://scenes/bot.tscn")
var _active := false


func _ready() -> void:
	add_to_group("botmgr")


func start() -> void:
	if _active:
		return
	_active = true
	for i in COUNT:
		_spawn_one()


func on_bot_died() -> void:
	if not _active:
		return
	await get_tree().create_timer(RESPAWN_DELAY).timeout
	if _active:
		_spawn_one()


func _spawn_one() -> void:
	var bot := bot_scene.instantiate()
	bot.position = _random_spawn()
	add_child(bot)


func _random_spawn() -> Vector3:
	# Keep bots away from the arena center where the player starts.
	var p := Vector3(randf_range(-42.0, 42.0), 2.0, randf_range(-42.0, 42.0))
	if p.length() < 14.0:
		p = p.normalized() * 18.0
		p.y = 2.0
	return p
