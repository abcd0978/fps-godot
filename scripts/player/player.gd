extends CharacterBody3D
## First-person player controller: movement, sprint (double-tap W), look,
## health, aim-down-sights, recoil, firing, an animated 3rd-person body (seen
## by other players), name, kill reporting and 5s respawn.

const WALK_SPEED := 6.0
const SPRINT_SPEED := 11.0
const JUMP_VELOCITY := 5.5
const GRAVITY := 14.0
const MOUSE_SENS := 0.0025
const DOUBLE_TAP_MS := 280
const MAX_HEALTH := 100
const HIP_FOV := 75.0
const RESPAWN_TIME := 5.0

# Boxhead-style points economy (zombie mode): earn per kill, spend on placeables
# and upgrades.
const MINE_SCENE := preload("res://scenes/mine.tscn")
const BARRICADE_SCENE := preload("res://scenes/barricade.tscn")
const POINTS_PER_KILL := 15
const MINE_COST := 40
const BARRICADE_COST := 80
const DURA_COST := 150

signal health_changed(value: int)

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var weapon: Node3D = $Head/Camera3D/Weapon
@onready var visual: Node3D = $Visual

var health := MAX_HEALTH
var pname := "Player"

var _sprinting := false
var _last_w_tap := -10000
var _w_was_down := false
var _recoil_pitch := 0.0
var _recoil_yaw := 0.0
var _aiming := false
var _scoped := false
var _dead := false
var _invincible := false
var _bob := 0.0
var _bob_amt := 0.0
var _bob_pitch := 0.0
var _bob_yaw := 0.0
var _last_pos := Vector3.ZERO
var _hud: CanvasLayer = null
var _wheel_open := false
var _wheel_vec := Vector2.ZERO
var _wheel_names: PackedStringArray = []
var _wheel_sel := 0
var points := 0
var _barricade_dura := 0


func _enter_tree() -> void:
	set_multiplayer_authority(name.to_int())


func _ready() -> void:
	add_to_group("player")
	Crash.breadcrumb("player ready id=%s authority=%s" % [name, is_multiplayer_authority()])
	visual.build(name.to_int())  # stable skin per peer id (same on every client)
	_last_pos = global_position
	if is_multiplayer_authority():
		camera.current = true
		camera.fov = HIP_FOV
		visual.visible = false  # don't render our own body in first person
		weapon.ignore_collider(self)
		pname = Net.player_name
		weapon.shooter_name = pname
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		_connect_hud()
	else:
		weapon.visible = false


func _connect_hud() -> void:
	var hud := get_tree().get_first_node_in_group("hud")
	if hud == null:
		return
	_hud = hud
	health_changed.connect(hud.set_health)
	weapon.weapon_changed.connect(hud.set_weapon)
	weapon.ammo_changed.connect(hud.set_ammo)
	hud.set_health(health)
	hud.set_weapon(weapon.current_name())
	hud.set_ammo(weapon.current_ammo(), weapon.current_mag())
	weapon.weapon_changed.connect(func(_n): _update_points_hud())  # show this gun's levels
	_update_points_hud()


# Runs on every peer: drives the 3rd-person animation from synced state.
func _process(delta: float) -> void:
	if health <= 0:
		visual.play_die()
	else:
		visual.revive()
		var d := global_position - _last_pos
		visual.set_locomotion(Vector2(d.x, d.z).length() / maxf(delta, 0.001))
	_last_pos = global_position


