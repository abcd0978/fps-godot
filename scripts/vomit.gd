extends Node3D
## Spitter zombie projectile. Server drives a ballistic arc and applies damage on
## a near hit; clients just render the replicated position.

const DAMAGE := 15
const LIFETIME := 5.0
const HIT_RADIUS := 1.8
const GRAVITY := 9.0

var velocity := Vector3.ZERO  # set by the spitter before add_child (server only)


func _ready() -> void:
	if multiplayer.is_server():
		await get_tree().create_timer(LIFETIME).timeout
		if is_instance_valid(self):
			queue_free()


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	var prev := global_position
	velocity.y -= GRAVITY * delta
	global_position += velocity * delta
	if global_position.y < -2.0:
		queue_free()
		return
	# Stop on walls: raycast the travelled segment; anything that isn't a fellow
	# zombie blocks the glob (it splats and vanishes).
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(prev, global_position)
	var hit := space.intersect_ray(q)
	if not hit.is_empty():
		var col = hit.get("collider")
		if col == null or not col.is_in_group("zombie"):
			if col and col.is_in_group("player") and col.has_method("take_damage"):
				col.take_damage.rpc_id(col.get_multiplayer_authority(), DAMAGE, "Zombie", "Vomit", global_position)
			queue_free()
			return
	for p in get_tree().get_nodes_in_group("player"):
		if global_position.distance_to(p.global_position) <= HIT_RADIUS:
			if p.has_method("take_damage"):
				p.take_damage.rpc_id(p.get_multiplayer_authority(), DAMAGE, "Zombie", "Vomit", global_position)
			queue_free()
			return
