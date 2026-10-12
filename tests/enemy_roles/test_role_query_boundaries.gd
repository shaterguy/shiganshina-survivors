extends RefCounted
const Q = preload("res://game/combat/enemy_world_query.gd")
const Model = preload("res://game/combat/enemy_attack_model.gd")
const Budget = preload("res://game/combat/enemy_threat_budget.gd")
const F = preload("res://tests/enemy_roles/role_fixture.gd")
const WF = preload("res://tests/core_world/new_streamed_helper_fixture.gd")
const H = preload("res://game/core/streamed_run_world.gd")
const Catalog = preload("res://game/combat/enemy_role_catalog.gd")
const Behavior = preload("res://game/combat/enemy_behaviors.gd")
const Hash = preload("res://game/combat/spatial_hash.gd")
const Counted = preload("res://tests/enemy_roles/counted_role_world.gd")
var catalog: Dictionary
func run(t) -> void:
	catalog = F.read_catalog(t)
	_factory_type_boundaries(t)
	_collection_cost_on_world_failure(t)
	_real_cover_and_late_failure(t)
	_rebase_cap(t)
	_observed_intervals_and_shapes(t)
	_body_prefix_boundaries(t)
	_hash_boundaries(t)
	_projection_filter_bounds(t)
	_checked_recovery_cap(t)
	_collection_cost_on_slot_rejection(t)
	_count_actual_work(t)
func _fixture() -> Dictionary:
	var helper = H.new(WF.definitions()); var state := WF.state(helper)
	var ready: Dictionary = helper.prepare(state,WF.hydration(H.requirements(state)))
	return {"helper":helper,"state":state,"ready":ready}
func _context() -> Dictionary:
	return {"tick":100,"survival_tick":28800,"move_speed":150.0,"player_radius":8.0,"reaction_ticks":21,"margin":8.0,"candidate_wait_since":80,"geometry_fully_loaded":true,"max_work_units":8192,"grab_reach_caps":{},"legacy_cover_modes":{},"observed_bodies":[],"observation_work_units":0,"observation_counts":{}}
func _grab(query, origin: Array = [384,384], target: Array = [554,384], source: int = 1) -> Dictionary:
	var actor := F.actor("grabber",origin); actor.id = source
	return Model.begin_query(actor,F.player(target),100,Catalog.profile(catalog,"grabber"),query,"run:enemy:%d:1" % source)
func _legacy(id: String, geometry: Array, active: int = 100, ends: int = 101, source: int = 2) -> Dictionary:
	return {"legacy_projection":true,"attack_id":id,"source_id":source,"active_from_tick":active,"attack_ends_tick":ends,"threat_cost":2,"damage_geometry":geometry}
func _real_cover_and_late_failure(t) -> void:
	var f := _fixture(); var q := Q.for_streamed(f.helper,f.state)
	var chosen := {}
	for prop in f.helper.props_query(Rect2(0,0,768,768)).props:
		if (int(prop.cover_mask)&4) != 0: chosen = prop; break
	t.check(not chosen.is_empty(),"real cover fixture has mask4 convex building")
	if chosen.is_empty(): return
	var box: Rect2 = chosen.ground_footprint
	var origin := Vector2(box.position.x-40,box.get_center().y)
	var target := Vector2(box.end.x+40,box.get_center().y)
	var sample := {"requires_visibility":true,"visibility_origin":[origin.x,origin.y]}
	var direct: Dictionary = f.helper.cover_query(origin,target,0,4)
	t.check(direct.ok and direct.hit_prop_id == chosen.prop_id and direct.fraction < 1,"real mask4 query hits selected prop")
	var seen := q.visibility(sample,target+Vector2(0,2),target-Vector2(0,2))
	t.check(seen.ok and not seen.visible and seen.blocked_by_solid and q.status().queries.cover_calls == 2,"same actual prop ID occludes entire swept segment")
	var from := Vector2(384,384)
	var left := Vector2(144,120); var right := Vector2(624,120)
	var first: Dictionary = f.helper.cover_query(from,left,0,4); var last: Dictionary = f.helper.cover_query(from,right,0,4)
	t.check(first.ok and last.ok and not first.hit_prop_id.is_empty() and not last.hit_prop_id.is_empty() and first.hit_prop_id != last.hit_prop_id,"real pair intersects different buildings")
	seen = q.visibility({"requires_visibility":true,"visibility_origin":[384,384]},right,left)
	t.check(seen.ok and seen.visible,"different actual prop IDs conservatively preserve visibility")
	var failed := q.visibility(sample,Vector2(8000,384))
	t.check(not failed.ok and failed.error_code == "world_not_ready" and not f.helper.query_status().ok,"late real cover failure preserved by adapter and helper")
	# Require that already-installed adapter becomes stale after same helper reprepare.
	var old := Q.for_streamed(f.helper,f.state)
	f.helper.prepare(f.state,WF.hydration(H.requirements(f.state)))
	t.check(not old.status().ok,"failure cannot be cleared by reprepare behind same adapter")
	old = Q.for_streamed(f.helper,f.state)
	f.helper.prepare(f.state,WF.hydration(H.requirements(f.state)))
	t.check(not old.sweep(Vector2(384,384),Vector2(10,0),22).ok,"helper republish invalidates old adapter even at equal scalar revision")
