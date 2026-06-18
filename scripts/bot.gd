extends CharacterBody3D
## Single-player enemy bot: animated combatant that chases the player, stops at
## range and fires probabilistic shots. Forgiving but not trivial.

const SPEED := 3.4
const GRAVITY := 14.0
const STOP_RANGE := 11.0
const SHOOT_RANGE := 30.0
const FIRE_MIN := 1.4
const FIRE_MAX := 2.4
const HIT_CHANCE := 0.75      # raised per request
const DAMAGE := 6
const MAX_HEALTH := 40

@onready var ray: RayCast3D = $Ray
@onready var visual: Node3D = $Visual

var health := MAX_HEALTH
var _fire_cd := 0.0
var _dead := false


func _ready() -> void:
	add_to_group("bot")
	ray.add_exception(self)
	visual.build(-1)  # random skin
	_fire_cd = randf_range(FIRE_MIN, FIRE_MAX)


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server() or _dead:
		return

	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = 0.0

	var target := _nearest_player()
	if target == null:
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()
		visual.set_locomotion(0.0)
		return

	var to_player := target.global_position - global_position
	to_player.y = 0.0
	var dist := to_player.length()

	if dist > 0.5:
		look_at(Vector3(target.global_position.x, global_position.y, target.global_position.z), Vector3.UP)

	if dist > STOP_RANGE:
		var dir := to_player.normalized()
		velocity.x = dir.x * SPEED
		velocity.z = dir.z * SPEED
	else:
		velocity.x = 0.0
		velocity.z = 0.0

	move_and_slide()
	visual.set_locomotion(Vector2(velocity.x, velocity.z).length())

	_fire_cd -= delta
	if _fire_cd <= 0.0 and dist < SHOOT_RANGE and _can_see(target):
		_shoot(target)
		_fire_cd = randf_range(FIRE_MIN, FIRE_MAX)


func _nearest_player() -> Node3D:
	var best: Node3D = null
	var best_d := INF
	for p in get_tree().get_nodes_in_group("player"):
		var d: float = global_position.distance_to(p.global_position)
		if d < best_d:
			best_d = d
			best = p
	return best


func _can_see(target: Node3D) -> bool:
	ray.target_position = ray.to_local(target.global_position + Vector3(0, 0.4, 0))
	ray.force_raycast_update()
	if ray.is_colliding():
		return ray.get_collider() == target
	return true


func _shoot(target: Node3D) -> void:
	if randf() > HIT_CHANCE:
		return
	if target.has_method("take_damage"):
		target.take_damage.rpc_id(target.get_multiplayer_authority(), DAMAGE, "Bot", "Rifle", global_position)


# Player weapon calls this with 3 args (matches player.take_damage signature).
@rpc("any_peer", "call_local", "reliable")
func take_damage(amount: int, attacker: String, weapon: String, _pos: Vector3) -> void:
	if not multiplayer.is_server() or _dead:
		return
	health -= amount
	if health <= 0:
		_dead = true
		Net.report_kill.rpc(attacker, "Bot", weapon)
		visual.play_die()
		await get_tree().create_timer(1.4).timeout
		var mgr := get_tree().get_first_node_in_group("botmgr")
		if mgr:
			mgr.on_bot_died()
		queue_free()