func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority() or _dead:
		return

	# Weapon wheel: hold F to open, aim the mouse, release F to equip.
	if event is InputEventKey and event.keycode == KEY_F:
		if event.pressed and not event.echo:
			_open_wheel()
		elif not event.pressed:
			_close_wheel()
		return

	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if _wheel_open:
			_wheel_vec += event.relative
			if _wheel_vec.length() > 140.0:
				_wheel_vec = _wheel_vec.normalized() * 140.0
			_update_wheel_sel()
			return
		var sens: float = Settings.mouse_sens
		if _scoped:
			sens *= 0.35
		elif _aiming:
			sens *= 0.6
		rotate_y(-event.relative.x * sens)
		head.rotate_x(-event.relative.y * sens)
		head.rotation.x = clamp(head.rotation.x, -1.4, 1.4)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_1: weapon.equip(0)
			KEY_2: weapon.equip(1)
			KEY_3: weapon.equip(2)
			KEY_4: weapon.equip(3)
			KEY_5: weapon.equip(4)
			KEY_6: weapon.equip(5)
			KEY_7: weapon.equip(6)
			KEY_8: weapon.equip(7)
			KEY_9: weapon.equip(8)
			KEY_0: weapon.equip(9)
			KEY_R: weapon.reload()
			KEY_Z: _place_mine()
			KEY_X: _place_barricade()
			KEY_H: _buy_barricade_durability()
			KEY_ESCAPE: Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority() or _dead:
		return

	_update_sprint()

	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	elif Input.is_physical_key_pressed(KEY_SPACE):
		velocity.y = JUMP_VELOCITY

	var input_dir := _movement_input()
	var dir := (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()
	var speed := SPRINT_SPEED if _sprinting else WALK_SPEED
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed
	move_and_slide()

	_handle_combat(delta)


func _handle_combat(delta: float) -> void:
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED

	_aiming = captured and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	_scoped = _aiming and weapon.has_scope()
	weapon.set_aiming(_aiming)
	weapon.show_model(not _scoped)
	if _hud:
		_hud.set_scope(_scoped)
		_hud.set_crosshair(not _aiming)  # iron sights: no crosshair while aiming
	var target_fov: float = weapon.aim_fov() if _aiming else HIP_FOV
	camera.fov = lerp(camera.fov, target_fov, delta * 12.0)

	if captured and not _wheel_open and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		var kick: float = weapon.fire()
		if kick > 0.0:
			_recoil_pitch += kick
			_recoil_yaw += randf_range(-kick * 0.4, kick * 0.4)

	_recoil_pitch = lerp(_recoil_pitch, 0.0, delta * 10.0)
	_recoil_yaw = lerp(_recoil_yaw, 0.0, delta * 10.0)
	_apply_bob(delta)
	camera.rotation.x = -_recoil_pitch + _bob_pitch
	camera.rotation.y = _recoil_yaw + _bob_yaw


# Head/weapon bob while moving — stronger when sprinting, damped when aiming.
func _apply_bob(delta: float) -> void:
	var moving := is_on_floor() and Vector2(velocity.x, velocity.z).length() > 0.5
	var target := 0.0
	if moving:
		target = 1.0 if _sprinting else 0.4
	if _aiming:
		target *= 0.2
	_bob_amt = lerp(_bob_amt, target, delta * 8.0)
	_bob += delta * (14.0 if _sprinting else 9.0)
	var x := cos(_bob) * 0.06 * _bob_amt
	var y := absf(sin(_bob)) * 0.05 * _bob_amt
	weapon.position = Vector3(x, -y, 0.0)
	_bob_pitch = -y * 0.15
	_bob_yaw = x * 0.15


# --- Weapon wheel ---
func _open_wheel() -> void:
	if _wheel_open:
		return
	_wheel_names = weapon.selectable_names()
	if _wheel_names.is_empty():
		return
	_wheel_open = true
	_wheel_vec = Vector2.ZERO
	_wheel_sel = -1  # nothing selected until the mouse picks a direction
	if _hud:
		_hud.open_weapon_wheel(_wheel_names, _wheel_sel, weapon.is_unlocked_list())


func _close_wheel() -> void:
	if not _wheel_open:
		return
	_wheel_open = false
	if _wheel_sel >= 0 and _wheel_sel < _wheel_names.size():
		weapon.equip(_wheel_sel)
	if _hud:
		_hud.close_weapon_wheel()


# Map the accumulated mouse vector to a sector (index 0 at the top, clockwise).
func _update_wheel_sel() -> void:
	var n := _wheel_names.size()
	if n == 0:
		return
	if _wheel_vec.length() >= 28.0:  # deadzone near the hub keeps the last pick
		var ang := atan2(_wheel_vec.y, _wheel_vec.x) + PI * 0.5
		_wheel_sel = int(round(fposmod(ang, TAU) / (TAU / n))) % n
	if _hud:
		_hud.update_weapon_wheel(_wheel_sel)


# --- Points economy (Boxhead-style) ---
func add_points(n: int) -> void:
	points += n
	_update_points_hud()


func _place_mine() -> void:
	if points < MINE_COST:
		return
	var scene := get_tree().get_first_node_in_group("gameworld")
	if scene == null:
		return
	var m := MINE_SCENE.instantiate()
	scene.add_child(m)
	var fwd := -global_transform.basis.z
	m.global_position = global_position + fwd * 1.8 + Vector3.DOWN * 0.9
	points -= MINE_COST
	_update_points_hud()


func _place_barricade() -> void:
	if points < BARRICADE_COST:
		return
	var scene := get_tree().get_first_node_in_group("gameworld")
	if scene == null:
		return
	var b := BARRICADE_SCENE.instantiate()
	scene.add_child(b)
	var fwd := -global_transform.basis.z
	b.global_position = global_position + fwd * 3.0
	b.rotation.y = rotation.y
	b.setup(_barricade_dura)
	points -= BARRICADE_COST
	_update_points_hud()


func _buy_barricade_durability() -> void:
	if points < DURA_COST or _barricade_dura >= 5:
		return
	_barricade_dura += 1
	points -= DURA_COST
	_update_points_hud()


func _update_points_hud() -> void:
	if _hud and _hud.has_method("set_points"):
		_hud.set_points(points, _barricade_dura, weapon.current_upgrades())


func _movement_input() -> Vector2:
	var d := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_W):
		d.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S):
		d.y += 1.0
	if Input.is_physical_key_pressed(KEY_A):
		d.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D):
		d.x += 1.0
	return d


