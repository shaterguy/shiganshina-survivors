extends Node
# Isolated development play scene. Never opens user://saves.
const CityProvider = preload("res://game/director/streamed_chapter_provider.gd")
const PreparedRuntime = preload("res://game/app/prepared_city_runtime.gd")
const DeltaStore = preload("res://game/persistence/world_delta_store.gd")
const Controller = preload("res://game/app/run_controller.gd")
var _qa_banner: Label
var app
var _sample_clock := 0.0
var _trace: FileAccess
var _error_captured := false
var _qa_directory := ""
var _last_frame_usec := -1
var _frame_window := {"frames":0,"sum_ms":0.0,"max_ms":0.0,"over_50_ms":0,"playing_frames":0,"playing_sum_ms":0.0,"playing_max_ms":0.0,"playing_over_50_ms":0}
@export var practice_health_refill := true
func _ready() -> void:
	var directory := ProjectSettings.globalize_path("res://.qa/city-practice/saves" if practice_health_refill else "res://.qa/city-play/saves")
	_qa_directory = directory
	DirAccess.make_dir_recursive_absolute(directory)
	_trace = FileAccess.open(directory.path_join("native-play-trace-%d.jsonl" % Time.get_unix_time_from_system()),FileAccess.WRITE)
	var provider = CityProvider.new()
	var delta_store = DeltaStore.new(directory.path_join("world"))
	var runtime = PreparedRuntime.new(provider,delta_store)
	app = Controller.new()
	var configured: Dictionary = app.configure_city_runtime(provider,runtime,delta_store,directory)
	if not configured.get("ok",false):
		push_error("Isolated city QA configuration refused: "+str(configured.get("error_code")))
		return
	app.name = "CityController"
	add_child(app)
	var layer := CanvasLayer.new()
	layer.layer = 30
	add_child(layer)
	_qa_banner = Label.new()
	_qa_banner.text = "연습 검수 · 체력 자동 회복 · 밸런스 평가 제외" if practice_health_refill else "도시 플레이 개발 검수 · 임시 저장 전용"
	_qa_banner.position = Vector2(8,76)
	_qa_banner.add_theme_font_size_override("font_size",12)
	_qa_banner.add_theme_color_override("font_color",Color(1.0,0.88,0.3))
	_qa_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_qa_banner)
func _process(delta: float) -> void:
	if app == null or app.state.is_empty(): return
	var frame_now := Time.get_ticks_usec()
	if _last_frame_usec >= 0:
		# Engine delta can be scaled/capped after a stall; measure real callbacks.
		_record_frame_delta(float(frame_now-_last_frame_usec)/1000000.0,app.state.pause_reasons.is_empty() and not app.state.phase in app.TERMINAL)
	_last_frame_usec = frame_now
	if not app._city_step_error.is_empty() and not _error_captured:
		_error_captured = true
		var error_file := FileAccess.open(_qa_directory.path_join("refused-tick.json"),FileAccess.WRITE)
		if error_file != null:
			error_file.store_string(JSON.stringify({"state":app.simulation.snapshot(app.state),"pending_tick":app._pending_city_tick,"controller_sha256":app.get_script().source_code.sha256_text(),"error":app._city_step_error,"practice_health_refill":practice_health_refill}))
	# QA-only survival aid, never part of a shipped scene or real save directory.
	# Collision, damage events, attacks and player movement still execute normally.
	if practice_health_refill and not app.state.phase in app.TERMINAL:
		app.state.player.hp = app.state.player.max_hp
	_sample_clock += delta
	if _sample_clock < 1.0 or _trace == null: return
	_sample_clock = 0.0
	var sample := {"wall_usec":Time.get_ticks_usec(),"tick":app.state.active_tick,"position":app.state.player.position,"move":str(app.input_router.sample_move()),"pause":app.state.pause_reasons,"phase":app.state.phase,"entities":app.state.entities.size(),"world_status":app.simulation.world_status(),"city_error":app._city_step_error,"render_error":app._city_render_error,"practice_health_refill":practice_health_refill}
	sample.frame_intervals = _take_frame_metrics()
	_trace.store_line(JSON.stringify(sample))
	_trace.flush()

# Bounded QA-only counters: actual frame intervals, not a CPU/GPU profiler.
func _record_frame_delta(delta: float, playing: bool) -> void:
	var ms := maxf(delta,0.0)*1000.0
	_frame_window.frames += 1
	_frame_window.sum_ms += ms
	_frame_window.max_ms = maxf(_frame_window.max_ms,ms)
	if ms > 50.0: _frame_window.over_50_ms += 1
	if playing:
		_frame_window.playing_frames += 1
		_frame_window.playing_sum_ms += ms
		_frame_window.playing_max_ms = maxf(_frame_window.playing_max_ms,ms)
		if ms > 50.0: _frame_window.playing_over_50_ms += 1

func _take_frame_metrics() -> Dictionary:
	var result := _frame_window.duplicate()
	result.mean_ms = result.sum_ms/float(result.frames) if result.frames > 0 else 0.0
	result.playing_mean_ms = result.playing_sum_ms/float(result.playing_frames) if result.playing_frames > 0 else 0.0
	for key in _frame_window:
		_frame_window[key] = 0.0 if typeof(_frame_window[key]) == TYPE_FLOAT else 0
	return result
