extends SceneTree
const Simulation = preload("res://game/core/run_simulation.gd")
const Chapters = preload("res://game/director/chapter_catalog.gd")
const App = preload("res://game/app/run_controller.gd")
const Save = preload("res://game/persistence/save_store.gd")
const Spy = preload("res://tests/integration/review_presentation/world_spy.gd")
var checks := 0
var failures: Array[String] = []
var observations: Dictionary = {}
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error("REVIEW FAIL: "+label)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var chapter: Dictionary = Chapters.new().load_chapter("chapter_01_shiganshina").chapter
	var sim := Simulation.new()
	var east: Dictionary = sim.new_run(chapter,17)
	for tick in range(600): sim.step(east,Vector2.RIGHT,[])
	observations.east_after_10s = east.player.position
	check(east.player.position == [632.0,0.0],"east boundary closes original infinite-world repro")
	var south: Dictionary = sim.new_run(chapter,17)
	for tick in range(600): sim.step(south,Vector2.DOWN,[])
	observations.south_after_10s = south.player.position
	check(south.player.position == [0.0,408.0],"shoreline closes original water-walking repro")
	var north: Dictionary = sim.new_run(chapter,17)
	for tick in range(600): sim.step(north,Vector2.UP,[])
	observations.north_after_10s = north.player.position
	check(north.player.position == [0.0,-292.0],"north boundary closes original wall-crossing repro")
	var distant: Dictionary = sim.new_run(chapter,17)
	distant.active_tick = 107999
	distant.survival_tick = 107999
	distant.player.position = [632.0,360.0]
	sim.step(distant,Vector2.ZERO,[{"command_id":"final_begin","kind":"begin_evacuation","payload":{"boss_id":"ch01_final_armored","escape_zone":chapter.escape_zone,"evacuation_ticks":4500}}])
	for tick in range(4500): sim.step(distant,Vector2.LEFT,[])
	observations.bounded_evacuation_after_75s = {"position":distant.player.position,"phase":distant.phase,"ready":distant.evacuation_ready,"survival_tick":distant.survival_tick}
	check(distant.evacuation_ready and distant.phase == "evacuation","75 seconds is a gate, not a game-over timeout")
	distant.player.position = [0.0,360.0]
	sim.step(distant,Vector2.ZERO,[])
	check(distant.phase == "won","dock remains accessible from valid ground coordinates after timer")
	var app = App.new()
	var store = Save.new("user://presentation_probe_"+str(OS.get_process_id()))
	app.save_store = store
	root.add_child(app)
	app.set_process(false)
	app.input_router.set_process(false)
	app.world.set_process(false)
	app.start_run(1234)
	app.input_router.set_touch_vector(Vector2.RIGHT)
	app.advance_frame(1.0/60.0)
	var tick: int = app.state.active_tick
	var position: Array = app.state.player.position.duplicate()
	app._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	app.advance_frame(1.0)
	check(app.state.active_tick == tick and app.state.player.position == position,"focus loss freezes time and movement")
	check(app.input_router.sample_move() == Vector2.ZERO,"focus loss clears movement")
	var saved: Dictionary = store.load_checkpoint()
	check(saved.ok and "background" in saved.snapshot.pause_reasons,"focus loss persists paused checkpoint")
	app._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	app.advance_frame(1.0)
	check(app.state.active_tick == tick and "background" in app.state.pause_reasons,"focus regain waits for explicit resume")
	app.request_resume()
	app.advance_frame(1.0/60.0)
	check(app.state.active_tick == tick+1 and app.state.player.position == position,"explicit focus resume does not replay stale movement")
	var motion := InputEventJoypadMotion.new()
	motion.device = 33
	motion.axis = JOY_AXIS_LEFT_X
	motion.axis_value = 1.0
	app.input_router.handle_event(motion)
	app.input_router._on_connection(33,false)
	tick = app.state.active_tick
	app.advance_frame(1.0)
	check("controller_lost" in app.state.pause_reasons and app.state.active_tick == tick,"active controller loss pauses simulation")
	check(app.input_router.sample_move() == Vector2.ZERO,"active controller loss clears movement")
	app.request_resume()
	app.input_router.set_touch_vector(Vector2.DOWN)
	app.advance_frame(1.0/60.0)
	check(app.state.active_tick == tick+1,"touch resumes after controller loss")
	app.set_user_pause(true)
	var before: Dictionary = app.simulation.snapshot(app.state)
	app._resize()
	check(app.simulation.snapshot(app.state) == before,"resize preserves existing user pause and full simulation snapshot")
	check(app.input_router.sample_move() == Vector2.ZERO,"resize clears movement")
	app.request_resume()
	app.state.drops.append({"id":90000,"position":app.state.player.position.duplicate(),"xp":24})
	app.advance_frame(1.0/60.0)
	check(not app.state.upgrade_offer.is_empty(),"fixture opens real upgrade offer")
	app.ui.navigate("right")
	var selected: String = app.state.upgrade_offer.selected_option_id
	before = app.simulation.snapshot(app.state)
	app.ui.reflow(Vector2i(450,800),Rect2i(0,30,450,740))
	app.ui.reflow(Vector2i(800,450),Rect2i(30,0,740,450))
	app._resize()
	check(app.simulation.snapshot(app.state) == before,"portrait/landscape reflow preserves active offer, focus, RNG, world, and clocks")
	app._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	tick = app.state.active_tick
	app.free()
	var restored = App.new()
	restored.save_store = store
	root.add_child(restored)
	restored.set_process(false)
	restored.input_router.set_process(false)
	restored.world.set_process(false)
	check(restored.state.is_empty() and restored.pending_checkpoint.active_tick == tick,"restart does not silently resume")
	restored.request_resume()
	check(restored.state.active_tick == tick and restored.state.upgrade_offer.selected_option_id == selected,"restart restores clock and selected upgrade")
	check(restored.state.pause_reasons == ["upgrade"] and restored.ui._mode == "upgrade","explicit restart resume preserves upgrade gate")
	var offer: Dictionary = restored.state.upgrade_offer
	restored.apply_upgrade(offer.offer_id,selected)
	check(restored.state.pause_reasons.is_empty(),"choosing restored upgrade exits gate normally")
	restored.free()
	var spy := Spy.new()
	spy.load_manifest()
	spy._clock = 10.0
	spy.reduce_effects = true
	var picture: Dictionary = sim.new_run(chapter,17)
	picture.entities.append({"id":1,"enemy_id":"walker","position":[0.0,50.0],"velocity":[0.0,0.0]})
	spy.present(picture)
	spy._draw()
	observations.ordinary_draw_order = spy.draw_calls.duplicate(true)
	spy.draw_calls.clear()
	spy.consume_events([{"type":"damage","payload":{"target_id":"player","amount":20,"hp":80}}])
	picture.player.hp = 80.0
	picture.player.invulnerable_until = 30
	spy.present(picture)
	spy._draw()
	check(spy.draw_calls[-1].animation == "hit","approved hit pose persists with reduced effects")
	observations.reduced_effects_after_player_hit = {"draw_calls":spy.draw_calls.duplicate(true),"effects":spy._effects.duplicate(true),"screen_origin":spy._screen(Vector2.ZERO)}
	spy.draw_calls.clear()
	picture.phase = "evacuation"
	spy.present(picture)
	spy._draw()
	observations.evacuation_draw_order = spy.draw_calls.duplicate(true)
	var armored_index := -1
	var player_index := -1
	for i in spy.draw_calls.size():
		if spy.draw_calls[i].id == "armored_titan": armored_index = i
		if spy.draw_calls[i].id == "garrison_01": player_index = i
	check(armored_index >= 0 and player_index > armored_index,"Armored draws before player and cannot recreate former total occlusion")
	spy.draw_calls.clear()
	picture.phase = "dead"
	spy.present(picture)
	spy._draw()
	observations.death_first_presentation = spy.draw_calls.duplicate(true)
	spy.free()
	print("PRESENTATION_OBSERVATIONS "+JSON.stringify(observations))
	await process_frame
	await process_frame
	await create_timer(0.35).timeout
	print("PRESENTATION_REVIEW checks=%d failures=%d" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
