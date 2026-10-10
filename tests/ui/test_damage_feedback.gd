extends RefCounted
func run(t) -> void:
	var view = load("res://game/presentation/world_view.gd").new()
	view.reduce_effects = true
	var events: Array[Dictionary] = [{"type":"damage","payload":{"target_id":"player","amount":5,"hp":95}}]
	view.consume_events(events)
	t.check(view.has_method("player_animation"),"player damage has explicit animation feedback")
	if view.has_method("player_animation"):
		t.check(view.player_animation({"phase":"survival","player":{"velocity":[0,0]}}) == "hit","reduced effects retains nonflashing hit pose")
		t.check(view.player_animation({"phase":"dead","player":{"velocity":[0,0]}}) == "death","death overrides hit pose")
	view.free()
