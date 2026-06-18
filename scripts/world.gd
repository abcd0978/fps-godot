extends Node3D
## Main scene controller: lobby menu (Main → Mode/Multi) + game start.

@onready var menu: Control = $UI/Menu
@onready var main_panel: VBoxContainer = $UI/Menu/Main
@onready var multi_panel: VBoxContainer = $UI/Menu/Multi
@onready var mode_panel: VBoxContainer = $UI/Menu/Mode
@onready var status: Label = $UI/Menu/Status
@onready var bots: Node3D = $Bots
@onready var zombies: Node3D = $Zombies
@onready var name_edit: LineEdit = $UI/Menu/Multi/NameEdit
@onready var ip_edit: LineEdit = $UI/Menu/Multi/IpEdit

var _multi := false  # is the pending host a multiplayer host?


func _ready() -> void:
	Net.players_root = $Players
	main_panel.get_node("SingleBtn").pressed.connect(_on_single)
	main_panel.get_node("MultiBtn").pressed.connect(_on_multi)
	main_panel.get_node("SettingsBtn").pressed.connect(Settings.open_ui)
	multi_panel.get_node("HostBtn").pressed.connect(_on_multi_host)
	multi_panel.get_node("JoinBtn").pressed.connect(_on_join)
	multi_panel.get_node("BackBtn").pressed.connect(_back_to_main)
	mode_panel.get_node("DmBtn").pressed.connect(_start.bind("dm"))
	mode_panel.get_node("ZombieBtn").pressed.connect(_start.bind("zombie"))
	mode_panel.get_node("ModeBackBtn").pressed.connect(_back_to_main)
	multi_panel.get_node("MyIp").text = "내 IP: %s  (호스트가 알려주세요)" % _local_ip()


func _show_only(which: String) -> void:
	main_panel.visible = which == "main"
	multi_panel.visible = which == "multi"
	mode_panel.visible = which == "mode"


func _back_to_main() -> void:
	_show_only("main")


func _on_single() -> void:
	_multi = false
	Net.player_name = "Player"
	_show_only("mode")


func _on_multi() -> void:
	_show_only("multi")


func _on_multi_host() -> void:
	_multi = true
	Net.player_name = _chosen_name()
	_show_only("mode")


func _on_join() -> void:
	Net.player_name = _chosen_name()
	if Net.join(_chosen_ip()):
		menu.hide()
	else:
		status.text = "접속 실패"


# Picked a mode -> host and start (solo or multiplayer host).
func _start(mode: String) -> void:
	if not Net.host():
		status.text = "시작 실패 (포트 사용 중?)"
		return
	Match.set_mode(mode)
	Match.start_match()
	if mode == "zombie":
		zombies.start()
	elif not _multi:
		bots.start()  # deathmatch single-player bots
	menu.hide()


func _chosen_name() -> String:
	var n := name_edit.text.strip_edges()
	return n if n != "" else "Player"


func _chosen_ip() -> String:
	var ip := ip_edit.text.strip_edges()
	return ip if ip != "" else "127.0.0.1"


func _local_ip() -> String:
	for a in IP.get_local_addresses():
		if a.get_slice_count(".") == 4 and not a.begins_with("127.") and not a.begins_with("169.254"):
			return a
	return "127.0.0.1"
