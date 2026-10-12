extends RefCounted
const Support = preload("res://tests/app/controller_test_support.gd")
const F = preload("res://tests/core/new_current_regression_fixture.gd")
func run(t) -> void:
	var app = Support.new().make(t).app
	app.start_run(42)
	F.drop_xp(app.simulation,app.state,100,"fixture:ui-consecutive")
	app._present()
	var old_offer: Dictionary = app.state.upgrade_offer.duplicate(true)
	t.check(not old_offer.is_empty(),"real level flow opens an initial growth offer")
	app.ui._buttons[0].grab_focus()
	app.ui.navigate("accept")
	var new_offer: String = app.state.upgrade_offer.get("offer_id","")
	t.check(not new_offer.is_empty() and new_offer != old_offer.offer_id,"first confirmed choice promotes the real FIFO next offer")
	t.check(app.ui._growth_notice.text.begins_with("직전 선택") and app.ui._growth_notice.get_parent() == app.ui._panel.get_node("Body"),"next growth screen preserves a visible prior-choice summary")
	app.ui.navigate("accept")
	t.check(app.state.upgrade_offer.get("offer_id","") == new_offer,"held A cannot choose through the confirmed next-offer transition")
	for screen in [Vector2i(320,568),Vector2i(640,360)]:
		app.ui.reflow(screen,Rect2i(Vector2i.ZERO,screen))
		for frame in 5: await t.process_frame
		t.check(app.ui._panel.get_global_rect().end.y <= screen.y,"consecutive feedback stays inside the supported viewport "+str(screen))
		var card: Button = app.ui._buttons[0]
		card.grab_focus()
		for frame in 5: await t.process_frame
		t.check(app.ui._scroll.get_global_rect().grow(1).encloses(card.get_global_rect()),"consecutive notice leaves current choice fully readable "+str(screen))
	app.ui.accept_released()
	app.ui.navigate("accept")
	t.check(app.state.upgrade_offer.get("offer_id","") != new_offer,"fresh A can choose the new offer after release")
	app.free()
