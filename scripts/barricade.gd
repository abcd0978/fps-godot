extends StaticBody3D
## Placeable barricade: a solid blocker with HP. Adjacent zombies wear it down
## over time; when its HP hits zero it's destroyed. Durability (max HP) scales
## with the placing player's barricade-durability upgrade level.

const BASE_HP := 300
const HP_PER_LEVEL := 250
const ERODE_INTERVAL := 0.5
const ERODE_PER_ZOMBIE := 9
const ERODE_RANGE := 3.0

@onready var _mesh: MeshInstance3D = $Mesh

var max_hp := BASE_HP
var hp := BASE_HP
var _t := 0.0


func setup(durability_level: int) -> void:
	max_hp = BASE_HP + durability_level * HP_PER_LEVEL
	hp = max_hp


func _ready() -> void:
	add_to_group("barricade")


func _process(delta: float) -> void:
	# Only the server (authoritative over zombies) erodes the barricade.
	if not multiplayer.is_server():
		return
	_t += delta
	if _t < ERODE_INTERVAL:
		return
	_t = 0.0
	var adjacent := 0
	for z in get_tree().get_nodes_in_group("zombie"):
		if is_instance_valid(z) and global_position.distance_to(z.global_position) <= ERODE_RANGE:
			adjacent += 1
	if adjacent > 0:
		hp -= adjacent * ERODE_PER_ZOMBIE
		# Redden the barricade as it takes damage so its health reads at a glance.
		if _mesh:
			var f := clampf(float(hp) / float(max_hp), 0.0, 1.0)
			_mesh.material_override = _damage_mat(f)
		if hp <= 0:
			queue_free()


func _damage_mat(frac: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.45, 0.30, 0.16).lerp(Color(0.6, 0.1, 0.1), 1.0 - frac)
	return m
