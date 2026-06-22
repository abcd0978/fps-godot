extends Area3D
## Rocket-launcher projectile: flies straight, explodes on contact with a zombie
## or the world, dealing area damage. Cosmetic-local like the grenade; damage is
## applied to each zombie's authority via RPC.

const SPEED := 42.0
const RADIUS := 8.0
const DAMAGE := 220
const PLAYER_DAMAGE := 120
const LIFETIME := 4.0

var dir := Vector3.FORWARD  # world-space travel direction, set by the weapon
var _done := false


func _ready() -> void:
	body_entered.connect(_on_body)
	await get_tree().create_timer(LIFETIME).timeout
	_explode()


func _physics_process(delta: float) -> void:
	global_position += dir * SPEED * delta


func _on_body(body: Node) -> void:
	if body.is_in_group("player"):
		return  # pass through players (no friendly fire); blow up on zombies/walls
	_explode()


func _explode() -> void:
	if _done:
		return
	_done = true
	Boom.blast(self, global_position, RADIUS, DAMAGE, PLAYER_DAMAGE, "Player", "Rocket")
	queue_free()
