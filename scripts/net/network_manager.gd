extends Node
## Autoload "Net": owns all multiplayer setup and player (de)spawning.
## The active world registers its Players container via `players_root`.

const PORT := 7777
const ADDRESS := "127.0.0.1"

var player_scene: PackedScene = preload("res://scenes/player.tscn")
var players_root: Node = null
var player_name := "Player"


# Broadcast a kill to every peer's HUD kill feed (called by the victim).
@rpc("any_peer", "call_local", "reliable")
func report_kill(killer: String, victim: String, weapon: String) -> void:
	var hud := get_tree().get_first_node_in_group("hud")
	if hud:
		hud.add_kill(killer, victim, weapon)
	Match.register_kill(killer)


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
