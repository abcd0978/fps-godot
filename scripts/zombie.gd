extends CharacterBody3D
## Melee zombie for Zombie Survival. Server-authoritative AI; replicated to
## clients via the MultiplayerSpawner + MultiplayerSynchronizer.

const SPEED := 3.0
const GRAVITY := 14.0
const ATTACK_RANGE := 2.3
const ATTACK_DURATION := 0.5  # wind-up; damage lands when the swing ends
const DAMAGE := 12
const MAX_HEALTH := 60

@onready var visual: Node3D = $Visual

var health := MAX_HEALTH
var _attacking := false
var _dead := false


func _ready() -> void:
	add_to_group("zombie")
	# Stable skin per node name (same on every peer) + sickly green tint, no gun.
	visual.build(abs(name.hash()), Color(0.5, 0.95, 0.5, 1), false)


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
	if dist > 0.5 and not _attacking:
		look_at(Vector3(target.global_position.x, global_position.y, target.global_position.z), Vector3.UP)

	if _attacking:
		# Hold position while swinging.
		velocity.x = 0.0
		velocity.z = 0.0
	elif dist > ATTACK_RANGE:
		var dir := to_player.normalized()
		velocity.x = dir.x * SPEED
		velocity.z = dir.z * SPEED
	else:
		velocity.x = 0.0
		velocity.z = 0.0
		# Only start a swing if actually within reach in 3D (can't attack a
		# player standing on a structure above with only the floor between).
		if global_position.distance_to(target.global_position) <= ATTACK_RANGE:
			_start_attack()

	move_and_slide()
	if not _attacking:
		visual.set_locomotion(Vector2(velocity.x, velocity.z).length())


# Server-only. Plays the swing on every peer; damage lands after the wind-up
# if the player is still within reach when the motion ends.
func _start_attack() -> void:
	_attacking = true
	_play_attack.rpc()
	await get_tree().create_timer(ATTACK_DURATION).timeout
	_attacking = false
	if _dead:
		return
	var target := _nearest_player()
	if target and global_position.distance_to(target.global_position) <= ATTACK_RANGE:
		if target.has_method("take_damage"):
			target.take_damage.rpc_id(target.get_multiplayer_authority(), DAMAGE, "Zombie", "Melee", global_position)


@rpc("authority", "call_local", "reliable")
func _play_attack() -> void:
	visual.play_attack(ATTACK_DURATION)


func _nearest_player() -> Node3D:
	var best: Node3D = null
	var best_d := INF
	for p in get_tree().get_nodes_in_group("player"):
		var d: float = global_position.distance_to(p.global_position)
		if d < best_d:
			best_d = d
			best = p
	return best


@rpc("any_peer", "call_local", "reliable")
func take_damage(amount: int, attacker: String, weapon: String, _pos: Vector3) -> void:
	if not multiplayer.is_server() or _dead:
		return
	health -= amount
	if health <= 0:
		_dead = true
		Net.report_kill.rpc(attacker, "Zombie", weapon)
		visual.play_die()
		var mgr := get_tree().get_first_node_in_group("zombiemgr")
		if mgr:
			mgr.on_zombie_died(global_position)
		await get_tree().create_timer(1.2).timeout
		queue_free()
