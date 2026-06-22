class_name Boom
extends RefCounted
## Shared explosion helper used by grenades, rockets and mines: spawns the
## explosion VFX and deals radial damage to zombies (full) and players (falls off
## with distance). Damage is applied on each victim's authority via RPC.

const EXPLOSION := preload("res://scenes/explosion.tscn")


static func blast(source: Node, pos: Vector3, radius: float, zombie_dmg: int, player_dmg: int, attacker: String, weapon: String) -> void:
	var tree := source.get_tree()
	if tree == null:
		return
	var world := tree.get_first_node_in_group("gameworld")
	if world:
		var fx := EXPLOSION.instantiate()
		world.add_child(fx)
		fx.global_position = pos
	for z in tree.get_nodes_in_group("zombie"):
		if is_instance_valid(z) and pos.distance_to(z.global_position) <= radius and z.has_method("take_damage"):
			z.take_damage.rpc_id(z.get_multiplayer_authority(), zombie_dmg, attacker, weapon, pos)
	for p in tree.get_nodes_in_group("player"):
		var d := pos.distance_to(p.global_position)
		if d <= radius and p.has_method("take_damage"):
			var dmg := int(player_dmg * (1.0 - d / radius))
			if dmg > 0:
				p.take_damage.rpc_id(p.get_multiplayer_authority(), dmg, attacker, weapon, pos)
