extends CanvasLayer
## In-game HUD. The local player connects its signals here on spawn.

@onready var bar: ProgressBar = $Root/HealthBar
@onready var hp_label: Label = $Root/HealthBar/Value
@onready var weapon_label: Label = $Root/WeaponLabel
@onready var ammo_label: Label = $Root/AmmoLabel
@onready var crosshair: Control = $Root/Crosshair
@onready var scope: ColorRect = $Root/Scope
@onready var kill_log: VBoxContainer = $Root/KillLog
@onready var death_label: Label = $Root/DeathLabel
@onready var damage: ColorRect = $Root/Damage
@onready var timer_label: Label = $Root/TimerLabel
@onready var scoreboard: Panel = $Root/Scoreboard
@onready var score_text: Label = $Root/Scoreboard/Text
@onready var winner_label: Label = $Root/WinnerLabel

var _hit := 0.0
var _dir_hit := 0.0
var _dmg_mat: ShaderMaterial


func _ready() -> void:
	_dmg_mat = damage.material as ShaderMaterial


func _process(delta: float) -> void:
	if _hit > 0.0 or _dir_hit > 0.0:
		_hit = maxf(_hit - delta * 1.8, 0.0)
		_dir_hit = maxf(_dir_hit - delta * 2.4, 0.0)
		_dmg_mat.set_shader_parameter("intensity", _hit)
		_dmg_mat.set_shader_parameter("dir_intensity", _dir_hit)
	_update_match()


func _update_match() -> void:
	var over := false
	if Match.mode == "zombie":
		timer_label.text = "PHASE %d" % Match.phase
		winner_label.visible = false
	else:
		timer_label.text = "%d:%02d" % [int(Match.time_left) / 60, int(Match.time_left) % 60]
		over = (not Match.running) and Match.winner != ""
		winner_label.visible = over
		if over:
			winner_label.text = "WINNER: %s\n곧 재시작..." % Match.winner
	var show_sb: bool = over or Input.is_physical_key_pressed(KEY_TAB)
	scoreboard.visible = show_sb
	if show_sb:
		score_text.text = _format_scores()


func _format_scores() -> String:
	var arr := []
	for k in Match.scores:
		arr.append([k, int(Match.scores[k])])
	arr.sort_custom(func(a, b): return a[1] > b[1])
	var s := "킬  (목표 %d)\n──────────────\n" % Match.KILL_TARGET
	for e in arr:
		s += "%-16s %d\n" % [e[0], e[1]]
	return s


func clear_kills() -> void:
	for c in kill_log.get_children():
		c.queue_free()


# angle: hit direction relative to the player's facing (radians, 0 = front).
func flash_damage(angle: float) -> void:
	_hit = 1.0
	_dir_hit = 1.0
	_dmg_mat.set_shader_parameter("dir", angle)
	_dmg_mat.set_shader_parameter("intensity", 1.0)
	_dmg_mat.set_shader_parameter("dir_intensity", 1.0)


func set_scope(on: bool) -> void:
	scope.visible = on
	crosshair.visible = not on


func set_dead(on: bool) -> void:
	death_label.visible = on
	if on:
		death_label.text = "사망 — 5초 후 부활"


func set_invincible(on: bool) -> void:
	death_label.visible = on
	if on:
		death_label.text = "부활 — 3초 무적"


func add_kill(killer: String, victim: String, weapon: String) -> void:
	var line := Label.new()
	line.text = "%s  ⟪%s⟫  %s" % [killer, weapon, victim]
	line.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	line.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
	kill_log.add_child(line)
	while kill_log.get_child_count() > 6:
		kill_log.get_child(0).free()
	await get_tree().create_timer(5.0).timeout
	if is_instance_valid(line):
		line.queue_free()


func set_health(value: int) -> void:
	bar.value = value
	hp_label.text = "HP %d" % value


func set_weapon(weapon_name: String) -> void:
	weapon_label.text = "[ %s ]" % weapon_name


func set_ammo(current: int, maximum: int) -> void:
	if maximum == -2:
		ammo_label.text = "수류탄 %d" % current
	elif maximum < 0:
		ammo_label.text = "∞"
	else:
		ammo_label.text = "%d / %d" % [current, maximum]
