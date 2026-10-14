extends RefCounted
const F = preload("res://tests/corridor_mobility_presentation/presentation_fixture.gd")
const Main = preload("res://tests/terrain_mobility_view/test_authoritative_roof_view.gd")
func run(t) -> void:
	var view = Main.Capture.new()
	view.load_manifest()
	if not F.available(t): view.free(); return
	var s: Dictionary = F.make(t)
	if s.is_empty(): view.free(); return
	t.check(F.reach(s,"boost"),"depth fixture obtains actual Core corridor state")
	if s.state.get("player_mobility",{}).get("phase") != "boost": view.free(); return
	var sample: Dictionary = load(F.PATH).visual_sample(s.core.snapshot(s.state))
	var terrain: Dictionary = Main.new()._terrain(s.core,s.state)
	view._viewport_size = Vector2(800,450)
	view.present_city(s.core.snapshot(s.state),terrain)
	var packet: Dictionary = view._city_render_packet()
	var player: Array = packet.upright.filter(func(c): return c.id == "actor:s:player")
	t.check(player.size() == 1 and sample.anchors.size() == 2,"actual paired anchors and player enter depth assertions")
	if player.size() != 1: view.free(); return
	t.check(player[0].depth_y == sample.ground_position[1] and sample.roof_prop_id.is_empty(),"corridor never borrows either anchor building depth")
	F.step(s); F.step(s)
	sample = load(F.PATH).visual_sample(s.core.snapshot(s.state))
	terrain = Main.new()._terrain(s.core,s.state)
	view.present_city(s.core.snapshot(s.state),terrain)
	player = view._city_render_packet().upright.filter(func(c): return c.id == "actor:s:player")
	t.check(sample.phase == "boost" and player.size() == 1 and player[0].position == F.vec(sample.ground_position) and player[0].depth_y == sample.ground_position[1],"continued corridor stays grounded with no late roof-depth lift")
	# Renderer-only occluder: real Core motion stays unmodified.
	var front: Dictionary = {"prop_id":"renderer:foreground","asset_id":"house_narrow","position":F.vec(sample.ground_position)+Vector2(0,32),"depth_y":sample.ground_position[1]+32.0,"render_bounds":Rect2(F.vec(sample.ground_position)-Vector2(80,200),Vector2(160,240)),"pose":"intact"}
	var augmented: Dictionary = terrain.duplicate(true)
	augmented.chunks[0].props.append(front)
	view.present_city(s.core.snapshot(s.state),augmented)
	var ids: Array = view._city_render_packet().upright.map(func(c): return c.id)
	t.check(ids.find("actor:s:player") < ids.find(front.prop_id),"foreground building still occludes corridor player at normal foot depth")
	var hazard: Dictionary = F.F.hazard("corridor-warning","circle",{"origin":s.state.player.position.duplicate(),"radius":36.0,"warning_ticks":10,"active_ticks":5,"damage":1.0})
	hazard.origin_revision = s.state.world.origin_revision
	F.step(s,Vector2.UP,[hazard])
	view.present_city(s.core.snapshot(s.state),Main.new()._terrain(s.core,s.state))
	view.reduce_effects = true
	var emitted: Array = view.capture()
	t.check(not s.state.telegraphs.is_empty() and not emitted.is_empty() and emitted.back().kind == "danger","actual Core warning remains final draw pass under reduced effects")
	var style: Dictionary = view._city_draw_data.actor.player
	var command: Array = view._city_render_packet().upright.filter(func(c): return c.id == "actor:s:player")
	t.check(command.size() == 1 and style.position == command[0].position and style.render_bounds == command[0].render_bounds,"occlusion outline reads exact drawn body bounds during corridor travel")
	view.free()
