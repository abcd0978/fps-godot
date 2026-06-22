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
	var scene := get_tree().get_first_node_in_group("gameworld")
	if scene:
		var fx := preload("res://scenes/explosion.tscn").instantiate()
		scene.add_child(fx)
		fx.global_position = global_position
	for z in get_tree().get_nodes_in_group("zombie"):
		if is_instance_valid(z) and global_position.distance_to(z.global_position) <= RADIUS:
			if z.has_method("take_damage"):
				z.take_damage.rpc_id(z.get_multiplayer_authority(), DAMAGE, "Player", "Rocket", global_position)
	# Splash damage catches players too (falls off with distance).
	for p in get_tree().get_nodes_in_group("player"):
		var d := global_position.distance_to(p.global_position)
		if d <= RADIUS and p.has_method("take_damage"):
			var dmg := int(PLAYER_DAMAGE * (1.0 - d / RADIUS))
			if dmg > 0:
				p.take_damage.rpc_id(p.get_multiplayer_authority(), dmg, "Rocket", "Rocket", global_position)
	queue_free()
