extends RefCounted
const F = preload("res://tests/terrain_mobility/motion_fixture.gd")
const Renderer = preload("res://game/presentation/city_render.gd")
const Main = preload("res://tests/terrain_mobility_view/test_authoritative_roof_view.gd")
func run(t) -> void:
	var view = Main.Capture.new()
	view.load_manifest()
	t.check(view.has_method("mobility_commands"),"bounded depth and danger consume actual mobility projection")
	if not view.has_method("mobility_commands"): view.free(); return
	if not F.available(t): view.free(); return
	var s: Dictionary = F.make(t)
	if s.is_empty(): view.free(); return
	t.check(F.reach(s,"over"),"depth fixture obtains actual Core over state")
	if s.state.get("player_mobility",{}).get("phase") != "over": view.free(); return
	var sample: Dictionary = load(F.PATH).visual_sample(s.core.snapshot(s.state))
	var terrain: Dictionary = s.core.world_render_view(s.state)
	terrain.world_revision = s.core.world_status().get("world_revision",s.state.world.world_revision)
	view._viewport_size = Vector2(800,450)
	view.present_city(s.core.snapshot(s.state),terrain)
	var packet: Dictionary = view._city_render_packet()
	var player: Array = packet.upright.filter(func(c): return c.id == "actor:s:player")
	var roofs: Array = packet.upright.filter(func(c): return c.id == sample.anchor.prop_id)
	t.check(player.size() == 1 and roofs.size() == 1,"actual target and player enter depth assertions")
	if player.size() != 1 or roofs.size() != 1: view.free(); return
	var expected_depth: float = maxf(float(sample.ground_position[1]),float(roofs[0].depth_y)+0.01)
	print("MOBILITY_DEPTH_PROBE ground=%s target=%s actual=%s expected=%s" % [sample.ground_position[1],roofs[0].depth_y,player[0].depth_y,expected_depth])
	t.check(is_equal_approx(float(player[0].depth_y),expected_depth),"roof policy preserves original ground depth and lifts only to exact target minimum")
	# First over sample is still at the expanded collider's near edge (ground232,
	# roof224). Move the actual Core two more ticks to ground216 before proving
	# the lift, rather than incorrectly forcing an already-forward actor behind.
	F.step(s)
	F.step(s)
	sample = load(F.PATH).visual_sample(s.core.snapshot(s.state))
	terrain = s.core.world_render_view(s.state)
	terrain.world_revision = s.core.world_status().get("world_revision",s.state.world.world_revision)
	view.present_city(s.core.snapshot(s.state),terrain)
	packet = view._city_render_packet()
	player = packet.upright.filter(func(c): return c.id == "actor:s:player")
	roofs = packet.upright.filter(func(c): return c.id == sample.roof_prop_id)
	t.check(sample.phase == "over" and player.size() == 1 and roofs.size() == 1 and float(sample.ground_position[1]) < float(roofs[0].depth_y) and is_equal_approx(float(player[0].depth_y),float(roofs[0].depth_y)+0.01),"actual inside-roof over lifts exactly to target depth plus0.01")
	if player.size() != 1 or roofs.size() != 1: view.free(); return
	# Explicit renderer-only occluder fixture. The player's mobility and DTO were
	# produced by actual Core/WorldView; this extra raster is not game geometry.
	var front: Dictionary = {"prop_id":"renderer:foreground","asset_id":"house_narrow","position":Vector2(sample.ground_position[0],roofs[0].depth_y+32.0),"depth_y":roofs[0].depth_y+32.0,"render_bounds":Rect2(F.vec(sample.ground_position)-Vector2(80,200),Vector2(160,240)),"pose":"intact"}
	var augmented: Dictionary = terrain.duplicate(true)
	augmented.chunks[0].props.append(front)
	view.present_city(s.core.snapshot(s.state),augmented)
	var bounded: Dictionary = view._city_render_packet()
	var ids: Array = bounded.upright.map(func(c): return c.id)
	t.check(ids.find("actor:s:player") < ids.find(front.prop_id),"unrelated foreground building still draws above rooftop player")
	var hazard: Dictionary = F.F.hazard("roof-warning","circle",{"origin":s.state.player.position.duplicate(),"radius":36.0,"warning_ticks":10,"active_ticks":5,"damage":1.0})
	hazard.origin_revision = s.state.world.origin_revision
	F.step(s,Vector2.UP,[hazard])
	terrain = s.core.world_render_view(s.state)
	terrain.world_revision = s.core.world_status().get("world_revision",s.state.world.world_revision)
	view.present_city(s.core.snapshot(s.state),terrain)
	view.reduce_effects = true
	var emitted: Array = view.capture()
	t.check(not s.state.telegraphs.is_empty() and not emitted.is_empty() and emitted.back().kind == "danger","actual Core warning remains final draw pass under reduced effects")
	var elevated_style: Dictionary = view._city_draw_data.actor.player
	var elevated_command: Array = view._city_render_packet().upright.filter(func(c): return c.id == "actor:s:player")
	t.check(elevated_command.size() == 1 and elevated_style.position == elevated_command[0].position and elevated_style.render_bounds == elevated_command[0].render_bounds,"occlusion outline reads raised actual body bounds rather than ground-only bounds")
	view.free()
