extends CharacterBody3D
## Zombie for Zombie Survival. Server-authoritative AI; replicated to clients via
## the MultiplayerSpawner + MultiplayerSynchronizer. Several behaviour kinds:
##   0 normal   — baseline melee
##   1 runner   — fast, fragile, small
##   2 brute    — big, slow, tanky, heavy hits
##   3 jumper   — periodically leaps toward the player
##   4 spitter  — keeps its distance and lobs damaging vomit

const VOMIT := preload("res://scenes/vomit.tscn")

const CLIMB_SPEED := 5.0  # vertical scaling speed when reaching an elevated player
const GRAVITY := 14.0
const ATTACK_DURATION := 0.5  # wind-up; damage lands when the swing ends

# Per-kind tuning. speed, hp, dmg, body scale, melee/standoff range, color tint.
const STATS := {
	0: {"speed": 7.0, "hp": 60, "dmg": 12, "scale": 1.0, "range": 2.3, "tint": Color(0.50, 0.95, 0.50)},
	1: {"speed": 12.5, "hp": 26, "dmg": 7, "scale": 0.8, "range": 2.0, "tint": Color(0.85, 0.95, 0.30)},
	2: {"speed": 3.8, "hp": 240, "dmg": 34, "scale": 1.75, "range": 3.2, "tint": Color(0.33, 0.52, 0.28)},
	3: {"speed": 8.0, "hp": 55, "dmg": 16, "scale": 1.0, "range": 2.3, "tint": Color(0.45, 0.80, 0.85)},
	4: {"speed": 5.5, "hp": 48, "dmg": 0, "scale": 1.05, "range": 30.0, "tint": Color(0.72, 0.55, 0.95)},
}

@export var kind := 0  # set by the manager before spawn; replicated at spawn

@onready var visual: Node3D = $Visual

var speed := 7.0
var damage := 12
var attack_range := 2.3
var max_health := 60
var health := 60
var _attacking := false
var _dead := false
var _jump_cd := 0.0   # jumper leap cooldown
var _spit_cd := 0.0   # spitter throw cooldown


func _ready() -> void:
	add_to_group("zombie")
	var s: Dictionary = STATS.get(kind, STATS[0])
	speed = s["speed"]
	damage = s["dmg"]
	attack_range = s["range"]
	max_health = s["hp"]
	health = max_health
	# Uniformly scale the whole body so collision + feet stay aligned.
	scale = Vector3.ONE * float(s["scale"])
	# Stable skin per node name (same on every peer), kind tint, no gun. Zombies
	# don't cast shadows — a big win when many are on screen.
	visual.build(abs(name.hash()), s["tint"], false, false)


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server() or _dead:
		return

	_jump_cd = maxf(_jump_cd - delta, 0.0)
	_spit_cd = maxf(_spit_cd - delta, 0.0)

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
	var height_diff := to_player.y  # how far above us the player is
	to_player.y = 0.0
	var dist := to_player.length()
	if dist > 0.5 and not _attacking:
		look_at(Vector3(target.global_position.x, global_position.y, target.global_position.z), Vector3.UP)

	if kind == 4:
		_act_spitter(target, to_player, dist)
	else:
		_act_melee(target, to_player, dist, height_diff)

	move_and_slide()
	if not _attacking:
		visual.set_locomotion(Vector2(velocity.x, velocity.z).length())


# Melee kinds (normal/runner/brute/jumper): close in, climb, swing in reach.
func _act_melee(target: Node3D, to_player: Vector3, dist: float, height_diff: float) -> void:
	if _attacking:
		velocity.x = 0.0
		velocity.z = 0.0
		return
	if dist > attack_range:
		var dir := _steer(to_player.normalized())
		velocity.x = dir.x * speed
		velocity.z = dir.z * speed
		# Jumpers periodically leap toward the player to close gaps.
		if kind == 3 and is_on_floor() and _jump_cd <= 0.0 and dist > 4.0 and dist < 20.0:
			velocity.x = dir.x * speed * 2.0
			velocity.z = dir.z * speed * 2.0
			velocity.y = 9.5
			_jump_cd = 2.5
		# Climb structures when the player is above and we're against a wall.
		elif height_diff > 1.0 and is_on_wall():
			velocity.y = CLIMB_SPEED
	else:
		velocity.x = 0.0
		velocity.z = 0.0
		if global_position.distance_to(target.global_position) <= attack_range:
			_start_attack(target)