func _update_sprint() -> void:
	var w := Input.is_physical_key_pressed(KEY_W)
	if w and not _w_was_down:
		var now := Time.get_ticks_msec()
		if now - _last_w_tap <= DOUBLE_TAP_MS:
			_sprinting = true
		_last_w_tap = now
	if not w:
		_sprinting = false
	_w_was_down = w


# Called by an attacker's weapon/bot. Runs on this player's authority peer only.
@rpc("any_peer", "call_local", "reliable")
func take_damage(amount: int, attacker_name: String, weapon_name: String, attacker_pos: Vector3) -> void:
	if not is_multiplayer_authority() or _dead or _invincible:
		return
	# No friendly fire in zombie survival — only zombies can hurt players, EXCEPT
	# explosives, which catch the player too (mind your own blast radius).
	if Match.mode == "zombie" and attacker_name != "Zombie" and weapon_name not in ["Rocket", "Grenade", "Mine"]:
		return
	if _hud:
		var local := global_transform.affine_inverse() * attacker_pos
		_hud.flash_damage(atan2(local.x, -local.z))
	health = max(health - amount, 0)
	if health == 0:
		_die(attacker_name, weapon_name)
	else:
		health_changed.emit(health)


func _die(attacker_name: String, weapon_name: String) -> void:
	_dead = true
	velocity = Vector3.ZERO
	health_changed.emit(0)
	Net.report_kill.rpc(attacker_name, pname, weapon_name)
	if _hud:
		_hud.set_dead(true)
	await get_tree().create_timer(RESPAWN_TIME).timeout
	_respawn()


# --- Pickups (called by the server on this player's authority) ---
@rpc("any_peer", "call_local", "reliable")
func add_health(amount: int) -> void:
	if not is_multiplayer_authority() or _dead:
		return
	health = min(health + amount, MAX_HEALTH)
	health_changed.emit(health)


@rpc("any_peer", "call_local", "reliable")
func give_ammo() -> void:
	if is_multiplayer_authority():
		weapon.add_ammo()


@rpc("any_peer", "call_local", "reliable")
func give_weapon(_index: int) -> void:
	if is_multiplayer_authority():
		var wi: int = weapon.unlock_random()  # find a new weapon
		weapon.add_ammo()
		if wi >= 0:
			weapon.equip(wi)


@rpc("any_peer", "call_local", "reliable")
func give_grenade(n: int) -> void:
	if is_multiplayer_authority():
		weapon.add_grenade(n)


@rpc("any_peer", "call_local", "reliable")
func give_minigun() -> void:
	if is_multiplayer_authority():
		weapon.give_minigun()


# Upgrade item: a random weapon gets a random stat bump.
@rpc("any_peer", "call_local", "reliable")
func give_upgrade() -> void:
	if not is_multiplayer_authority():
		return
	var msg: String = weapon.upgrade_random()
	_update_points_hud()
	if msg != "" and _hud and _hud.has_method("flash_upgrade"):
		_hud.flash_upgrade(msg)


# Called by the Match manager when a new round starts.
func match_reset() -> void:
	_dead = false
	_respawn()


func _respawn() -> void:
	health = MAX_HEALTH
	# random spawn across the arena
	position = Vector3(randf_range(-28.0, 28.0), 3.0, randf_range(-28.0, 28.0))
	velocity = Vector3.ZERO
	_dead = false
	_invincible = true
	health_changed.emit(health)
	if _hud:
		_hud.set_dead(false)
		_hud.set_invincible(true)
	await get_tree().create_timer(3.0).timeout
	_invincible = false
	if _hud:
		_hud.set_invincible(false)
