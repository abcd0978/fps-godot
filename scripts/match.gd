extends Node
## Deathmatch (free-for-all) match manager. Autoload "Match".
## Scores come from Net.report_kill (already broadcast to every peer), so the
## scores dict stays consistent everywhere. The server owns win/timer/restart.

const KILL_TARGET := 20
const MATCH_TIME := 300.0  # 5 minutes

var scores := {}            # name -> kills
var time_left := MATCH_TIME
var running := false
var winner := ""
var mode := "dm"            # "dm" or "zombie"
var phase := 0              # zombie wave number


func set_mode(m: String) -> void:
	_set_mode.rpc(m)


@rpc("any_peer", "call_local", "reliable")
func _set_mode(m: String) -> void:
	mode = m


func set_phase(p: int) -> void:
	_set_phase.rpc(p)


@rpc("any_peer", "call_local", "reliable")
func _set_phase(p: int) -> void:
	phase = p


func _ready() -> void:
	set_process(false)


# Called by the host (single or multiplayer) to (re)start a match.
func start_match() -> void:
	_begin.rpc()


@rpc("any_peer", "call_local", "reliable")
func _begin() -> void:
	scores.clear()
	time_left = MATCH_TIME
	winner = ""
	phase = 0
	running = true
	set_process(true)


func _process(delta: float) -> void:
	if not running or mode != "dm":
		return
	time_left = maxf(time_left - delta, 0.0)
	if multiplayer.is_server() and time_left <= 0.0:
		_end.rpc(_leader())


# Called from Net.report_kill on every peer, so scoring stays in sync.
func register_kill(killer: String) -> void:
	if not running or killer == "":
		return
	scores[killer] = int(scores.get(killer, 0)) + 1
	if mode == "dm" and multiplayer.is_server() and int(scores[killer]) >= KILL_TARGET:
		_end.rpc(killer)


@rpc("any_peer", "call_local", "reliable")
func _end(win_name: String) -> void:
	running = false
	winner = win_name
	set_process(false)
	if multiplayer.is_server():
		_schedule_restart()


func _schedule_restart() -> void:
	await get_tree().create_timer(10.0).timeout
	_begin.rpc()
	_respawn_all.rpc()


@rpc("any_peer", "call_local", "reliable")
func _respawn_all() -> void:
	for p in get_tree().get_nodes_in_group("player"):
		if p.is_multiplayer_authority() and p.has_method("match_reset"):
			p.match_reset()
	var hud := get_tree().get_first_node_in_group("hud")
	if hud:
		hud.clear_kills()


# Server sends current match state to a late-joining peer.
func sync_to(id: int) -> void:
	_sync.rpc_id(id, scores, time_left, winner, running, mode, phase)


@rpc("any_peer", "reliable")
func _sync(s: Dictionary, t: float, w: String, r: bool, m: String, ph: int) -> void:
	scores = s
	time_left = t
	winner = w
	running = r
	mode = m
	phase = ph
	set_process(r)


func _leader() -> String:
	var best := ""
	var best_v := -1
	for k in scores:
		if int(scores[k]) > best_v:
			best_v = int(scores[k])
			best = k
	return best
