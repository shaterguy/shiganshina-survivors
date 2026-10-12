extends RefCounted
const S = preload("res://tests/app_city_controller/controller_city_support.gd")
func run(t) -> void:
	var f := S.make(t)
	if f.is_empty(): return
	var app = f.app
	app.start_run(42)
	app.request_end_run()
	t.check(app.state.phase == "abandoned" and app.ui._notice.text.contains("획득 보급금"),"actual settlement displays its earned-supply result")
	var receipt: Dictionary = app.game_save.settlement_receipts.back().duplicate(true)
	app.start_run(43)
	t.check(app.state.seed == 43 and app.state.run_serial == 2 and app.ui._notice.text.is_empty(),"confirmed fresh city run clears obsolete prior settlement HUD notice")
	t.check(app.game_save.settlement_receipts.back() == receipt,"clearing old presentation notice does not discard economic receipt")
	app.free()
