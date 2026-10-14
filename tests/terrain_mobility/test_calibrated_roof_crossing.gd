extends RefCounted
# Four cardinal corridors retain calibrated normal collision. Legacy roof
# clearance remains admission-only and rejects recalibrated physical metadata.
const F = preload("res://tests/terrain_mobility/anchor_fixture.gd")
const C = preload("res://tests/corridor_mobility/corridor_fixture.gd")
const H = preload("res://game/core/streamed_run_world.gd")
const Planner = preload("res://game/world/mobility_anchor_query.gd")
func run(t) -> void:
	var cases := [
		{"direction":Vector2.UP,"position":[180.0,256.0],"slots":C.slots()},
		{"direction":Vector2.DOWN,"position":[180.0,120.0],"slots":C.slots()},
		{"direction":Vector2.RIGHT,"position":[80.0,384.0],"slots":[F.slot("top","house_narrow",[224,224]),F.slot("bottom","house_narrow",[224,544])]},
		{"direction":Vector2.LEFT,"position":[280.0,384.0],"slots":[F.slot("top","house_narrow",[224,224]),F.slot("bottom","house_narrow",[224,544])]}]
	for item in cases:
		var s := C.make(t,item.slots,item.position)
		var helper = s.core._streamed
		var result: Dictionary = Planner.plan(s.state,item.direction,helper)
		t.check(result.get("ok",false),"calibrated paired anchors support cardinal corridor: "+str(item.direction))
		if not result.get("ok",false): continue
		var start := F.point(result.path[0],s.state.world.origin_chunk)
		var end := F.point(result.path[1],s.state.world.origin_chunk)
		t.check(helper.walkable(end,8).get("walkable",false),"four-sided corridor ends outside real floor geometry")
		t.check(helper.sweep(start,end-start,8).fraction == 1.0,"ordinary collision approves the complete calibrated corridor")
		t.check((end-start).normalized().dot(item.direction) > 0.99999 and start.distance_to(end) <= 320.0002,"four-sided route follows only the current input within its range cap")
		var wall: Dictionary = helper._world._props[result.anchors[0].prop_id]
		var middle: Vector2 = wall.ground_footprint.get_center()
		t.check(not helper.walkable(middle,8).get("walkable",true),"anchor building remains solid and cannot become a live roof crossing")
	var legacy := F.legacy()
	t.check(legacy.prepared.get("ok",false),"captured v1 calibrated roof proof prepares for admission")
	var m: Dictionary = legacy.state.player_mobility
	var rise := F.point(m.path[1],legacy.state.world.origin_chunk)
	var over := F.point(m.path[2],legacy.state.world.origin_chunk)
	t.check(legacy.helper.sweep(rise,over-rise,8).fraction < 1.0,"legacy control remains blocked by ordinary collision")
	t.check(legacy.helper.mobility_sweep(legacy.state,rise,over-rise,8,m.anchor,144).get("fraction",0.0) == 1.0,"captured v1 signed segment remains valid only for old-save admission")
	var changed: Dictionary = legacy.definitions.duplicate(true)
	changed.props.definitions.house_narrow.ground_footprint[2] -= 2
	changed.props.definitions.house_narrow.mobility_anchor.pass_range[2] -= 2
	var cold := H.new(changed)
	t.check(cold.prepare(legacy.state,legacy.hydration).get("error_code","") == "stale_mobility_anchor","full legacy admission rejects changed physical geometry before installing its cache")
	var ground_context: Dictionary = legacy.state.duplicate(true)
	ground_context.erase("player_mobility")
	ground_context.player.position = [rise.x,rise.y]
	t.check(cold.prepare(ground_context,legacy.hydration).get("ok",false),"changed physical footprint independently prepares a legal ground control")
	t.check(cold.mobility_sweep(legacy.state,rise,over-rise,8,m.anchor,144).get("error_code","") == "stale_mobility_anchor","stored v1 signed segment cannot survive physical footprint calibration")