func _rebase_cap(t) -> void:
	var f := _fixture(); var q := Q.for_streamed(f.helper,f.state)
	var b := _grab(q,[1050,384],[1200,384])
	t.check(b.ok,"rebase fixture begins in real streamed city")
	if not b.ok: return
	var state: Dictionary = f.state.duplicate(true); state.player.position = [1200,384]; state.enemy_attack_instances = [b.attack]
	var old_sample := Model.sample_query(b.attack,170,q,b.grab_reach_cap)
	var shifted := H.rebase_proposal(state)
	t.check(shifted.ok and shifted.changed,"actual streamed rebase translates raw attack locks")
	if not shifted.ok: return
	var helper = H.new(WF.definitions())
	t.check(helper.prepare(shifted.state,WF.hydration(H.requirements(shifted.state))).ok,"rebased representation prepares same absolute terrain")
	var translated := Model.sample_query(shifted.state.enemy_attack_instances[0],170,Q.for_streamed(helper,shifted.state),b.grab_reach_cap)
	t.check(old_sample.ok and translated.ok,"old/new prepared samples both succeed")
	if old_sample.ok and translated.ok:
		for field in old_sample.sample.hand_pose:
			var before := Model._vec(old_sample.sample.hand_pose[field])
			var after := Model._vec(translated.sample.hand_pose[field])+Model._vec(shifted.offset)
			t.check(before.distance_to(after) < 0.0002,"cap/hand absolute continuity at rebase: "+field)
		t.check(translated.sample.phase == old_sample.sample.phase and shifted.state.enemy_attack_instances[0].attack_id == b.attack.attack_id,"rebase preserves phase and identity")
