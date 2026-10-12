extends RefCounted
const Support = preload("res://tests/app/controller_test_support.gd")
func run(t) -> void:
	var support := Support.new()
	var f := support.make(t)
	var app = f.app
	app.start_run(42)
	t.check(app.ui.has_method("confirmed_upgrade_text"),"UI provides a durable upgrade notice")
	if not app.ui.has_method("confirmed_upgrade_text"):
		app.free()
		return
	t.check(app.ui.confirmed_upgrade_text().is_empty(),"initial run synchronizes HUD without acquisition feedback")
	support.evolution_offer(app)
	var offer: Dictionary = app.state.upgrade_offer.duplicate(true)
	app.save_store._fault_injector = func(stage): return ERR_CANT_CREATE if stage == "write" else OK
	app.apply_upgrade(offer.offer_id,offer.options[0].option_id)
	t.check(app.ui.confirmed_upgrade_text().is_empty() and app.state.evolutions.is_empty(),"failed durable write cannot show evolution or successful feedback")
	app.save_store._fault_injector = Callable()
	app.apply_upgrade(offer.offer_id,offer.options[0].option_id)
	t.check(app.state.evolutions.get("blade_slash") == "evo_wing_cut","real retry publishes the committed ultimate")
	t.check(app.ui._notice.text.is_empty(),"successful retry removes the obsolete save failure notice")
	t.check(app.ui.confirmed_upgrade_text().contains("입체기동 연속참") and app.ui.confirmed_upgrade_text().contains("궁극 진화"),"successful upgrade_applied identifies the newest authoritative ultimate")
	t.check(app.ui.get_node("ProgressionHUD").display_text().contains("궁극"),"notice and durable HUD reflect the same published state")
	var notice: String = app.ui.confirmed_upgrade_text()
	var ttl: float = app.ui._growth_notice_seconds
	app.apply_upgrade(offer.offer_id,offer.options[0].option_id)
	t.check(app.ui.confirmed_upgrade_text() == notice and app.ui._growth_notice_seconds <= ttl,"duplicate/stale selection cannot restart successful feedback")
	var resumed = support.restart(t,f.directory)
	resumed.request_resume()
	t.check(resumed.state.evolutions.get("blade_slash") == "evo_wing_cut" and resumed.ui.confirmed_upgrade_text().is_empty(),"checkpoint restore shows ultimate without replaying acquisition")
	app.ui._process(2.1)
	t.check(app.ui.confirmed_upgrade_text().is_empty(),"ultimate notice expires without a growing event queue")
	app.free()
	resumed.free()
