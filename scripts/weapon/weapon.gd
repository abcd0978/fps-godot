extends Node3D
## First-person weapon: swaps real GLB gun models per type and handles
## firing, recoil kickback, muzzle flash, ammo/reload, and aim-down-sights.

signal weapon_changed(weapon_name: String)
signal ammo_changed(current: int, maximum: int)

const KICK_BACK := 0.10   # how far the gun jolts toward the camera per shot
const KICK_PITCH := 0.05  # camera recoil (radians) returned to the player
const RECOVER := 13.0     # recoil/aim lerp speed
const FLASH_TIME := 0.05
const RELOAD_TIME := 1.1
const SHELL := preload("res://scenes/shell.tscn")
const GRENADE := preload("res://scenes/grenade.tscn")
# Orient Quaternius guns (barrel = model +X) to Godot view space (forward -Z).
# columns = images of model X/Y/Z axes. up stays +Y (fixes the 90° roll).
# If a gun points backwards, negate the x column; if it rolls the wrong way,
# swap the sign on the y/z columns.
const GUN_ORIENT := Basis(Vector3(0, 0, -1), Vector3(0, 1, 0), Vector3(1, 0, 0))

# name, model, damage, cooldown, magazine size, view scale + hip-fire position
var _defs := [
	{"name": "Pistol", "scene": preload("res://assets/weapons/real/pistol.glb"), "damage": 18, "cooldown": 0.30, "mag": 12, "reserve": 36, "scale": 0.29, "pos": Vector3(0.22, -0.29, -0.5)},
	{"name": "Rifle", "scene": preload("res://assets/weapons/real/rifle.glb"), "damage": 28, "cooldown": 0.12, "mag": 30, "reserve": 60, "scale": 0.28, "pos": Vector3(0.24, -0.31, -0.55)},
	{"name": "Shotgun", "scene": preload("res://assets/weapons/real/shotgun.glb"), "damage": 55, "cooldown": 0.85, "mag": 7, "reserve": 21, "scale": 0.30, "pos": Vector3(0.24, -0.31, -0.52)},
	{"name": "Sniper", "scene": preload("res://assets/weapons/real/sniper.glb"), "damage": 100, "cooldown": 1.4, "mag": 5, "reserve": 15, "scale": 0.34, "pos": Vector3(0.26, -0.29, -0.58), "scope": true, "ads_fov": 16.0},
	{"name": "Knife", "scene": preload("res://assets/weapons/real/knife.glb"), "damage": 70, "cooldown": 0.5, "mag": 1, "scale": 12.0, "pos": Vector3(0.2, -0.26, -0.45), "melee": true, "range": 2.6},
	{"name": "Grenade", "scene": preload("res://scenes/grenade_held.tscn"), "damage": 0, "cooldown": 0.8, "mag": 1, "reserve": 2, "scale": 1.0, "pos": Vector3(0.22, -0.28, -0.5), "throwable": true},
]

@onready var raycast: RayCast3D = $RayCast
@onready var recoil: Node3D = $Recoil
@onready var hold: Node3D = $Recoil/Hold
@onready var muzzle: MeshInstance3D = $Recoil/Muzzle

var shooter_name := "Player"  # set by the owning player for kill attribution
var _current := 0
var _cooldown := 0.0
var _flash := 0.0
var _reloading := false
var _aiming := false
var _ammo: Array[int] = []
var _reserve: Array[int] = []   # spare ammo (zombie); grenade count for throwable
var _model: Node3D = null
var _hip_pos := Vector3.ZERO
var _aim_pos := Vector3.ZERO


func _ready() -> void:
	for d in _defs:
		_ammo.append(int(d.get("mag", 1)))
		_reserve.append(int(d.get("reserve", 0)))
	_equip(0)


func _process(delta: float) -> void:
	if _cooldown > 0.0:
		_cooldown -= delta
	var target := _aim_pos if _aiming else _hip_pos
	recoil.position = recoil.position.lerp(target, delta * RECOVER)
	recoil.rotation.x = lerp(recoil.rotation.x, 0.0, delta * RECOVER)
	if _flash > 0.0:
		_flash -= delta
		if _flash <= 0.0:
			muzzle.visible = false


func current_name() -> String:
	return _defs[_current].name


func current_ammo() -> int:
	return _ammo[_current]


func current_mag() -> int:
	return int(_defs[_current].mag)


func ignore_collider(node: Node3D) -> void:
	raycast.add_exception(node)


func set_aiming(value: bool) -> void:
	_aiming = value


func aim_fov() -> float:
	return float(_defs[_current].get("ads_fov", 50.0))


func has_scope() -> bool:
	return bool(_defs[_current].get("scope", false))


# Hide the gun model while looking through the scope.
func show_model(value: bool) -> void:
	hold.visible = value
	if not value:
		muzzle.visible = false


func equip(index: int) -> void:
	if index < 0 or index >= _defs.size() or index == _current or _reloading:
		return
	_equip(index)


