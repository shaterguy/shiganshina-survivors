extends Node
const Simulation = preload("res://game/core/run_simulation.gd")
const Director = preload("res://game/director/spawn_director.gd")
const Chapters = preload("res://game/director/chapter_catalog.gd")
const Router = preload("res://game/input/input_router.gd")
const Lifecycle = preload("res://game/input/lifecycle_guard.gd")
const UI = preload("res://game/ui/game_ui.gd")
const Audio = preload("res://game/presentation/audio_director.gd")
const Save = preload("res://game/persistence/save_store.gd")
const World = preload("res://game/presentation/world_view.gd")
const TICK_DURATION := 1.0/60.0
var simulation = Simulation.new()
var director = Director.new()
var chapter: Dictionary = {}
var state: Dictionary = {}
var save_store = Save.new()
var profile: Dictionary = {}
var pending_checkpoint: Dictionary = {}
var _last_save_tick := -1
var _last_phase := ""
var input_router
var ui
var world
var audio
var _accumulator := 0.0
var _foreground := true
func _ready() -> void:
	chapter = Chapters.new().load_chapter("chapter_01_shiganshina").chapter
	var loaded_profile: Dictionary = save_store.load_profile()
	if loaded_profile.ok: profile = loaded_profile.profile
	var checkpoint: Dictionary = save_store.load_checkpoint()
	if checkpoint.ok and checkpoint_matches_chapter(checkpoint.snapshot,chapter) and not checkpoint.snapshot.phase in ["dead","won"]:
		pending_checkpoint = checkpoint.snapshot
	audio = Audio.new()
	audio.name = "AudioDirector"
	add_child(audio)
	world = World.new()
	world.name = "World"
	add_child(world)
	input_router = Router.new()
	input_router.name = "InputRouter"
	add_child(input_router)
	ui = UI.new()
	ui.name = "GameUI"
	add_child(ui)
	ui.set_checkpoint_available(not pending_checkpoint.is_empty())
	if not loaded_profile.ok or (not checkpoint.ok and checkpoint.error_code != "not_found"):
		ui.set_save_notice("저장 파일을 읽지 못했습니다. 기존 파일은 보존됩니다.")
	elif checkpoint.ok and not checkpoint_matches_chapter(checkpoint.snapshot,chapter):
		ui.set_save_notice("콘텐츠 버전이 달라 이전 전투는 보존했습니다. 새로 출격해주세요.")
	elif checkpoint.get("recovered",false):
		ui.set_save_notice("이전 안전 저장 지점에서 복구했습니다.")
	ui.new_run_requested.connect(func(): start_run(randi() & 0x7fffffff))
	ui.resume_requested.connect(request_resume)
	ui.pause_changed.connect(set_user_pause)
	ui.end_run_requested.connect(request_end_run)
	ui.upgrade_chosen.connect(apply_upgrade)
	ui.upgrade_focus_changed.connect(func(id):
		if not state.is_empty(): simulation.set_offer_focus(state,id))
	ui.settings_changed.connect(_apply_settings)
	if not profile.is_empty():
		ui.set_settings(profile.settings)
		world.reduce_effects = profile.settings.reduce_effects
		world.screen_shake = float(profile.settings.screen_shake)
		input_router.deadzone = float(profile.settings.deadzone)
		AudioServer.set_bus_volume_linear(0,float(profile.settings.audio_master))
	ui.touch_move_changed.connect(input_router.set_touch_vector)
	input_router.ui_action.connect(ui.navigate)
	input_router.input_hint_changed.connect(ui.set_input_hint)
	input_router.active_controller_lost.connect(func():
		if not state.is_empty():
			simulation.set_pause(state,"controller_lost",true)
			_save_checkpoint()
		_present())
	get_viewport().size_changed.connect(_resize)
	_resize()
func start_run(seed: int) -> void:
	world.reset_presentation()
	state = simulation.new_run(chapter,seed)
	pending_checkpoint.clear()
	ui.set_checkpoint_available(false)
	_last_save_tick = -1
	ui.set_save_notice("")
	_last_phase = state.phase
	_save_checkpoint()
	_accumulator = 0.0
	input_router.clear_transient_input()
	_present()
func _process(delta: float) -> void:
	advance_frame(delta)
func advance_frame(delta: float) -> void:
	if state.is_empty(): return
	if not state.pause_reasons.is_empty() or state.phase in ["dead","won"]:
		_accumulator = 0
		_present()
		return
	_accumulator += maxf(delta,0)
	if _accumulator > 2.0:
		simulation.set_pause(state,"slow_frame",true)
		_present()
		return
	var ticks := 0
	while _accumulator + 0.00000001 >= TICK_DURATION and ticks < 8:
		var commands: Array[Dictionary] = director.plan(state,chapter)
		var events: Array[Dictionary] = simulation.step(state,input_router.sample_move(),commands)
		audio.consume_events(events)
		world.consume_events(events)
		for event in events:
			if event.type == "run_ended": _record_result()
		if int(state.active_tick)-_last_save_tick >= 1800 or state.phase != _last_phase or not state.upgrade_offer.is_empty():
			_save_checkpoint()
		else:
			for event in events:
				if event.type == "boss_spawned":
					_save_checkpoint()
					break
		_accumulator = maxf(0,_accumulator-TICK_DURATION)
		ticks += 1
		if not state.pause_reasons.is_empty() or state.phase in ["dead","won"]: break
	_present()
func apply_upgrade(offer_id: String, option_id: String) -> void:
	if state.is_empty(): return
	var result: Dictionary = simulation.choose_upgrade(state,offer_id,option_id)
	if result.ok:
		_accumulator = 0
		input_router.clear_transient_input()
		audio.consume_events(result.events)
		world.consume_events(result.events)
		_save_checkpoint()
	_present()
