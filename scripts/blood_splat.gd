extends MeshInstance3D
## A persistent blood splat decal on the ground. Lives in the "bloodsplat"
## group; the spawner caps the total count and frees the oldest beyond it.

func _ready() -> void:
	add_to_group("bloodsplat")
