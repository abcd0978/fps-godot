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
const ROCKET := preload("res://scenes/rocket.tscn")
# Orient Quaternius guns (barrel = model +X) to Godot view space (forward -Z).
# columns = images of model X/Y/Z axes. up stays +Y (fixes the 90° roll).
# If a gun points backwards, negate the x column; if it rolls the wrong way,
# swap the sign on the y/z columns.
const GUN_ORIENT := Basis(Vector3(0, 0, -1), Vector3(0, 1, 0), Vector3(1, 0, 0))

# name, model, damage, cooldown, magazine, reserve, view scale + hip position.
# "spread" = hip-fire cone half-angle in radians (ADS tightens it). Each weapon
# now has its own real (Quaternius CC0) model; scales are AABB-calibrated so the
# guns read at a consistent in-hand size. Keys 1-9,0 → indices 0-9; Minigun (10)
# is pickup-only and reuses the rifle model (dark, oversized) for a heavy look.
const Q_PISTOL := preload("res://assets/weapons/real/q_pistol.glb")
const Q_SMG := preload("res://assets/weapons/real/q_smg.glb")
const Q_RIFLE := preload("res://assets/weapons/real/q_rifle.glb")
const Q_BULLPUP := preload("res://assets/weapons/real/q_bullpup.glb")
const Q_LMG := preload("res://assets/weapons/real/q_lmg.glb")
const Q_SNIPER := preload("res://assets/weapons/real/q_sniper.glb")
const Q_REVOLVER := preload("res://assets/weapons/real/q_revolver.glb")
const Q_ROCKET := preload("res://assets/weapons/real/q_rocket.glb")
const Q_LASER := preload("res://assets/weapons/real/q_laser.glb")
const SHOTGUN := preload("res://assets/weapons/real/shotgun.glb")
const KNIFE := preload("res://assets/weapons/real/knife.glb")
const RIFLE := preload("res://assets/weapons/real/rifle.glb")
const GRENADE_HELD := preload("res://scenes/grenade_held.tscn")

# This launcher model's barrel runs along +Z, not +X like the Quaternius guns,
# so it needs its own orientation (180° about Y → model +Z points to view -Z).
const ROCKET_ORIENT := Basis(Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, -1))

var _defs := [
	{"name": "Pistol", "scene": Q_PISTOL, "damage": 18, "cooldown": 0.28, "mag": 12, "reserve": 48, "scale": 0.22, "pos": Vector3(0.22, -0.29, -0.5), "spread": 0.040},
	{"name": "SMG", "scene": Q_SMG, "damage": 14, "cooldown": 0.07, "mag": 35, "reserve": 140, "scale": 0.27, "pos": Vector3(0.23, -0.30, -0.48), "spread": 0.060},
	{"name": "Rifle", "scene": Q_RIFLE, "damage": 28, "cooldown": 0.12, "mag": 30, "reserve": 120, "scale": 0.29, "pos": Vector3(0.24, -0.31, -0.55), "spread": 0.038},
	{"name": "Carbine", "scene": Q_BULLPUP, "damage": 34, "cooldown": 0.17, "mag": 24, "reserve": 96, "scale": 0.28, "pos": Vector3(0.24, -0.31, -0.54), "spread": 0.026},
	{"name": "LMG", "scene": Q_LMG, "damage": 26, "cooldown": 0.09, "mag": 80, "reserve": 160, "scale": 0.31, "pos": Vector3(0.26, -0.33, -0.6), "spread": 0.072},
	{"name": "Shotgun", "scene": SHOTGUN, "damage": 62, "cooldown": 0.80, "mag": 7, "reserve": 35, "scale": 0.30, "pos": Vector3(0.24, -0.31, -0.52), "spread": 0.11},
	{"name": "Sniper", "scene": Q_SNIPER, "damage": 110, "cooldown": 1.3, "mag": 5, "reserve": 25, "scale": 0.29, "pos": Vector3(0.26, -0.29, -0.58), "scope": true, "ads_fov": 16.0, "spread": 0.022},
	{"name": "Magnum", "scene": Q_REVOLVER, "damage": 75, "cooldown": 0.55, "mag": 6, "reserve": 36, "scale": 0.31, "pos": Vector3(0.22, -0.29, -0.5), "spread": 0.030},
	{"name": "Rocket", "scene": Q_ROCKET, "damage": 0, "cooldown": 0.85, "mag": 4, "reserve": 12, "scale": 7.0, "pos": Vector3(0.22, -0.28, -0.5), "orient": ROCKET_ORIENT, "rocket": true},
	{"name": "Laser", "scene": Q_LASER, "damage": 42, "cooldown": 0.10, "mag": 60, "reserve": 180, "scale": 0.66, "pos": Vector3(0.24, -0.30, -0.55), "spread": 0.004, "tint": Color(0.4, 0.9, 1.0), "laser": true},
	{"name": "Knife", "scene": KNIFE, "damage": 70, "cooldown": 0.5, "mag": 1, "scale": 12.0, "pos": Vector3(0.2, -0.26, -0.45), "melee": true, "range": 2.6},
	{"name": "Grenade", "scene": GRENADE_HELD, "damage": 0, "cooldown": 0.8, "mag": 1, "reserve": 2, "scale": 1.0, "pos": Vector3(0.22, -0.28, -0.5), "throwable": true},
	{"name": "Minigun", "scene": RIFLE, "damage": 24, "cooldown": 0.045, "mag": 200, "reserve": 0, "scale": 0.40, "pos": Vector3(0.27, -0.34, -0.62), "spread": 0.055, "tint": Color(0.24, 0.24, 0.28), "no_reload": true},
]

