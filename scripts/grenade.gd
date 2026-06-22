extends RigidBody3D
## Thrown grenade: bounces, then explodes after a fuse, dealing area damage to
## zombies. Damage is applied on each zombie's authority (server) via RPC.

const FUSE := 1.6
const RADIUS := 7.0
const DAMAGE := 150
const PLAYER_DAMAGE := 100


func _ready() -> void:
	await get_tree().create_timer(FUSE).timeout
	_explode()


func _explode() -> void:
	Boom.blast(self, global_position, RADIUS, DAMAGE, PLAYER_DAMAGE, "Grenade", "Grenade")
	queue_free()