func _observed_intervals_and_shapes(t) -> void:
	var q := Q.for_finite({}); var b := _grab(q,[0,0],[170,0]); var c := _context()
	c.grab_reach_caps[b.attack.attack_id] = b.grab_reach_cap; c.move_speed = 0.0
	var player := F.player([300,0])
	# Committed active interval, not warning interval. Geometry only active at145.
	var runner := Behavior.profile({"enemy_id":"runner"})
	var body_origin := Vector2(270,0)
	var full_end := body_origin+Vector2.RIGHT*float(runner.rush_speed)*int(runner.active_ticks)/60.0
	var hazard := Model._line(body_origin,full_end,float(runner.width))
	var projection := _legacy("runner:warning",[hazard],145,165)
	c.legacy_cover_modes[projection.attack_id] = ["none"]
	var diagnostics := {"sample_calls":0}
	var records := Budget._danger_at([projection],144,q,diagnostics,c)
	t.check(records.is_empty(),"observed W boundary has no early danger")
	records = Budget._danger_at([projection],145,q,diagnostics,c)
	t.check(records.size() == 1 and records[0].geometry == hazard,"observed active boundary uses actual legacy geometry")
	t.check(Budget._danger_at([projection],165,q,diagnostics,c).is_empty(),"legacy expiration is half open and recovery harmless")
	var remaining := maxi(0,165-150-1)
	var tail := Model._line(Vector2(294,0),Vector2(294+float(runner.rush_speed)*remaining/60,0),32)
	t.check(is_equal_approx(tail.length,56.0) and Budget._swept_hits(tail,Vector2(349,0),Vector2(349,0),0) and not Budget._swept_hits(tail,Vector2(370,0),Vector2(370,0),0),"post-move remaining14 capsule excludes traveled/full20 future overrun")
	var sector := {"shape":"sector","origin":[300,0],"direction":[1.0,0.0],"radius":100.0,"arc_degrees":90.0}
	var body := Model._circle(Vector2(300,0),20)
	projection = _legacy("sweep:body",[sector,body]); c.legacy_cover_modes = {projection.attack_id:["none","none"]}
	player.position = [285,0]
	var blocked := Budget.evaluate_query(b.attack,[projection],player,q,c)
	t.check(not Budget._swept_hits(sector,Vector2(285,0),Vector2(285,0),0) and blocked.reason == "no_safe_path","body behind sector remains reserved once per source")
	var world := {"bounds":[-500,-500,1000,1000],"obstacles":[[26,-100,10,200]]}
	q = Q.for_finite(world); b = _grab(q,[150,0],[170,0]); c.grab_reach_caps = {b.attack.attack_id:b.grab_reach_cap}; player.position = [60,0]
	projection = _legacy("cover:hazard",[Model._circle(Vector2.ZERO,96)]); c.legacy_cover_modes = {projection.attack_id:["legacy_mask4"]}
	var covered := Budget.evaluate_query(b.attack,[projection],player,q,c)
	t.check(covered.accepted and covered.diagnostics.visibility_blocked > 0,"checked legacy mask4 authorizes actual wall cover")
	c.legacy_cover_modes[projection.attack_id] = ["none"]
	t.check(Budget.evaluate_query(b.attack,[projection],player,q,c).reason == "no_safe_path","checked body/cover-none keeps physical pressure through visibility exemption")
	projection.attack_ends_tick = 100; projection.active_from_tick = 99
	t.check(Budget.evaluate_query(b.attack,[projection],player,q,c).accepted,"expired observed attack takes no slot and no damage")
	projection = _legacy("late:cover",[Model._circle(Vector2(8000,384),8000)]); c = _context(); c.move_speed = 0.0
	var f := _fixture(); q = Q.for_streamed(f.helper,f.state); b = _grab(q); c.grab_reach_caps[b.attack.attack_id] = b.grab_reach_cap; c.legacy_cover_modes[projection.attack_id] = ["legacy_mask4"]
	var failed := Budget.evaluate_query(b.attack,[projection],F.player([554,384]),q,c)
	t.check(failed.reason == "world_unavailable" and failed.diagnostics.query_error.error_code == "world_not_ready" and failed.diagnostics.geometry_queries == 1,"budget late cover error is never treated as wall-safe")
func _body_prefix_boundaries(t) -> void:
	var q := Q.for_finite({}); var b := _grab(q,[0,0],[170,0]); var c := _context(); c.grab_reach_caps[b.attack.attack_id] = b.grab_reach_cap
	var player := F.player([170,0])
	for ticks in [0,20,21]:
		var reach: float = 32.0+43.0*ticks/60.0+16.0
		for gap in [-0.01,0.01]:
			c.observed_bodies = [{"source_id":99,"origin":[170+reach+gap,0],"body_radius":32.0,"move_speed":43.0,"observed_until_tick":100+ticks}]
			var r := Budget.evaluate_query(b.attack,[],player,q,c)
			t.check((r.reason == "no_safe_path" and r.diagnostics.detail == "observed_body_pressure") if gap < 0 else r.accepted,"reaction bound exact at ticks%d gap%s" % [ticks,gap])
			t.check(r.diagnostics.observed_body_tests == 1,"body exact test evaluated once across reaction paths")
			if gap < 0: t.check(r.diagnostics.current_contact_rejections == 0 and r.diagnostics.bounded_pressure_rejections == 1,"safety margin and expanded bound are not reported as actual body contact")
	c.observed_bodies = [{"source_id":99,"origin":[209.99,0],"body_radius":32.0,"move_speed":43.0,"observed_until_tick":121}]
	var contact := Budget.evaluate_query(b.attack,[],player,q,c)
	t.check(contact.diagnostics.current_contact_rejections == 1 and contact.diagnostics.bounded_pressure_rejections == 0,"actual current body contact separately counted at player radius8")
	c.observed_bodies = [{"source_id":" \t ","origin":[600,0],"body_radius":32.0,"move_speed":43.0,"observed_until_tick":121}]
	t.check(Budget.evaluate_query(b.attack,[],player,q,c).accepted,"checked observed body preserves actual Core nonempty whitespace source")
	c.observed_bodies[0].observed_until_tick = 122
	t.check(Budget.evaluate_query(b.attack,[],player,q,c).diagnostics.detail == "invalid_observed_interval","tick22 lies beyond common stationary prefix")
	c.observed_bodies[0].observed_until_tick = 121
	for field in ["body_radius","move_speed"]:
		var old: Variant = c.observed_bodies[0][field]; c.observed_bodies[0][field] = NAN
		t.check(Budget.evaluate_query(b.attack,[],player,q,c).reason == "invalid_candidate","nonfinite observed "+field+" rejected")
		c.observed_bodies[0][field] = old
	c.observed_bodies.append(c.observed_bodies[0].duplicate(true))
	t.check(Budget.evaluate_query(b.attack,[],player,q,c).diagnostics.detail == "duplicate_observed_source","duplicate body source rejected")
	c.observed_bodies = []; c.observation_counts = {"entity_count":180}; c.observation_work_units = 179
	t.check(Budget.evaluate_query(b.attack,[],player,q,c).diagnostics.detail == "uncharged_observation_work","reported collection cost cannot hide count180")
	c.observation_counts = {}; c.observation_work_units = 0; c.max_work_units = 0
	c.observed_bodies = [{"source_id":99,"origin":[170,0],"body_radius":32.0,"move_speed":43.0,"observed_until_tick":121}]
	t.check(Budget.evaluate_query(b.attack,[],player,q,c).reason == "work_budget_exhausted","dense contact with no work left is distinct from proven body pressure")
	c.max_work_units = 8192
	t.check(Budget.evaluate_query(b.attack,[],player,q,c).diagnostics.detail == "observed_body_pressure","same dense contact with work available is genuine pressure rejection")
