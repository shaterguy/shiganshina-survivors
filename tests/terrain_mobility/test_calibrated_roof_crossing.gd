extends RefCounted
const F = preload("res://tests/terrain_mobility/anchor_fixture.gd")
const H = preload("res://game/core/streamed_run_world.gd")
const Planner = preload("res://game/world/mobility_anchor_query.gd")
const Props = preload("res://game/world/world_prop_catalog.gd")
func run(t) -> void:
	var s := F.make()
	var footprint := Props.rect(s.definitions.props.definitions.house_narrow.ground_footprint)
	footprint.position += Vector2(144,224)
	var center := footprint.get_center()
	for direction in [Vector2.RIGHT,Vector2.LEFT,Vector2.UP,Vector2.DOWN]:
		var start: Vector2 = center-direction*(Vector2(footprint.size.x,footprint.size.y)*0.5+Vector2.ONE*32)
		s.state.player.position = [start.x,start.y]
		# Moving the approach can add a whole column to VIEW_MARGIN coverage.
		s.hydration = F.F.hydration(H.requirements(s.state))
		var prepared: Dictionary = s.helper.prepare(s.state,s.hydration)
		t.check(prepared.get("ok",false),"four-sided fixture hydrates its current required coverage: "+str(direction))
		if not prepared.get("ok",false): continue
		var result: Dictionary = Planner.plan(s.state,direction,s.helper)
		t.check(result.get("ok",false),"calibrated roof supports real four-sided approach: "+str(direction))
		if not result.get("ok",false): continue
		var rise := F.point(result.path[1],s.state.world.origin_chunk)
		var over := F.point(result.path[2],s.state.world.origin_chunk)
		var landing := F.point(result.landing,s.state.world.origin_chunk)
		t.check(s.helper.walkable(landing,8).get("walkable",false),"four-sided calibrated roof path lands outside real floor geometry")
		t.check(s.helper.sweep(rise,over-rise,8).fraction < 1.0,"ordinary collision still blocks the calibrated roof")
		t.check(s.helper.mobility_sweep(s.state,rise,over-rise,8,result.anchor,144).get("fraction",0.0) == 1.0,"confirmed calibrated segment crosses only its signed roof")
		if direction.x != 0:
			# The actual front wall is x11..103 in the 160px source asset.
			# Allow at most 8px floor padding plus 2*radius + 2*edge margin.
			t.check(rise.distance_to(over) <= 92+8+16+8,"horizontal crossing does not traverse the transparent right side of the sprite")
		var changed: Dictionary = s.definitions.duplicate(true)
		changed.props.definitions.house_narrow.ground_footprint[2] -= 2
		changed.props.definitions.house_narrow.mobility_anchor.pass_range[2] -= 2
		var cold := H.new(changed)
		var changed_prepared: Dictionary = cold.prepare(s.state,s.hydration)
		t.check(changed_prepared.get("ok",false),"changed physical footprint prepares independently: "+str(direction)+" "+str(changed_prepared.get("error_code","")))
		if not changed_prepared.get("ok",false): continue
		var rejected: Dictionary = cold.mobility_sweep(s.state,rise,over-rise,8,result.anchor,144)
		t.check(rejected.get("error_code","") == "stale_mobility_anchor","a stored confirmed segment cannot survive actual footprint calibration")
