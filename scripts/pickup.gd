extends Area3D
## Pickup item: health / ammo / weapon. Server grants to the touching player
## and despawns. Color is derived from `kind` (replicated on spawn).

@export var kind := 0  # 0 = health, 1 = ammo, 2 = weapon

@onready var mesh: MeshInstance3D = $Mesh


func _ready() -> void:
	_apply_color()
	if multiplayer.is_server():
		body_entered.connect(_on_body)


func _process(delta: float) -> void:
	rotate_y(delta * 1.5)


func _apply_color() -> void:
	var c := Color(0.2, 0.9, 0.35)        # health = green
	if kind == 1:
		c = Color(0.95, 0.85, 0.2)        # ammo = yellow
	elif kind == 2:
		c = Color(0.35, 0.6, 1.0)         # weapon = blue
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = 0.9
	mesh.material_override = m


func _on_body(body: Node) -> void:
	if not multiplayer.is_server() or not body.is_in_group("player"):
		return
	var auth: int = body.get_multiplayer_authority()
	match kind:
		0:
			body.add_health.rpc_id(auth, 50)
		1:
			body.give_ammo.rpc_id(auth)
		2:
			body.give_weapon.rpc_id(auth, randi_range(1, 3))
	queue_free()
