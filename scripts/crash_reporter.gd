extends Node
## Crash / error reporter (autoload "Crash").
##
## Writes a per-session log under user://logs/ with engine + system info, a
## ring buffer of "breadcrumbs" (where the game last was), and on-demand
## GDScript stack traces. Combined with engine file logging (see project.godot
## [debug]) this captures both GDScript errors and native crash backtraces.
##
## Usage from anywhere:
##   Crash.breadcrumb("entered wave 3")        # record context cheaply
##   Crash.report("nil player in radar")       # dump full stack + breadcrumbs
##
## On Windows the log folder is:
##   %APPDATA%\Godot\app_userdata\AluxStrike\logs\   (editor)
##   %APPDATA%\AluxStrike\logs\                       (exported build)

const LOG_DIR := "user://logs"
const MAX_BREADCRUMBS := 50

var _path := ""
var _file: FileAccess = null
var _crumbs: PackedStringArray = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # keep logging even if the tree pauses
	_open()
	_header()


func _open() -> void:
	DirAccess.make_dir_recursive_absolute(LOG_DIR)
	var stamp := Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	_path = "%s/crash_%s.log" % [LOG_DIR, stamp]
	_file = FileAccess.open(_path, FileAccess.WRITE)


func _header() -> void:
	_line("==================== AluxStrike session ====================")
	_line("time      : %s" % Time.get_datetime_string_from_system())
	_line("engine    : %s" % Engine.get_version_info().get("string", "?"))
	_line("os        : %s %s" % [OS.get_name(), OS.get_version()])
	_line("cpu       : %s (%d threads)" % [OS.get_processor_name(), OS.get_processor_count()])
	_line("gpu       : %s" % RenderingServer.get_video_adapter_name())
	_line("gpu api   : %s" % RenderingServer.get_video_adapter_api_version())
	_line("debug build: %s  (symbols/GDScript stack need a debug build or the editor)" % OS.is_debug_build())
	_line("log file  : %s" % ProjectSettings.globalize_path(_path))
	_line("============================================================")


# Cheap context marker. Kept in memory; written to the log only on report().
func breadcrumb(msg: String) -> void:
	_crumbs.append("[%s] %s" % [Time.get_time_string_from_system(), msg])
	while _crumbs.size() > MAX_BREADCRUMBS:
		_crumbs.remove_at(0)


# Dump a full report: the GDScript call stack at this point plus recent
# breadcrumbs. Safe to call from anywhere; flushes the log immediately.
func report(reason: String) -> void:
	_line("")
	_line("########## CRASH REPORT ##########")
	_line("reason    : %s" % reason)
	_line("time      : %s" % Time.get_datetime_string_from_system())
	_line("--- GDScript stack (outermost first) ---")
	var stack := get_stack()
	if stack.is_empty():
		_line("  (empty — release build strips the GDScript stack; run a debug")
		_line("   build or the editor to get source:line:function frames)")
	else:
		for i in stack.size():
			var f: Dictionary = stack[i]
			_line("  #%-2d %s:%d  ->  %s()" % [i, f.get("source", "?"), f.get("line", -1), f.get("function", "?")])
	_line("--- recent breadcrumbs (oldest first) ---")
	for c in _crumbs:
		_line("  " + c)
	_line("########## END REPORT ##########")
	_flush()


func _line(s: String) -> void:
	print(s)  # also goes to stdout -> engine godot.log
	if _file:
		_file.store_line(s)
		_file.flush()  # flush now so a hard crash still leaves the log on disk


func _flush() -> void:
	if _file:
		_file.flush()


func _notification(what: int) -> void:
	# Flush on shutdown so a crash during quit still leaves a complete log.
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		_flush()
