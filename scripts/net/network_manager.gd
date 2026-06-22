extends Node
## Autoload "Net": owns all multiplayer setup and player (de)spawning.
## The active world registers its Players container via `players_root`.

const PORT := 7777
const ADDRESS := "127.0.0.1"

const MAX_SPLATS := 500  # global cap on persistent ground blood decals

var player_scene: PackedScene = preload("res://scenes/player.tscn")
var blood_scene: PackedScene = preload("res://scenes/blood.tscn")
var splat_scene: PackedScene = preload("res://scenes/blood_splat.tscn")
var players_root: Node = null
var player_name := "Player"


# Broadcast a kill to every peer's HUD kill feed (called by the victim).
@rpc("any_peer", "call_local", "reliable")
func report_kill(killer: String, victim: String, weapon: String) -> void:
	var hud := get_tree().get_first_node_in_group("hud")
	if hud:
		hud.add_kill(killer, victim, weapon)
	Match.register_kill(killer)
	# Award the local player points for their own zombie kills (Boxhead economy).
	if victim == "Zombie":
		for p in get_tree().get_nodes_in_group("player"):
			if p.is_multiplayer_authority() and p.pname == killer and p.has_method("add_points"):
				p.add_points(15)
				break


# Spawn a blood burst at a hit point on every peer (cosmetic, so unreliable).
# `normal` is the surface normal so the spurt sprays outward; a persistent
# splat decal is also dropped on the ground below the hit.
@rpc("any_peer", "call_local", "unreliable")
func spawn_blood(pos: Vector3, normal := Vector3.UP) -> void:
	var scene := get_tree().get_first_node_in_group("gameworld")
	if scene == null:
		return
	var b := blood_scene.instantiate()
	scene.add_child(b)
	b.global_position = pos
	# Aim the burst (local +Z) along the surface normal so it sprays back
	# outward. look_at points -Z at the target, so target = pos - normal.
	if normal.length() > 0.01 and absf(normal.dot(Vector3.UP)) < 0.99:
		b.look_at(pos - normal, Vector3.UP)
	_drop_splat(scene, pos)


# Scatter several small blood marks on the ground beneath the hit. Actors are
# excluded from the ray so a mid-air kill never paints blood onto a body — it
# always falls to the floor (or nowhere, if there's no ground below).
func _drop_splat(scene: Node, pos: Vector3) -> void:
	var world := (scene as Node3D).get_world_3d()
	if world == null:
		return
	var space := world.direct_space_state
	if space == null:
		return
	var exclude: Array = []
	for n in get_tree().get_nodes_in_group("zombie"):
		exclude.append(n.get_rid())
	for n in get_tree().get_nodes_in_group("player"):
		exclude.append(n.get_rid())
	var q := PhysicsRayQueryParameters3D.create(pos + Vector3.UP * 0.3, pos + Vector3.DOWN * 10.0)
	q.exclude = exclude
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return
	var hpos: Vector3 = hit.position
	var hnorm: Vector3 = hit.normal
	var marks := randi_range(3, 5)
	var splats := get_tree().get_nodes_in_group("bloodsplat")
	while splats.size() + marks > MAX_SPLATS and not splats.is_empty():
		splats[0].queue_free()
		splats.remove_at(0)
	# A cluster of small, varied marks rather than one big pool.
	for i in marks:
		var s := splat_scene.instantiate()
		scene.add_child(s)
		var off := Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0))
		s.global_position = hpos + hnorm * 0.02 + off
		var basis := _basis_from_normal(hnorm)
		basis = basis.rotated(hnorm, randf() * TAU).scaled(Vector3.ONE * randf_range(0.25, 0.6))
		s.global_transform.basis = basis


# Build an orthonormal basis whose +Z points along `n` (the quad's facing axis).
func _basis_from_normal(n: Vector3) -> Basis:
	var up := Vector3.UP if absf(n.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	var x := up.cross(n).normalized()
	var y := n.cross(x).normalized()
	return Basis(x, y, n)


func host() -> bool:
	var peer := ENetMultiplayerPeer.new()
	if peer.create_server(PORT) != OK:
		return false
	multiplayer.multiplayer_peer = peer
	multiplayer.peer_connected.connect(_spawn_player)
	multiplayer.peer_disconnected.connect(_despawn_player)
	_spawn_player(1)
	return true


func join(address := ADDRESS) -> bool:
	var peer := ENetMultiplayerPeer.new()
	if peer.create_client(address, PORT) != OK:
		return false
	multiplayer.multiplayer_peer = peer
	return true


# Server-only. MultiplayerSpawner replicates the new child to every client.
func _spawn_player(id: int) -> void:
	if players_root == null:
		return
	var p := player_scene.instantiate()
	p.name = str(id)
	p.position = Vector3(randf_range(-6.0, 6.0), 2.0, randf_range(-6.0, 6.0))
	players_root.add_child(p, true)
	if id != 1 and Match.running:
		Match.sync_to(id)


func _despawn_player(id: int) -> void:
	if players_root and players_root.has_node(str(id)):
		players_root.get_node(str(id)).queue_free()