func set_user_pause(enabled: bool) -> void:
	if state.is_empty(): return
	simulation.set_pause(state,"user",enabled)
	_save_checkpoint()
	input_router.clear_transient_input()
	_present()
func request_resume() -> void:
	if not _foreground: return
	if state.is_empty() and not pending_checkpoint.is_empty():
		if not checkpoint_matches_chapter(pending_checkpoint,chapter): return
		var restored: Dictionary = simulation.restore(pending_checkpoint)
		if not restored.ok: return
		world.reset_presentation()
		state = restored.state
		pending_checkpoint.clear()
		ui.set_checkpoint_available(false)
	if state.is_empty(): return
	input_router.clear_transient_input()
	for reason in ["user","background","controller_lost","slow_frame"]:
		simulation.set_pause(state,reason,false)
	_accumulator = 0
	_present()
func request_end_run() -> void:
	if state.is_empty(): return
	var events: Array[Dictionary] = simulation.abandon_run(state)
	world.consume_events(events)
	audio.consume_events(events)
	_record_result()
	_save_checkpoint()
	_present()
func _record_result() -> void:
	if profile.is_empty() or not state.phase in ["won","dead"]: return
	var candidate := profile.duplicate(true)
	if state.phase == "won" and not state.chapter_id in candidate.cleared_chapter_ids:
		candidate.cleared_chapter_ids.append(state.chapter_id)
	var old: Dictionary = candidate.best_runs.get(state.chapter_id,{})
	if (state.phase == "won" and not old.get("won",false)) or int(state.survival_tick) >= int(old.get("survival_tick",-1)):
		candidate.best_runs[state.chapter_id] = {"survival_tick":state.survival_tick,"kills":state.stats.kills,"won":state.phase == "won" or old.get("won",false)}
	var saved: Dictionary = save_store.save_profile(candidate)
	if saved.ok: profile = candidate
	else: ui.set_save_notice("전투 기록 저장에 실패했습니다. 이전 진행은 보존됩니다.")
func _apply_settings(values: Dictionary) -> void:
	if profile.is_empty(): return
	var next := profile.duplicate(true)
	next.settings = values.duplicate(true)
	var result: Dictionary = save_store.save_profile(next)
	if not result.ok:
		ui.set_save_notice("설정을 저장하지 못했습니다.")
		return
	profile = next
	world.reduce_effects = values.reduce_effects
	world.screen_shake = float(values.screen_shake)
	input_router.deadzone = float(values.deadzone)
	AudioServer.set_bus_volume_linear(0,float(values.audio_master))
func _save_checkpoint() -> void:
	if state.is_empty(): return
	var result: Dictionary = save_store.save_checkpoint(simulation.snapshot(state))
	if result.ok:
		_last_save_tick = int(state.active_tick)
		_last_phase = state.phase
	elif is_instance_valid(ui): ui.set_save_notice("저장에 실패했습니다. 현재 전투는 계속할 수 있습니다.")
func _present() -> void:
	if not is_instance_valid(ui): return
	var view: Dictionary = simulation.snapshot(state) if not state.is_empty() else {}
	ui.present(view)
	world.present(view)
	audio.present(view)
func _resize() -> void:
	if not is_instance_valid(ui): return
	if not state.is_empty(): simulation.set_pause(state,"rotation",true)
	input_router.clear_transient_input()
	var viewport := Vector2i(get_viewport().get_visible_rect().size)
	var safe_area := Rect2i(Vector2i.ZERO,viewport)
	if OS.has_feature("android") or OS.has_feature("ios"):
		safe_area = Lifecycle.new().map_safe_area(viewport,DisplayServer.window_get_size(),DisplayServer.get_display_safe_area(),DisplayServer.window_get_position())
	ui.reflow(viewport,safe_area)
	if not state.is_empty(): simulation.set_pause(state,"rotation",false)
	_present()
func _notification(what: int) -> void:
	if not is_instance_valid(input_router): return
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT,NOTIFICATION_APPLICATION_PAUSED]:
		_foreground = false
		input_router.set_active(false)
		if not state.is_empty():
			simulation.set_pause(state,"background",true)
			_save_checkpoint()
	elif what in [NOTIFICATION_APPLICATION_FOCUS_IN,NOTIFICATION_APPLICATION_RESUMED]:
		_foreground = true
		input_router.set_active(true)

func _unhandled_key_input(event: InputEvent) -> void:
	if not OS.has_feature("debug") or OS.has_feature("mobile"): return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F9:
		_capture_validation_frame()
func _capture_validation_frame() -> void:
	await RenderingServer.frame_post_draw
	var directory := "res://dist/screenshots"
	DirAccess.make_dir_recursive_absolute(directory)
	var path := directory.path_join("game-%d.png" % Time.get_unix_time_from_system())
	var result := get_viewport().get_texture().get_image().save_png(path)
	var meta := {"phase":state.get("phase","title"),"tick":state.get("active_tick",0),"panel_size":str(ui._panel.size),"panel_minimum":str(ui._panel.get_combined_minimum_size()),"panel_position":str(ui._panel.position),"viewport":str(get_viewport().get_visible_rect().size)}
	var file := FileAccess.open(path+".json",FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(meta))
	print("VALIDATION_CAPTURE ",path," result=",result," phase=",state.get("phase","title")," tick=",state.get("active_tick",0)," viewport=",get_viewport().get_visible_rect().size)

func checkpoint_matches_chapter(snapshot: Dictionary, current_chapter: Dictionary) -> bool:
	return snapshot.get("chapter_id","") == current_chapter.get("chapter_id","") and snapshot.get("content_revision","") == current_chapter.get("content_revision","") and snapshot.get("rules",{}).get("world_geometry",{}) == current_chapter.get("world_geometry",{})
