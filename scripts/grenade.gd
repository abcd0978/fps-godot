extends RigidBody3D
## Thrown grenade: bounces, then explodes after a fuse, dealing area damage to
## zombies. Damage is applied on each zombie's authority (server) via RPC.

const FUSE := 1.6
const RADIUS := 7.0
const DAMAGE := 150


func _ready() -> void:
	await get_tree().create_timer(FUSE).timeout
	_explode()


func _explode() -> void:
	var scene := get_tree().get_first_node_in_group("gameworld")
	if scene:
		var fx := preload("res://scenes/blood.tscn").instantiate()
		scene.add_child(fx)
		fx.global_position = global_position
		fx.scale = Vector3(3.5, 3.5, 3.5)
	for z in get_tree().get_nodes_in_group("zombie"):
		if is_instance_valid(z) and global_position.distance_to(z.global_position) <= RADIUS:
			if z.has_method("take_damage"):
				z.take_damage.rpc_id(z.get_multiplayer_authority(), DAMAGE, "Grenade", "Grenade", global_position)
	queue_free()
