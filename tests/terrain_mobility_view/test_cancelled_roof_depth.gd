extends RefCounted
const F = preload("res://tests/corridor_mobility_presentation/presentation_fixture.gd")
const Main = preload("res://tests/terrain_mobility_view/test_authoritative_roof_view.gd")
# Interruption is now grounded. No saved or cold renderer state grants roof depth.
func run(t) -> void:
	if not F.available(t): return
	var s: Dictionary = F.make(t)
	if s.is_empty(): return
	t.check(F.reach(s,"boost"),"interruption-depth fixture reaches actual corridor")
	F.step(s,Vector2.ZERO)
	var saved: Dictionary = s.core.snapshot(s.state)
	var sample: Dictionary = load(F.PATH).visual_sample(saved)
	t.check(saved.player_mobility.phase == "ground" and sample.anchors.is_empty(),"actual interruption releases both anchors immediately")
	t.check(sample.get("roof_prop_id","").is_empty() and sample.height == 0.0,"interrupted corridor has no roof identity or elevation")
	var cold = F.Core.new(s.provider)
	var checked: Dictionary = cold.restore(saved,s.hydration)
	t.check(checked.get("ok",false),"saved interrupted corridor restores without renderer history")
	if not checked.get("ok",false): return
	var state: Dictionary = checked.state
	t.check(cold.prepare_world(state,s.hydration).get("ok",false),"cold interrupted state prepares geometry")
	var view = Main.Capture.new()
	view.load_manifest()
	view.present_city(cold.snapshot(state),Main.new()._terrain(cold,state))
	t.check(view.mobility_commands().wires.is_empty(),"cold interrupted state never redraws detached wires")
	var player: Array = view._city_render_packet().upright.filter(func(c): return c.id == "actor:s:player")
	var plane: Vector2 = F.vec(state.player.position)
	t.check(player.size() == 1 and player[0].depth_y == plane.y and player[0].position == plane,"cold interrupted player keeps exact ordinary road depth")
	var shifted: Dictionary = state.duplicate(true)
	shifted.world.origin_chunk = ["-1","0"]; shifted.world.origin_revision += 1; shifted.player.position[0] += 768.0
	var hydration: Dictionary = F.HF.hydration(F.H.requirements(shifted))
	t.check(cold.prepare_world(shifted,hydration).get("ok",false),"interrupted geometry prepares under another origin")
	view.present_city(cold.snapshot(shifted),Main.new()._terrain(cold,shifted))
	var shifted_player: Array = view._city_render_packet().upright.filter(func(c): return c.id == "actor:s:player")
	t.check(view.mobility_commands().wires.is_empty() and view.mobility_commands().height == 0.0,"interrupted rebase preserves detached wires and zero height")
	t.check(shifted_player.size() == 1 and shifted_player[0].depth_y == shifted.player.position[1] and shifted_player[0].position-view._camera == player[0].position-plane,"interrupted rebase preserves exact depth and body screen position")
	view.free()
