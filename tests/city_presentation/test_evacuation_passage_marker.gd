extends RefCounted
const Fixture = preload("res://tests/city_presentation/test_world_view_city.gd")

func run(t) -> void:
	var fixture := Fixture.new()
	var view := Fixture.Capture.new()
	view.load_manifest()
	var state: Dictionary = fixture._state()
	var terrain: Dictionary = fixture._terrain()
	state.phase = "evacuation"
	state.entities = []; state.projectiles = []; state.telegraphs = []
	state.player.position = [384.0,384.0]
	state.world.evacuation = {"passage_id":"passage:city_v1:0:0","chunk":["0","0"],"selected_tick":108000}
	var before := state.duplicate(true)
	t.check(view.present_city(state,terrain).get("ok",false),"selected passage renders in current prepared city")
	var markers: Array = view.capture().filter(func(c): return c.asset == "escape_marker")
	t.check(markers.size() == 1,"durably selected city passage has one actual raster marker")
	if markers.size() == 1: t.check(markers[0].world == Vector2(384,384),"marker denotes the physical passage center")
	t.check(state == before,"marker rendering cannot mutate authority or phase")
	state.world.evacuation = {}
	view.present_city(state,terrain)
	t.check(view.capture().filter(func(c): return c.asset == "escape_marker").is_empty(),"uncommitted passage does not fabricate a destination")
	state.world.evacuation = before.world.evacuation.duplicate(true)
	state.world.origin_chunk = ["1","0"]
	state.world.origin_revision = 1
	state.player.position = [-384.0,384.0]
	terrain.origin_chunk = ["1","0"]
	terrain.origin_revision = 1
	view.present_city(state,terrain)
	markers = view.capture().filter(func(c): return c.asset == "escape_marker")
	t.check(markers.size() == 1 and markers[0].world == Vector2(-384,384),"absolute selected passage survives origin rebase once")
	state.phase = "survival"
	view.present_city(state,terrain)
	t.check(view.capture().filter(func(c): return c.asset == "escape_marker").is_empty(),"survival does not present an evacuation destination")
	view.free()