func _hash_boundaries(t) -> void:
	var records: Array = []
	var player := Vector2(63.99,63.99)
	var maximum := 32.0+43.0*21/60.0+16.0
	for index in 64:
		var axis := Vector2.RIGHT.rotated(TAU*index/64.0)
		for gap in [-0.01,0.01]:
			var point: Vector2 = player+axis*(maximum+gap)
			records.append({"id":records.size()+1,"position":[point.x,point.y],"radius":32.0,"speed":43.0})
	var hash = Hash.new(); hash.rebuild(records)
	var ids := hash.query(player,maximum)
	var broad: Array = []; var brute: Array = []
	for i in records.size():
		if player.distance_to(Model._vec(records[i].position)) <= maximum: brute.append(records[i].id)
	for i in ids:
		if player.distance_to(Model._vec(records[i].position)) <= maximum: broad.append(records[i].id)
	t.check(broad == brute and broad.size() == 64,"large radius/speed expanded center hash equals brute force at cell/circle boundaries")
func _checked_recovery_cap(t) -> void:
	var q := Q.for_finite({}); var candidate := _grab(q,[0,0],[170,0]); var live := _grab(q,[1000,0],[1170,0],2)
	# A raw live grabber in recovery still owns its historical cap until retirement.
	for key in ["started_tick","active_from_tick","attack_ends_tick","recover_ends_tick"]: live.attack[key] -= 80
	var c := _context(); c.grab_reach_caps[candidate.attack.attack_id] = candidate.grab_reach_cap
	var missing := Budget.evaluate_query(candidate.attack,[live.attack],F.player([170,0]),q,c)
	t.check(missing.reason == "invalid_candidate" and missing.diagnostics.detail == "invalid_grab_reach_cap","checked context requires cap even for live recovering grabber")
	c.grab_reach_caps[live.attack.attack_id] = live.grab_reach_cap
	t.check(Budget.evaluate_query(candidate.attack,[live.attack],F.player([170,0]),q,c).accepted,"recovering live grab with valid cap consumes zero slots")