func reload() -> void:
	if _reloading:
		return
	var d = _defs[_current]
	if bool(d.get("melee", false)) or bool(d.get("throwable", false)):
		return
	if _ammo[_current] >= int(d.mag):
		return
	if Match.mode == "zombie" and _reserve[_current] <= 0:
		return  # no spare ammo to reload with
	_reloading = true
	var t := create_tween()
	t.set_ease(Tween.EASE_IN_OUT)
	t.tween_property(hold, "rotation:x", 0.9, RELOAD_TIME * 0.45)
	t.tween_callback(_refill)
	t.tween_property(hold, "rotation:x", 0.0, RELOAD_TIME * 0.45)
	t.tween_callback(_end_reload)


# Emit the current weapon's ammo display: melee=∞, grenade=count(-2), gun=mag/reserve.
func _emit_ammo() -> void:
	var d = _defs[_current]
	if bool(d.get("throwable", false)):
		ammo_changed.emit(_reserve[_current], -2)
	elif bool(d.get("melee", false)):
		ammo_changed.emit(-1, -1)
	elif Match.mode == "zombie":
		ammo_changed.emit(_ammo[_current], _reserve[_current])
	else:
		ammo_changed.emit(_ammo[_current], int(d.mag))


# Returns the camera recoil pitch to apply (0.0 if no shot was fired).
func fire() -> float:
	var d = _defs[_current]
	if _cooldown > 0.0 or _reloading:
		return 0.0

	# Throwable (grenade): consume one from reserve and throw a projectile.
	if bool(d.get("throwable", false)):
		if _reserve[_current] <= 0:
			return 0.0
		_cooldown = float(d.cooldown)
		_reserve[_current] -= 1
		_emit_ammo()
		_throw_grenade()
		recoil.position.z += KICK_BACK
		return KICK_PITCH

	var melee := bool(d.get("melee", false))
	if not melee and _ammo[_current] <= 0:
		return 0.0
	_cooldown = float(d.cooldown)
	if not melee:
		_ammo[_current] -= 1
		_emit_ammo()

	recoil.position.z += KICK_BACK
	recoil.rotation.x = -KICK_PITCH
	if not melee:
		_show_flash()
		_eject_shell()

	if raycast.is_colliding():
		var point: Vector3 = raycast.get_collision_point()
		if global_position.distance_to(point) <= float(d.get("range", 1000.0)):
			var hit = raycast.get_collider()
			if hit:
				var dmg := int(d.damage)
				if hit.has_method("take_damage"):
					hit.take_damage.rpc_id(hit.get_multiplayer_authority(), dmg, shooter_name, current_name(), global_position)
					Net.spawn_blood.rpc(point)
				elif hit.has_method("hit"):
					hit.hit.rpc()
	return KICK_PITCH


func _eject_shell() -> void:
	var scene := get_tree().get_first_node_in_group("gameworld")
	if scene == null:
		return
	var shell := SHELL.instantiate()
	scene.add_child(shell)
	shell.global_position = muzzle.global_position
	var b := global_transform.basis
	shell.linear_velocity = b.x * randf_range(2.0, 3.5) + b.y * randf_range(1.5, 2.5) + b.z * randf_range(-0.5, 0.5)


func _show_flash() -> void:
	muzzle.visible = true
	muzzle.rotation.z = randf_range(0.0, TAU)
	muzzle.scale = Vector3.ONE * randf_range(0.7, 1.2)
	_flash = FLASH_TIME


func _refill() -> void:
	var d = _defs[_current]
	var mag := int(d.mag)
	if Match.mode == "zombie":
		var take: int = mini(mag - _ammo[_current], _reserve[_current])
		_ammo[_current] += take
		_reserve[_current] -= take
	else:
		_ammo[_current] = mag
	_emit_ammo()


# Ammo pickup: add a magazine of reserve to every gun (zombie) / refill (dm).
func add_ammo() -> void:
	for i in _defs.size():
		var d = _defs[i]
		if bool(d.get("melee", false)) or bool(d.get("throwable", false)):
			continue
		if Match.mode == "zombie":
			_reserve[i] += int(d.mag)
		else:
			_ammo[i] = int(d.mag)
	_emit_ammo()


func add_grenade(n: int) -> void:
	var gi := _grenade_index()
	if gi >= 0:
		_reserve[gi] += n
		_emit_ammo()


func _grenade_index() -> int:
	for i in _defs.size():
		if bool(_defs[i].get("throwable", false)):
			return i
	return -1


func _throw_grenade() -> void:
	var scene := get_tree().get_first_node_in_group("gameworld")
	if scene == null:
		return
	var g := GRENADE.instantiate()
	scene.add_child(g)
	g.global_position = muzzle.global_position
	var b := global_transform.basis
	g.linear_velocity = -b.z * 14.0 + b.y * 4.0


func _end_reload() -> void:
	_reloading = false


func _equip(index: int) -> void:
	_current = index
	var d = _defs[index]
	if _model:
		_model.queue_free()
	_model = d.scene.instantiate()
	hold.add_child(_model)
	var s := float(d.scale)
	_model.transform = Transform3D(GUN_ORIENT.scaled(Vector3(s, s, s)), Vector3.ZERO)
	_hip_pos = d.pos
	_aim_pos = Vector3(0.0, d.pos.y + 0.04, d.pos.z + 0.10)
	recoil.position = _hip_pos
	recoil.rotation = Vector3.ZERO
	hold.rotation.x = 0.0
	weapon_changed.emit(d.name)
	_emit_ammo()
