extends Area3D
## Proximity mine: arms shortly after being placed, then detonates when a zombie
## steps onto it, dealing area damage. Cosmetic-local like the grenade; damage is
## applied to each zombie's authority via RPC.

const RADIUS := 6.0     # explosion damage radius
const DAMAGE := 170
const PLAYER_DAMAGE := 90
const ARM_DELAY := 0.7  # don't blow up the instant it's dropped

var _armed := false
var _done := false


func _ready() -> void:
	add_to_group("mine")
	body_entered.connect(_on_body)
	await get_tree().create_timer(ARM_DELAY).timeout
	_armed = true


func _on_body(body: Node) -> void:
	if _armed and body.is_in_group("zombie"):
		_explode()


func _explode() -> void:
	if _done:
		return
	_done = true
	Boom.blast(self, global_position, RADIUS, DAMAGE, PLAYER_DAMAGE, "Player", "Mine")
	queue_free()