func _count_actual_work(t) -> void:
	var f := _fixture()
	# Replace only derived backend with counted subclass, using same generator,
	# seed, hydration and inherited real algorithms; no fake collision answers.
	var h = f.helper; var needed := H.requirements(f.state); var hydration := WF.hydration(needed)
	var counted = Counted.new(h._generator,int(f.state.seed))
	t.check(counted.prepare(needed.chunks,[],hydration,f.state.world.origin_chunk,needed.origin_chunk).ok,"counted real streamed backend prepares")
	h._world = counted
	var times: Array[int] = []; var accepted := 0; var logical := 0; var queries := {}
	for iteration in 40:
		var q := Q.for_streamed(h,f.state)
		var start := Time.get_ticks_usec(); var b := _grab(q,[290,210],[450,210]); var c := _context(); c.grab_reach_caps[b.attack.attack_id] = b.grab_reach_cap
		var legacy := _legacy("legacy:2:100",[Model._line(Vector2(290,300),Vector2(370,300),32.0)],145,165)
		c.legacy_cover_modes[legacy.attack_id] = ["legacy_mask4"]
		var result := Budget.evaluate_query(b.attack,[legacy],F.player([450,210]),q,c)
		times.append(Time.get_ticks_usec()-start)
		if result.accepted: accepted += 1
		logical += int(result.diagnostics.work_units); queries = q.status().queries
	times.sort()
	t.check(accepted == 40 and counted.candidate_props > 0 and counted.narrow_tests > 0,"real-cost sample has accepted attacks and real candidate/narrow collision work")
	print("T1 COUNTED accepted=%d/40 logical_sum=%d last_queries=%s candidates=%d narrow=%d usec_p50=%d p95=%d max=%d" % [accepted,logical,queries,counted.candidate_props,counted.narrow_tests,times[19],times[37],times[-1]])
func _collection_cost_on_slot_rejection(t) -> void:
	var q := Q.for_finite({}); var b := _grab(q,[0,0],[170,0]); var c := _context(); c.grab_reach_caps[b.attack.attack_id] = b.grab_reach_cap
	var first := _legacy("legacy:2:1",[Model._circle(Vector2(400,0),20)],120,150,2)
	var second := _legacy("legacy:3:1",[Model._circle(Vector2(-400,0),20)],120,150,3)
	c.legacy_cover_modes = {first.attack_id:["none"],second.attack_id:["none"]}
	c.observation_counts = {"entity_count":180,"telegraph_count":2,"reservation_count":2,"primitive_count":2}
	c.observation_work_units = 186
	var r := Budget.evaluate_query(b.attack,[first,second],F.player([170,0]),q,c)
	t.check(r.reason == "budget_full" and r.diagnostics.work_units == 186 and r.diagnostics.get("observation_counts",{}) == c.observation_counts,"slot rejection retains already-performed collection work/counts")
	t.check(r.diagnostics.paths_tested == 0 and r.diagnostics.get("observed_body_tests",-1) == 0,"slot rejection does not run path search/body prefix")
func _projection_filter_bounds(t) -> void:
	# Test-only observation assembly. T2 must repeat this with the real collector.
	# All probes are within the player's finite reachable disk and active window.
	var center := Vector2(170,0); var tick := 100; var end := 176
	var reach := 225.0*(end-tick-1-21)/60.0
	var bounds := Rect2(center-Vector2.ONE*(reach+16),Vector2.ONE*(reach+16)*2)
	var inputs: Array[Dictionary] = []
	for x in [center.x-reach-20,center.x,center.x+reach+20,center.x+reach+200]:
		for interval in [[99,100],[100,101],[175,176],[176,177]]:
			for geometry in [Model._circle(Vector2(x,0),24),Model._line(Vector2(x,-80),Vector2(x,80),32),{"shape":"sector","origin":[x,0],"direction":[-1.0,0.0],"radius":100.0,"arc_degrees":90.0}]:
				inputs.append(_legacy("projection:"+str(inputs.size()),[geometry],interval[0],interval[1],inputs.size()+2))
	var kept := {}; var relevant := {}; var excluded_time := 0; var excluded_bounds := 0
	for a in inputs:
		var in_time: bool = a.active_from_tick < end and a.attack_ends_tick > tick
		var g: Dictionary = a.damage_geometry[0]
		var point := Model._vec(g.origin)
		var rectangle: Rect2
		if g.shape == "line":
			var target := point+Model._vec(g.direction)*float(g.length)
			rectangle = H.segment_rect(point,target,float(g.width)*0.5)
		else: rectangle = Rect2(point-Vector2.ONE*float(g.radius),Vector2.ONE*float(g.radius)*2)
		if not in_time: excluded_time += 1
		elif not bounds.intersects(rectangle,true): excluded_bounds += 1
		else: kept[a.attack_id] = true
		if not in_time: continue
		for direction in 32:
			for distance in [0.0,reach*0.5,reach]:
				var probe: Vector2 = center+Vector2.RIGHT.rotated(TAU*direction/32.0)*distance
				if Budget._swept_hits(g,probe,probe,16): relevant[a.attack_id] = true
	var omitted := 0
	for id in relevant:
		if not kept.has(id): omitted += 1
	t.check(omitted == 0 and relevant.size() > 0 and excluded_time > 0 and excluded_bounds > 0,"observed hazard AABB/time filter includes brute-force relevant circle/line/sector boundary probes")
	t.check(not kept.has(inputs[0].attack_id),"damage ending exactly at current tick is outside observation window")
	print("T1 FILTER constructed=%d kept=%d brute_relevant=%d time_filtered=%d bounds_filtered=%d omitted=%d" % [inputs.size(),kept.size(),relevant.size(),excluded_time,excluded_bounds,omitted])