const MINIGUN_INDEX := 12

# How much aiming-down-sights tightens spread and tames recoil.
const ADS_SPREAD := 0.16    # ADS spread = hip spread * this
const ADS_RECOIL := 0.45    # ADS recoil = hip recoil * this

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

# Per-weapon upgrade levels (Boxhead-style): damage / fire-rate / magazine.
const UP_MAX := 5
var _dmg_lv: Array[int] = []
var _rate_lv: Array[int] = []
var _mag_lv: Array[int] = []


var _unlocked: Array[bool] = []  # zombie mode: weapons must be picked up first


func _ready() -> void:
	for d in _defs:
		_dmg_lv.append(0)
		_rate_lv.append(0)
		_mag_lv.append(0)
		_unlocked.append(false)
	for d in _defs:
		_ammo.append(int(d.get("mag", 1)))
		_reserve.append(int(d.get("reserve", 0)))
	# Start with only the pistol, knife and grenades; everything else is found.
	for i in [0, _defs.size() - 3, _defs.size() - 2]:
		if i >= 0 and i < _unlocked.size():
			_unlocked[i] = true
	_equip(0)


# In deathmatch every weapon is available; in zombie mode you must find them.
func _locked(i: int) -> bool:
	return Match.mode == "zombie" and not _unlocked[i]


func is_unlocked_list() -> Array:
	var arr: Array = []
	for i in mini(MINIGUN_INDEX, _defs.size()):
		arr.append(not _locked(i))
	return arr


# Unlock a random still-locked selectable weapon. Returns its index, or -1.
func unlock_random() -> int:
	var locked: Array[int] = []
	for i in mini(MINIGUN_INDEX, _defs.size()):
		if not _unlocked[i]:
			locked.append(i)
	if locked.is_empty():
		return -1
	var wi: int = locked[randi() % locked.size()]
	_unlocked[wi] = true
	return wi


# --- Upgrade effective stats ---
func _eff_damage(i: int) -> int:
	return int(round(int(_defs[i].damage) * (1.0 + 0.25 * _dmg_lv[i])))


func _eff_cooldown(i: int) -> float:
	return float(_defs[i].cooldown) * pow(0.85, _rate_lv[i])  # faster per level


func _eff_mag(i: int) -> int:
	var base := int(_defs[i].mag)
	return base + _mag_lv[i] * maxi(1, int(round(base * 0.3)))


