extends RefCounted
const Fixture = preload("res://tests/city_presentation/test_world_view_city.gd")

func run(t) -> void:
	var fixture := Fixture.new()
	var view := Fixture.Capture.new()
	view.load_manifest()
	var state: Dictionary = fixture._state()
	state.phase = "evacuation"
	state.escape_zone = [-56,320,112,80]
	state.entities = []; state.projectiles = []; state.telegraphs = []
	view.present(state)
	t.check(not view.capture().any(func(c): return c.asset == "armored_titan"),"final phase cannot fabricate an Armored body without a physical actor")
	var actor: Dictionary = fixture._enemy("final-physical",210.0)
	actor.enemy_id = "armored_titan"
	actor.position = [90.0,210.0]
	actor.facing = [-1.0,0.0]
	actor.action_state = "brake"
	state.entities = [actor]
	state.rules.enemy_catalog.armored_titan = {"art_id":"armored_titan"}
	var before := state.duplicate(true)
	view.present(state)
	var drawn: Array = view.capture().filter(func(c): return c.asset == "armored_titan")
	t.check(drawn.size() == 1,"finite final actor is emitted exactly once instead of actor plus decoration")
	if drawn.size() == 1:
		t.check(drawn[0].world == Vector2(90,210) and drawn[0].flip,"Armored position and facing come from the physical actor")
		t.check(drawn[0].pose == "idle","non-damaging brake never falls through to a walking pose")
		t.check(drawn[0].scale == 1.5,"Armored uses the documented provisional native display scale")
	var terrain: Dictionary = fixture._terrain()
	t.check(view.present_city(state,terrain).get("ok",false),"physical final actor accepts matching prepared city")
	var packet: Dictionary = view._city_render_packet()
	var ordered: Array = packet.upright.map(func(c): return c.id)
	t.check(ordered.count("actor:s:final-physical") == 1 and ordered.find("actor:s:final-physical") < ordered.find("house"),"Armored shares foot-depth order behind an actual nearer house")
	drawn = view.capture().filter(func(c): return c.asset == "armored_titan")
	t.check(drawn.size() == 1 and drawn[0].world == Vector2(90,210),"streamed city uses the same physical final actor identity")
	t.check(state == before,"actor presentation preserves authoritative state")
	view.free()
