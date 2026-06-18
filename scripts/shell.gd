extends RigidBody3D
## Ejected cartridge casing — spins, bounces off the floor, then vanishes.

func _ready() -> void:
	angular_velocity = Vector3(randf_range(-10, 10), randf_range(-10, 10), randf_range(-10, 10))
	await get_tree().create_timer(1.6).timeout
	queue_free()
