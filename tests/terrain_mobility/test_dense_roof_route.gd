extends RefCounted
# Historical filename retained: dense-district coverage now proves genuine
# opposite-side alley routes rather than authorizing a single roof crossing.
const Planner = preload("res://game/world/mobility_anchor_query.gd")
const F = preload("res://tests/terrain_mobility/anchor_fixture.gd")
const Base = preload("res://tests/core_world/new_streamed_helper_fixture.gd")
const H = preload("res://game/core/streamed_run_world.gd")
const Props = preload("res://game/world/world_prop_catalog.gd")
func run(t) -> void:
	var d := Base.definitions()
	for template in d.templates.templates:
		var s := F.make(template.slots)
		var found := false
		for left in template.slots:
			for right in template.slots:
				if float(left.position[0]) >= float(right.position[0]) or left.position[1] != right.position[1]: continue
				var a: Dictionary = d.props.definitions[left.definition_id]
				var b: Dictionary = d.props.definitions[right.definition_id]
				if not a.has("mobility_anchor") or not b.has("mobility_anchor"): continue
				var ra := Props.rect(a.ground_footprint); ra.position += Vector2(left.position[0],left.position[1])
				var rb := Props.rect(b.ground_footprint); rb.position += Vector2(right.position[0],right.position[1])
				var gap: float = rb.position.x-ra.end.x
				if gap < 16.0 or gap >= 64.0: continue
				s.state.player.position = [(ra.end.x+rb.position.x)*0.5,maxf(ra.end.y,rb.end.y)+16.0]
				s.hydration = Base.hydration(H.requirements(s.state))
				t.check(s.helper.prepare(s.state,s.hydration).get("ok",false),"dense paired alley prepares actual district: "+template.template_id)
				var result: Dictionary = Planner.plan(s.state,Vector2.UP,s.helper)
				t.check(result.get("ok",false),"dense side-by-side buildings provide a genuine forward corridor: "+template.template_id)
				if not result.get("ok",false): continue
				var start := F.point(result.path[0],s.state.world.origin_chunk)
				var end := F.point(result.landing,s.state.world.origin_chunk)
				t.check(s.helper.walkable(end,8).get("walkable",false) and s.helper.sweep(start,end-start,8).fraction == 1.0,"dense corridor stays in the verified narrow alley and never crosses a roof")
				t.check(end.x == start.x and end.y < start.y and result.anchors.size() == 2,"dense alley preserves current input and both side attachments")
				found = true
		t.check(found,"every dense district exposes at least one real paired corridor: "+template.template_id)
