extends RefCounted
const Support = preload("res://tests/app/controller_test_support.gd")
func run(t) -> void:
	var support := Support.new()
	var fixture := support.make(t)
	var app = fixture.app
	t.check(not app.game_save.is_empty() and app.game_save.store_revision == 1,"fresh controller initializes one real authority")
	app.start_run(42)
	t.check(not app.state.is_empty() and app.state.seed == 42,"actual service/store/controller adopts real Core start")
	if app.state.is_empty():
		app.free()
		return
	t.check(app.ui._mode == "play","confirmed start reaches playable screen")
	t.check(app.save_store.load_game().game_save.checkpoint == app.game_save.checkpoint,"initial candidate is actual durable checkpoint")
	for frame in 180: app.advance_frame(1.0/60.0)
	t.check(app.state.active_tick == 180 and app.state.survival_tick == 180,"real director/Core advances first three seconds")
	app.set_user_pause(true)
	var saved_tick: int = app.state.active_tick
	app.advance_frame(1.0)
	t.check(app.state.active_tick == saved_tick,"actual controller pause freezes clock")
	app.free()
	var resumed = support.restart(t,fixture.directory)
	t.check(resumed.state.is_empty() and not resumed.pending_checkpoint.is_empty(),"restart awaits explicit resume")
	resumed.request_resume()
	t.check(not resumed.state.is_empty() and resumed.state.active_tick == saved_tick,"actual validated checkpoint resumes without clock loss")
	if resumed.state.is_empty():
		resumed.free()
		return
	resumed.advance_frame(1.0/60.0)
	t.check(resumed.state.active_tick == saved_tick+1,"explicit continue returns control")
	resumed.free()
