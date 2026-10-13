extends RefCounted
const F = preload("res://tests/terrain_mobility/motion_fixture.gd")
const Main = preload("res://tests/terrain_mobility_view/test_authoritative_roof_view.gd")
# Wire detachment cannot remove the sole read-only roof depth identity. This
# tests a saved cancelled-over checkpoint too, without prior renderer history.
func run(t) -> void:
	if not F.available(t): return
	var script = load(F.PATH)
	var s: Dictionary = F.make(t)
	if s.is_empty(): return
	t.check(F.reach(s,"over"),"cancelled-depth fixture reaches actual Core roof phase")
	if s.state.get("player_mobility",{}).get("phase") != "over": return
	var roof_id: String = str(s.state.player_mobility.anchor.prop_id)
	F.step(s,Vector2.ZERO)
	var saved: Dictionary = s.core.snapshot(s.state)
	var sample: Dictionary = script.visual_sample(saved)
	t.check(saved.player_mobility.cancelled and sample.anchor.is_empty(),"actual over cancellation releases wire immediately")
	t.check(sample.get("roof_prop_id","") == roof_id and sample.phase == "over","read-only projection retains only precise roof depth identity during cancelled over")
	if sample.get("roof_prop_id","") != roof_id: return
	var cold = F.Core.new(s.provider)
	var checked: Dictionary = cold.restore(saved,s.hydration)
	t.check(checked.get("ok",false),"saved cancelled over restores without renderer history")
	if not checked.get("ok",false): return
	var state: Dictionary = checked.state
	t.check(cold.prepare_world(state,s.hydration).get("ok",false),"cold cancelled roof state prepares actual geometry")
	var view = Main.Capture.new()
	view.load_manifest()
	t.check(view.has_method("mobility_commands"),"cancelled roof depth has an actual WorldView projection")
	if not view.has_method("mobility_commands"): view.free(); return
	var terrain: Dictionary = cold.world_render_view(state)
	terrain.world_revision = cold.world_status().get("world_revision",state.world.world_revision)
	view.present_city(cold.snapshot(state),terrain)
	t.check(view.mobility_commands().get("wire",{}).is_empty(),"cold cancelled state never redraws detached wire")
	var packet: Dictionary = view._city_render_packet()
	var player: Array = packet.upright.filter(func(c): return c.id == "actor:s:player")
	var roofs: Array = packet.upright.filter(func(c): return c.id == roof_id)
	t.check(player.size() == 1 and roofs.size() == 1 and player[0].depth_y > roofs[0].depth_y and player[0].depth_y <= roofs[0].depth_y+1.0,"cold cancelled over remains just above the actual approved roof")
	var plane: Vector2 = F.vec(state.player.position)
	var before: Dictionary = view.mobility_commands()
	var shifted: Dictionary = state.duplicate(true)
	shifted.world.origin_chunk = ["-1","0"]
	shifted.world.origin_revision += 1
	shifted.player.position[0] += 768.0
	var hydration: Dictionary = F.HF.hydration(F.H.requirements(shifted))
	t.check(cold.prepare_world(shifted,hydration).get("ok",false),"cancelled-over geometry prepares under a different origin")
	terrain = cold.world_render_view(shifted)
	terrain.world_revision = cold.world_status().get("world_revision",shifted.world.world_revision)
	view.present_city(cold.snapshot(shifted),terrain)
	var rebased: Dictionary = view._city_render_packet()
	var shifted_player: Array = rebased.upright.filter(func(c): return c.id == "actor:s:player")
	var shifted_roof: Array = rebased.upright.filter(func(c): return c.id == roof_id)
	t.check(view.mobility_commands().get("wire",{}).is_empty() and is_equal_approx(float(view.mobility_commands().height),float(before.height)),"cancelled-over rebase preserves detached wire and actual height")
	t.check(shifted_player.size() == 1 and shifted_roof.size() == 1 and shifted_player[0].depth_y > shifted_roof[0].depth_y and shifted_player[0].position-view._camera == player[0].position-plane,"cancelled-over rebase preserves exact target depth and raised body screen position")
	view.free()
