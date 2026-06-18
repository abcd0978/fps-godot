extends Node3D
## Zombie Survival wave manager (server-authoritative). Lives on the "Zombies"
## node, which is the MultiplayerSpawner target, so spawned zombies replicate.

const ZOMBIE := preload("res://scenes/zombie.tscn")
const PICKUP := preload("res://scenes/pickup.tscn")
const PICKUP_CHANCE := 0.4

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
	var count := (4 + _phase * 2) * 10
	_alive = count
	for i in count:
		_spawn_zombie()


func _spawn_zombie() -> void:
	var z := ZOMBIE.instantiate()
	z.position = _ring_pos()
	add_child(z, true)


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
	p.kind = randi() % 3
	p.position = Vector3(pos.x, 1.0, pos.z)
	get_node("../Pickups").add_child(p, true)


func _ring_pos() -> Vector3:
	var ang := randf() * TAU
	var r := randf_range(45.0, 82.0)
	return Vector3(cos(ang) * r, 2.0, sin(ang) * r)
