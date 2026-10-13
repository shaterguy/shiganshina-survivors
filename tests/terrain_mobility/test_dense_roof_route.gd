extends RefCounted
const PATH := "res://game/world/mobility_anchor_query.gd"
const F = preload("res://tests/terrain_mobility/anchor_fixture.gd")
const Base = preload("res://tests/core_world/new_streamed_helper_fixture.gd")
const H = preload("res://game/core/streamed_run_world.gd")
func run(t) -> void:
	if not FileAccess.file_exists(PATH): return
	var planner = load(PATH)
	if planner == null or not planner.can_instantiate(): return
	var d := Base.definitions()
	for template in d.templates.templates:
		var front := {}
		for slot in template.slots:
			if float(slot.position[1]) <= 240.0 or float(slot.position[1]) >= 288.0: continue
			if not d.props.definitions[slot.definition_id].has("mobility_anchor"): continue
			front = slot
			break
		t.check(not front.is_empty(),"each dense district offers an intact front-row roof")
		if front.is_empty(): continue
		var s := F.make(template.slots)
		s.state.player.position = [float(front.position[0]),float(front.position[1])+32.0]
		s.hydration = Base.hydration(H.requirements(s.state))
		t.check(s.helper.prepare(s.state,s.hydration).ok,"dense front-row approach prepares actual data: "+template.template_id)
		var result: Dictionary = planner.plan(s.state,Vector2.UP,s.helper)
		t.check(result.get("ok",false),"dense front-row roof can land in the actual narrow alley before the next row: "+template.template_id)
		if not result.get("ok",false): continue
		var landing := F.point(result.landing,s.state.world.origin_chunk)
		t.check(s.helper.walkable(landing,8).get("walkable",false),"short descent ends inside the verified alley clearance")
		t.check(landing.x == float(front.position[0]) and landing.y < float(front.position[1]),"short alley landing preserves current input direction")
