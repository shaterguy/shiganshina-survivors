extends RefCounted
const Support = preload("res://tests/app/controller_test_support.gd")
const CitySupport = preload("res://tests/app_city_controller/controller_city_support.gd")
class ObservedWorld:
	extends "res://game/presentation/world_view.gd"
	var deliveries: Array[Dictionary] = []
	var sequence: Array[String] = []
	func consume_combat_events(events: Array[Dictionary], current_snapshot: Dictionary) -> void:
		deliveries.append({"events":events.duplicate(true),"snapshot":current_snapshot})
		sequence.append("combat")
	func consume_events(events: Array[Dictionary]) -> void:
		sequence.append("feedback")
		super.consume_events(events)

func _observe(app):
	app.world.free()
	var observed := ObservedWorld.new()
	app.world = observed
	app.add_child(observed)
	observed.set_process(false)
	return observed

func run(t) -> void:
	for city in [false,true]:
		var fixture: Dictionary = CitySupport.make(t) if city else Support.new().make(t)
		if fixture.is_empty(): continue
		var app = fixture.app
		app.start_run(42)
		var observed = _observe(app)
		app.input_router.set_touch_vector(Vector2.RIGHT)
		app.advance_frame(3.0/60.0)
		t.check(observed.deliveries.size() == 3,"each successful %s Core tick supplies a combat snapshot" % ("city" if city else "finite"))
		for i in observed.deliveries.size():
			var packet: Dictionary = observed.deliveries[i]
			t.check(int(packet.snapshot.active_tick) == i+1,"combat gets this successful tick, never the previous rendered frame")
			t.check(not is_same(packet.snapshot,app.state),"combat snapshot does not alias live gameplay authority")
			for event in packet.events:
				t.check(int(event.tick) == int(packet.snapshot.active_tick),"event tick and supplied snapshot tick agree")
		t.check(observed.sequence == ["combat","feedback","combat","feedback","combat","feedback"],"drawable combat commands are prepared before legacy feedback")
		var count: int = observed.deliveries.size()
		app.set_user_pause(true)
		app.advance_frame(0.5)
		t.check(observed.deliveries.size() == count,"paused controller emits no fabricated successful combat tick")
		app.free()
	var support := Support.new()
	var app = support.make(t).app
	app.start_run(42)
	support.evolution_offer(app)
	var observed = _observe(app)
	var offer: Dictionary = app.state.upgrade_offer.duplicate(true)
	app.apply_upgrade(offer.offer_id,offer.options[0].option_id)
	t.check(observed.deliveries.size() == 1,"confirmed growth transaction forwards actual committed events once")
	if observed.deliveries.size() == 1:
		var packet: Dictionary = observed.deliveries[0]
		t.check(packet.snapshot == app.simulation.snapshot(app.state),"transaction event snapshot is the adopted authority")
		t.check(not packet.events.is_empty() and app.state.evolutions.get("blade_slash") == "evo_wing_cut","transaction fixture commits real evolution before presentation")
		t.check(observed.sequence == ["combat","feedback"],"committed growth combat delivery precedes generic feedback")
	app.apply_upgrade(offer.offer_id,offer.options[0].option_id)
	t.check(observed.deliveries.size() <= 1,"stale growth intent never replays accepted visual events")
	app.free()
