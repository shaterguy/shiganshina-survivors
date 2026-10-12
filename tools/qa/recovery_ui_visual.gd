extends "res://game/app/run_controller.gd"
# Disposable QA entry point. Main scene and default user:// saves are unchanged.
@export var qa_save_directory: String = ""
var qa_last_key := "none"
var qa_last_action := "none"
var qa_router_identity := ""
class InputObserver extends Node:
	var sink: Node
	func _input(event: InputEvent) -> void:
		if event is InputEventKey:
			sink.qa_last_key = "%d/%d %s echo:%s" % [event.keycode,event.physical_keycode,"down" if event.pressed else "up",event.echo]
func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		qa_last_key = "%d/%d %s" % [event.keycode,event.physical_keycode,"down" if event.pressed else "up"]
func _process(delta: float) -> void:
	super._process(delta)
	if is_instance_valid(ui) and is_instance_valid(input_router):
		ui._dev_notice.text = "QA %s fg:%s input:%s action:%s key:%s focus:%s" % [qa_router_identity,_foreground,input_router._enabled,qa_last_action,qa_last_key,ui.focused_semantic_id()]
func _ready() -> void:
	var directory := ProjectSettings.globalize_path(qa_save_directory)
	if qa_save_directory.is_empty() or not FileAccess.file_exists(directory.path_join("game_save.json")):
		push_error("Recovery visual QA requires its existing disposable fixture; no default save was opened.")
		return
	save_store = Save.new(directory,Callable(validation_simulation,"restore"))
	super._ready()
	input_router.ui_action.connect(func(action): qa_last_action = action)
	qa_router_identity = "loaded:%s disk:%s" % [input_router.get_script().get_source_code().sha256_text().left(8),FileAccess.get_sha256("res://game/input/input_router.gd").left(8)]
	var observer := InputObserver.new()
	observer.sink = self
	add_child(observer)
	ui._dev_notice.text = "QA 전용 · 실제 사용자 저장과 분리"
	ui.set_save_notice("QA 전용 복구 화면 · 기존 사용자 저장은 사용하지 않습니다.")