# Upgrade item: pick a random weapon and a random stat (damage/rate/mag) and
# bump it a level. Returns a short description (or "" if everything is maxed).
func upgrade_random() -> String:
	var stat_names := ["데미지", "연사력", "탄창"]
	for _attempt in 24:
		var wi := randi() % MINIGUN_INDEX          # any selectable weapon
		var kind := randi() % 3
		var lv: Array[int] = [_dmg_lv, _rate_lv, _mag_lv][kind]
		if lv[wi] < UP_MAX:
			lv[wi] += 1
			if kind == 2 and wi == _current:
				_ammo[_current] = _eff_mag(_current)  # top up to the new magazine
			if wi == _current:
				_emit_ammo()
			return "%s %s Lv%d" % [_defs[wi].name, stat_names[kind], lv[wi]]
	return ""


# Levels for the current weapon (damage, rate, mag) — for the HUD.
func current_upgrades() -> Array:
	return [_dmg_lv[_current], _rate_lv[_current], _mag_lv[_current]]


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


# Names of the wheel-selectable weapons (keys 1-9,0 → indices 0-9). The pickup-
# only Minigun is excluded.
func selectable_names() -> PackedStringArray:
	var arr: PackedStringArray = []
	for i in mini(MINIGUN_INDEX, _defs.size()):  # everything except the pickup-only Minigun
		arr.append(_defs[i].name)
	return arr


func current_ammo() -> int:
	return _ammo[_current]


func current_mag() -> int:
	return _eff_mag(_current)


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
	if _locked(index):
		return  # not picked up yet (zombie mode)
	_equip(index)


func reload() -> void:
	if _reloading:
		return
	var d = _defs[_current]
	if bool(d.get("melee", false)) or bool(d.get("throwable", false)) or bool(d.get("no_reload", false)):
		return
	if _ammo[_current] >= _eff_mag(_current):
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
	elif bool(d.get("no_reload", false)):
		ammo_changed.emit(_ammo[_current], int(d.mag))  # e.g. "153 / 200", no reload
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
		_cooldown = _eff_cooldown(_current)
		_reserve[_current] -= 1
		_emit_ammo()
		_throw_grenade()
		recoil.position.z += KICK_BACK
		return KICK_PITCH

	# Rocket launcher: consume a round and fire an explosive projectile.
	if bool(d.get("rocket", false)):
		if _ammo[_current] <= 0:
			return 0.0
		_cooldown = _eff_cooldown(_current)
		_ammo[_current] -= 1
		_emit_ammo()
		_show_flash()
		_fire_rocket()
		recoil.position.z += KICK_BACK * 2.0
		recoil.rotation.x = -KICK_PITCH * 2.5
		return KICK_PITCH * 2.5

	var melee := bool(d.get("melee", false))
	if not melee and _ammo[_current] <= 0:
		return 0.0
	_cooldown = _eff_cooldown(_current)
	if not melee:
		_ammo[_current] -= 1
		_emit_ammo()

	# ADS tames the recoil; hip fire kicks full strength.
	var rscale := ADS_RECOIL if _aiming else 1.0
	recoil.position.z += KICK_BACK * rscale
	recoil.rotation.x = -KICK_PITCH * rscale
	if not melee:
		_show_flash()
		_eject_shell()

	# Aim the ray inside the accuracy cone (zero for melee). Hip fire is loose,
	# aiming down the sights is near pin-point.
	_aim_raycast(0.0 if melee else _current_spread(d))
	if bool(d.get("laser", false)):
		_fire_laser(_eff_damage(_current))
		return KICK_PITCH * rscale
	if raycast.is_colliding():
		var point: Vector3 = raycast.get_collision_point()
		if global_position.distance_to(point) <= float(d.get("range", 1000.0)):
			var hit = raycast.get_collider()
			if hit:
				var dmg := _eff_damage(_current)
				if hit.has_method("take_damage"):
					hit.take_damage.rpc_id(hit.get_multiplayer_authority(), dmg, shooter_name, current_name(), global_position)
					Net.spawn_blood.rpc(point, raycast.get_collision_normal())
				elif hit.has_method("hit"):
					hit.hit.rpc()
	return KICK_PITCH * rscale


# Current shot spread (radians). Aiming down sights tightens it dramatically.
func _current_spread(d: Dictionary) -> float:
	var base := float(d.get("spread", 0.04))
	return base * ADS_SPREAD if _aiming else base


