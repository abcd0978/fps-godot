extends Node3D
## One-shot explosion VFX: fire burst + debris + a quick light flash, then frees.

func _ready() -> void:
	for p in find_children("*", "CPUParticles3D", true, false):
		p.emitting = true
	var light := get_node_or_null("Light") as OmniLight3D
	if light:
		var tw := create_tween()
		tw.tween_property(light, "light_energy", 0.0, 0.4)
	await get_tree().create_timer(1.2).timeout
	queue_free()
