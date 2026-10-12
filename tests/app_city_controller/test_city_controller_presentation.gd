extends RefCounted
const S = preload("res://tests/app_city_controller/controller_city_support.gd")
func run(t) -> void:
	var f := S.make(t)
	if f.is_empty(): return
	var app = f.app
	app.start_run(42)
	t.check(app.world._city_active and app.world._city_view.get("ok",false),"explicit city controller presents actual derived streamed terrain")
	if not app.world._city_active:
		app.free()
		return
	var cached: Dictionary = app._city_terrain_view
	var identity: String = cached.cache_identity
	for frame in 8: app.advance_frame(1.0/60.0)
	t.check(is_same(cached,app._city_terrain_view) and app._city_terrain_view.cache_identity == identity,"covered ticks reuse identical derived view without 49-chunk copies")
	t.check(not app.state.has("cache_identity") and not app.state.world.has("cache_identity") and not app.game_save.checkpoint.world.has("geometry_revision"),"presentation cache metadata never enters runtime or durable world")
	app._save_checkpoint()
	t.check(not is_same(cached,app._city_terrain_view) and app._city_terrain_view.cache_identity != identity,"prepared Core adoption invalidates presentation identity")
	var before: Dictionary = app.state.duplicate(true)
	app.state.world.origin_revision += 1
	app._present()
	t.check(app.world._city_view.is_empty() and app.ui._notice.text.contains("world_not_ready"),"unavailable city terrain blanks world and exposes explicit diagnostic")
	var tick: int = app.state.active_tick
	app.advance_frame(1.0)
	t.check(app.state.active_tick == tick and app.audio._music.stream_paused,"renderer refusal holds simulation and audio outside saved pause schema")
	app.state = before
	app.request_resume()
	t.check(app.world._city_view.get("ok",false),"explicit retry reacquires correct derived terrain after transient presentation refusal")
	app.advance_frame(1.0/60.0)
	t.check(app.state.active_tick == tick+1,"presentation recovery returns actual city control")
	app.free()
