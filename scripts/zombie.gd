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
const SIGHT_RANGE := 55.0  # max distance a zombie can spot a player in line of sight
const SENSE_RANGE := 9.0   # close range it senses the player even without sight
const LOSE_TIME := 4.0     # keeps chasing this long after losing line of sight

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
@onready var _agent: NavigationAgent3D = $NavAgent

var _nav_t := 0.0  # throttle path target updates
var _aware := false        # has line of sight / sense of a player right now
var _last_seen := Vector3.ZERO
var _has_last_seen := false
var _sight_t := 0.0        # throttle line-of-sight checks
var _lost_t := 0.0         # awareness grace timer after losing sight
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
	_update_perception(target, dist, delta)

	if _aware:
		# Pursue: the zombie can see (or sense) the player.
		if dist > 0.5 and not _attacking:
			look_at(Vector3(target.global_position.x, global_position.y, target.global_position.z), Vector3.UP)
		if kind == 4:
			_act_spitter(target, to_player, dist)
		else:
			_act_melee(target, to_player, dist, height_diff, delta)
	elif _has_last_seen:
		_search(delta)  # head to where the player was last seen, then give up
	else:
		velocity.x = 0.0  # idle: hasn't noticed any player
		velocity.z = 0.0

	move_and_slide()
	if not _attacking:
		visual.set_locomotion(Vector2(velocity.x, velocity.z).length())


# Update line-of-sight awareness. Seeing (or sensing up close) refreshes a grace
# timer; once it runs out the zombie stops perceiving the player.
func _update_perception(target: Node3D, dist: float, delta: float) -> void:
	_lost_t = maxf(_lost_t - delta, 0.0)
	_sight_t -= delta
	if _sight_t <= 0.0:
		_sight_t = 0.25
		if dist < SENSE_RANGE or (dist < SIGHT_RANGE and _has_los(target)):
			_last_seen = target.global_position
			_has_last_seen = true
			_lost_t = LOSE_TIME
	_aware = _lost_t > 0.0


# Clear line of sight to the player? Walls block it; other zombies don't.
func _has_los(target: Node3D) -> bool:
	var space := get_world_3d().direct_space_state
	var from := global_position + Vector3.UP * 1.2
	var to := target.global_position + Vector3.UP * 0.6
	var q := PhysicsRayQueryParameters3D.create(from, to)
	var ex: Array = [get_rid()]
	for z in get_tree().get_nodes_in_group("zombie"):
		if z != self:
			ex.append(z.get_rid())
	q.exclude = ex
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return true
	var col = hit.get("collider")
	return col != null and col.is_in_group("player")


# Walk to the last place the player was seen; on arrival, lose interest.
func _search(delta: float) -> void:
	var to := _last_seen - global_position
	to.y = 0.0
	if to.length() < 2.5:
		_has_last_seen = false
		velocity.x = 0.0
		velocity.z = 0.0
		return
	var dir := _nav_dir(_last_seen, delta)
	velocity.x = dir.x * speed * 0.75
	velocity.z = dir.z * speed * 0.75
	if dir.length() > 0.1:
		look_at(global_position + Vector3(dir.x, 0.0, dir.z), Vector3.UP)


# Melee kinds (normal/runner/brute/jumper): close in, climb, swing in reach.
func _act_melee(target: Node3D, to_player: Vector3, dist: float, height_diff: float, delta: float) -> void:
	if _attacking:
		velocity.x = 0.0
		velocity.z = 0.0
		return
	if dist > attack_range:
		var dir := _nav_dir(target.global_position, delta)
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
	# Ballistic solve with target leading: pick a time-of-flight from the range,
	# predict where the player will be, then solve the launch velocity that lands
	# exactly there (gravity must match vomit.gd's GRAVITY).
	var aim := target.global_position + Vector3.UP * 0.8
	var horiz_dist := Vector2(aim.x - origin.x, aim.z - origin.z).length()
	var t: float = clampf(horiz_dist / 24.0, 0.45, 2.2)  # flight time
	aim += target.velocity * t                            # lead the moving player
	var disp := aim - origin
	var g := 9.0
	v.velocity = Vector3(disp.x / t, disp.y / t + 0.5 * g * t, disp.z / t)
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


# Follow the navmesh path toward the player (routes around walls/buildings), with
# a light separation push so zombies don't fully overlap. Falls back to a direct
# beeline if the navmesh isn't ready or yields no path.
func _nav_dir(goal: Vector3, delta: float) -> Vector3:
	var dir := Vector3.ZERO
	_nav_t -= delta
	if _nav_t <= 0.0:
		_nav_t = 0.2
		_agent.target_position = goal
	if not _agent.is_navigation_finished():
		var nxt := _agent.get_next_path_position() - global_position
		nxt.y = 0.0
		if nxt.length() > 0.1:
			dir = nxt.normalized()
	if dir == Vector3.ZERO:  # fallback: straight at the goal
		var to := goal - global_position
		to.y = 0.0
		dir = to.normalized()
	# Light anti-overlap separation (does NOT treat the player as an obstacle).
	var sep := Vector3.ZERO
	for z in get_tree().get_nodes_in_group("zombie"):
		if z == self:
			continue
		var off: Vector3 = global_position - z.global_position
		off.y = 0.0
		var dd := off.length()
		if dd > 0.05 and dd < 1.5:
			sep += off.normalized() * (1.5 - dd)
	var out := dir + sep * 0.4
	out.y = 0.0
	return out.normalized() if out.length() > 0.05 else dir


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