# Spitter: stay far back and snipe with lobbed vomit. It never closes to melee —
# it holds a long standoff and actively retreats if the player charges it.
func _act_spitter(target: Node3D, to_player: Vector3, dist: float) -> void:
	var dir := to_player.normalized()
	if dist > attack_range + 5.0:
		# Too far to aim reliably — drift a bit closer.
		velocity.x = dir.x * speed
		velocity.z = dir.z * speed
	elif dist < attack_range:
		# Player is inside our comfort zone — back away to keep sniping.
		velocity.x = -dir.x * speed
		velocity.z = -dir.z * speed
	else:
		velocity.x = 0.0
		velocity.z = 0.0
	# Fire from anywhere in range; works at long distance now.
	if _spit_cd <= 0.0 and dist < attack_range + 12.0:
		_spit_cd = 2.0
		_spit(target)


# Server-only. Plays the swing on every peer; melee damage lands after the
# wind-up if the player is still within reach.
func _start_attack(_target: Node3D) -> void:
	_attacking = true
	_play_attack.rpc()
	await get_tree().create_timer(ATTACK_DURATION).timeout
	_attacking = false
	if _dead:
		return
	var target := _nearest_player()
	if target and global_position.distance_to(target.global_position) <= attack_range:
		if target.has_method("take_damage"):
			target.take_damage.rpc_id(target.get_multiplayer_authority(), damage, "Zombie", "Melee", global_position)


# Server-only. Launch a vomit projectile on a ballistic arc toward the player.
func _spit(target: Node3D) -> void:
	var v := VOMIT.instantiate()
	var origin := global_position + Vector3.UP * 1.2
	v.position = origin
	var to := target.global_position + Vector3.UP * 0.8 - origin
	var horiz := Vector3(to.x, 0.0, to.z)
	var d := horiz.length()
	# Lobbed arc tuned for long-range sniping: fast and fairly flat so it
	# crosses ~30 m, with an upward kick that scales with distance.
	var launch := horiz.normalized() * 26.0
	launch.y = clampf(d * 0.30, 4.0, 12.0)
	v.velocity = launch
	# Vomits is a sibling of our Zombies container, so resolve it relative to our
	# parent (the Zombies node) — NOT to this zombie, which would be one level off.
	var vomits := get_parent().get_node_or_null("../Vomits")
	if vomits == null:
		Crash.report("spitter: Vomits container missing")
		v.queue_free()
		return
	vomits.add_child(v, true)


@rpc("authority", "call_local", "reliable")
func _play_attack() -> void:
	visual.play_attack(ATTACK_DURATION)


# Reynolds-style steering: seek the player, avoid walls via forward feelers, and
# separate from nearby zombies — so the horde flows around buildings and fans
# out to surround instead of stacking into a single line.
func _steer(seek: Vector3) -> Vector3:
	var steer := seek
	var space := get_world_3d().direct_space_state
	var origin := global_position + Vector3.UP * 0.5
	for a in [0.0, 0.6, -0.6]:
		var d := seek.rotated(Vector3.UP, a)
		var q := PhysicsRayQueryParameters3D.create(origin, origin + d * 4.0)
		q.exclude = [get_rid()]
		var hit := space.intersect_ray(q)
		if not hit.is_empty():
			var n: Vector3 = hit.normal
			n.y = 0.0
			if n.length() > 0.01:
				steer += n.normalized() * 1.3
	for z in get_tree().get_nodes_in_group("zombie"):
		if z == self:
			continue
		var off: Vector3 = global_position - z.global_position
		off.y = 0.0
		var dd := off.length()
		if dd > 0.05 and dd < 2.2:
			steer += off.normalized() * (2.2 - dd) * 0.5
	steer.y = 0.0
	if steer.length() < 0.05:
		return seek
	return steer.normalized()


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
