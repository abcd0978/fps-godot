extends CPUParticles3D
## One-shot blood burst spawned at a hit point, then self-frees.

func _ready() -> void:
	emitting = true
	await get_tree().create_timer(1.0).timeout
	queue_free()