# Point the ray at a random spot inside the spread cone, then refresh it so the
# shot reads this frame's deflected direction (not the last physics tick).
func _aim_raycast(spread: float) -> void:
	if spread <= 0.0:
		raycast.target_position = Vector3(0, 0, -1000)
	else:
		var ang := randf() * TAU
		var rad := sqrt(randf()) * spread
		var off := Vector2(cos(ang), sin(ang)) * tan(rad) * 1000.0
		raycast.target_position = Vector3(off.x, off.y, -1000.0)
	raycast.force_raycast_update()


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
	var mag := _eff_mag(_current)
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
		if bool(d.get("melee", false)) or bool(d.get("throwable", false)) or bool(d.get("no_reload", false)):
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


# Minigun pickup: load a full 200-round drum and switch to it immediately.
func give_minigun() -> void:
	if MINIGUN_INDEX >= _defs.size():
		return
	_unlocked[MINIGUN_INDEX] = true
	_ammo[MINIGUN_INDEX] = int(_defs[MINIGUN_INDEX].mag)
	_equip(MINIGUN_INDEX)


# Spawn an explosive rocket travelling along the camera forward.
func _fire_rocket() -> void:
	var scene := get_tree().get_first_node_in_group("gameworld")
	if scene == null:
		return
	var r := ROCKET.instantiate()
	scene.add_child(r)
	r.global_position = muzzle.global_position
	r.dir = (-global_transform.basis.z).normalized()


# Instant laser bolt: hit the first thing the ray meets and draw a glowing beam.
func _fire_laser(dmg: int) -> void:
	var end: Vector3 = muzzle.global_position - global_transform.basis.z * 200.0
	if raycast.is_colliding():
		end = raycast.get_collision_point()
		var hit = raycast.get_collider()
		if hit:
			if hit.has_method("take_damage"):
				hit.take_damage.rpc_id(hit.get_multiplayer_authority(), dmg, shooter_name, "Laser", global_position)
				Net.spawn_blood.rpc(end, raycast.get_collision_normal())
			elif hit.has_method("hit"):
				hit.hit.rpc()
	_spawn_beam(muzzle.global_position, end)


# Brief glowing cylinder between two points (cosmetic, self-frees).
func _spawn_beam(a: Vector3, b: Vector3) -> void:
	var scene := get_tree().get_first_node_in_group("gameworld")
	if scene == null or a.distance_to(b) < 0.05:
		return
	var beam := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.04
	mesh.bottom_radius = 0.04
	mesh.height = a.distance_to(b)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.6, 0.95, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(0.4, 0.9, 1.0)
	mat.emission_energy_multiplier = 3.0
	mesh.material = mat
	beam.mesh = mesh
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	scene.add_child(beam)
	beam.look_at_from_position((a + b) * 0.5, b, Vector3.UP)
	beam.rotate_object_local(Vector3(1, 0, 0), PI * 0.5)  # cylinder Y axis → beam direction
	var tw := beam.create_tween()
	tw.tween_interval(0.05)
	tw.tween_callback(beam.queue_free)


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
	var orient: Basis = d.get("orient", GUN_ORIENT)
	_model.transform = Transform3D(orient.scaled(Vector3(s, s, s)), Vector3.ZERO)
	# Tint same-model variants so the arsenal looks distinct.
	if d.has("tint"):
		var mat := StandardMaterial3D.new()
		mat.albedo_color = d["tint"]
		mat.metallic = 0.4
		mat.roughness = 0.5
		for mi in _model.find_children("*", "MeshInstance3D", true, false):
			mi.material_override = mat
	_hip_pos = d.pos
	# Iron sights: centre the gun and raise it to the sight line. A per-weapon
	# "ads_pos" can override this for guns whose sights sit higher/lower.
	_aim_pos = d.get("ads_pos", Vector3(0.0, d.pos.y + 0.075, d.pos.z + 0.17))
	recoil.position = _hip_pos
	recoil.rotation = Vector3.ZERO
	hold.rotation.x = 0.0
	weapon_changed.emit(d.name)
	_emit_ammo()
