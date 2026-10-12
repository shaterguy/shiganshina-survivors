extends RefCounted
const S = preload("res://tests/app_city_controller/controller_city_support.gd")
func run(t) -> void:
	var f := S.make(t)
	if f.is_empty(): return
	var app = f.app
	app.start_run(42)
	app.state.active_tick = 107999
	app.state.survival_tick = 107999
	app.state.player.position = [384.0,384.0]
	app.advance_frame(1.0/60.0)
	t.check(app.state.phase == "evacuation" and app.state.final_started_tick == 108000,"actual Controller calls actual Director at 107999 boundary")
	t.check(not app.state.world.evacuation.is_empty(),"actual Controller durably selects passage after final boundary")
	t.check(app.game_save.checkpoint.world.evacuation == app.state.world.evacuation and app.game_save.checkpoint.active_tick == app.state.active_tick,"selected passage and live tick share confirmed authority")
	app.advance_frame(1.0/60.0)
	t.check(app.state.world.stage == "dock" and app.game_save.checkpoint.world.stage == "dock","actual Controller physical passage overlap commits and adopts dock")
	t.check(app.ui._notice.text == "선착장으로 퇴각","confirmed scene change presents its existing helper caption rather than generic save text")
	app.free()