func _factory_type_boundaries(t) -> void:
	var f := _fixture()
	for field in ["stage","scene_id"]:
		for value in [[],{},true,0,0.0,null]:
			var state: Dictionary = f.state.duplicate(true)
			state.world[field] = value
			var query = Q.for_streamed(f.helper,state)
			t.check(query != null and not query.status().ok and query.status().get("error_code") == "world_not_ready","factory rejects non-String %s %s through status, without null/exception" % [field,var_to_str(value)])
	t.check(f.helper.query_status().ok and Q.for_streamed(f.helper,f.state).status().ok,"malformed factory input does not poison prepared helper")
func _collection_cost_on_world_failure(t) -> void:
	var f := _fixture(); var q := Q.for_streamed(f.helper,f.state); var b := _grab(q)
	var c := _context(); c.grab_reach_caps[b.attack.attack_id] = b.grab_reach_cap
	c.observation_counts = {"entity_count":180}; c.observation_work_units = 180
	q.sweep(Vector2(384,384),Vector2(8000,0),22)
	var prior := q.status()
	t.check(not prior.ok,"collection failure fixture has actual sticky streamed query error")
	for loaded in [true,false]:
		for maximum in [8192,100]:
			c.geometry_fully_loaded = loaded; c.max_work_units = maximum
			var r := Budget.evaluate_query(b.attack,[],F.player([554,384]),q,c)
			t.check(r.reason == "world_unavailable" and r.diagnostics.get("query_error",{}) == prior,"collection diagnostics preserve exact world failure before other rejection")
			t.check(r.diagnostics.get("observation_counts",{}) == c.observation_counts and r.diagnostics.get("observation_work_units",-1) == 180 and r.diagnostics.work_units == mini(180,maximum),"failed query retains validated collection count/work including exhausted logical budget")
			t.check(r.diagnostics.paths_tested == 0 and r.diagnostics.get("observed_body_tests",-1) == 0 and q.status() == prior,"early world failure performs no path/body/additional world query")
	c.geometry_fully_loaded = true; c.max_work_units = 8192
	var missing := Budget.evaluate_query(b.attack,[],F.player([554,384]),null,c)
	t.check(missing.reason == "world_unavailable" and missing.diagnostics.get("observation_counts",{}) == c.observation_counts and missing.diagnostics.work_units == 180,"missing query also preserves validated performed collection")
	c.geometry_fully_loaded = false
	var uncovered := Budget.evaluate_query(b.attack,[],F.player([554,384]),Q.for_finite({}),c)
	t.check(uncovered.reason == "world_unavailable" and uncovered.diagnostics.get("observation_work_units",-1) == 180 and uncovered.diagnostics.work_units == 180,"coverage flag early exit preserves performed collection")
	c.geometry_fully_loaded = true
	for bad in [{"counts":[],"work":180},{"counts":{"entity_count":180},"work":179},{"counts":{"entity_count":-1},"work":180},{"counts":{"unknown_count":1},"work":180},{"counts":{"entity_count":180},"work":NAN}]:
		c.observation_counts = bad.counts; c.observation_work_units = bad.work
		var failed := Budget.evaluate_query(b.attack,[],F.player([554,384]),q,c)
		t.check(failed.reason == "world_unavailable" and failed.diagnostics.get("query_error",{}) == prior and failed.diagnostics.work_units == 0 and not failed.diagnostics.has("observation_counts"),"invalid observation metadata never trusted; prior world error retains precedence")
		t.check(Budget.evaluate_query(b.attack,[],F.player([554,384]),Q.for_finite({}),c).reason == "invalid_candidate","healthy world still rejects invalid observation metadata")
