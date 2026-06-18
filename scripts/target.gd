extends StaticBody3D


@rpc("any_peer", "call_local", "reliable")
func hit() -> void:
	queue_free()
