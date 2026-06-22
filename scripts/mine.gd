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
	var scene := get_tree().get_first_node_in_group("gameworld")
	if scene:
		var fx := preload("res://scenes/explosion.tscn").instantiate()
		scene.add_child(fx)
		fx.global_position = global_position
	for z in get_tree().get_nodes_in_group("zombie"):
		if is_instance_valid(z) and global_position.distance_to(z.global_position) <= RADIUS:
			if z.has_method("take_damage"):
				z.take_damage.rpc_id(z.get_multiplayer_authority(), DAMAGE, "Player", "Mine", global_position)
	# Mines hurt players caught in the blast too.
	for p in get_tree().get_nodes_in_group("player"):
		var d := global_position.distance_to(p.global_position)
		if d <= RADIUS and p.has_method("take_damage"):
			var dmg := int(PLAYER_DAMAGE * (1.0 - d / RADIUS))
			if dmg > 0:
				p.take_damage.rpc_id(p.get_multiplayer_authority(), dmg, "Mine", "Mine", global_position)
	queue_free()
