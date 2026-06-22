extends Node3D
## Zombie Survival wave manager (server-authoritative). Lives on the "Zombies"
## node, which is the MultiplayerSpawner target, so spawned zombies replicate.

const ZOMBIE := preload("res://scenes/zombie.tscn")
const PICKUP := preload("res://scenes/pickup.tscn")
const PICKUP_CHANCE := 0.7  # higher drop rate
const MAX_ALIVE := 28  # hard concurrent cap — keeps the frame rate sane

var _phase := 0
var _alive := 0
var _active := false


func _ready() -> void:
	add_to_group("zombiemgr")


func start() -> void:
	if _active:
		return
	_active = true
	_next_phase()


func _next_phase() -> void:
	_phase += 1
	Match.set_phase(_phase)
	var players: int = maxi(get_tree().get_nodes_in_group("player").size(), 1)
	# Modest growth, capped so we never tank performance.
	var count: int = mini((12 + _phase * 4) * players, MAX_ALIVE * players)
	count = mini(count, MAX_ALIVE)
	_alive = count
	Crash.breadcrumb("wave phase=%d spawn=%d players=%d" % [_phase, count, players])
	for i in count:
		_spawn_zombie()


func _spawn_zombie() -> void:
	var z := ZOMBIE.instantiate()
	z.kind = _pick_kind()
	z.position = _spawn_pos()
	add_child(z, true)


# Weighted kind roll. Special types get rarer-but-tougher; brutes/spitters
# only show up in later phases so early waves stay readable.
func _pick_kind() -> int:
	var r := randf()
	if _phase >= 3 and r < 0.08:
		return 2  # brute (big, slow tank)
	if _phase >= 2 and r < 0.22:
		return 4  # spitter (ranged vomit)
	if r < 0.42:
		return 1  # runner (fast)
	if r < 0.60:
		return 3  # jumper (leaps in)
	return 0  # normal


func on_zombie_died(pos: Vector3) -> void:
	if not _active:
		return
	_alive -= 1
	if randf() < PICKUP_CHANCE:
		_spawn_pickup(pos)
	if _alive <= 0:
		await get_tree().create_timer(4.0).timeout
		if _active:
			_next_phase()


func _spawn_pickup(pos: Vector3) -> void:
	var p := PICKUP.instantiate()
	# Rare minigun, common weapon/upgrade items, otherwise health/ammo/grenade.
	var r := randf()
	if r < 0.05:
		p.kind = 4          # minigun (rare)
	elif r < 0.30:
		p.kind = 5          # weapon upgrade item
	elif r < 0.55:
		p.kind = 2          # new weapon unlock
	else:
		p.kind = randi() % 4  # health / ammo / weapon / grenade
	p.position = Vector3(pos.x, 1.0, pos.z)
	get_node("../Pickups").add_child(p, true)


# Spawn in a full ring AROUND a (random) player rather than around the map
# origin, so zombies close in from every side instead of funnelling into a line.
func _spawn_pos() -> Vector3:
	var players := get_tree().get_nodes_in_group("player")
	var center := Vector3.ZERO
	if players.size() > 0:
		center = players[randi() % players.size()].global_position
	var ang := randf() * TAU
	var r := randf_range(28.0, 52.0)
	var x: float = clampf(center.x + cos(ang) * r, -86.0, 86.0)
	var z: float = clampf(center.z + sin(ang) * r, -86.0, 86.0)
	# Snap onto the navmesh so zombies never spawn trapped inside a wall/building.
	var map := get_world_3d().get_navigation_map()
	var snapped := NavigationServer3D.map_get_closest_point(map, Vector3(x, 1.0, z))
	if snapped != Vector3.ZERO:
		return Vector3(snapped.x, 2.0, snapped.z)
	return Vector3(x, 2.0, z)
