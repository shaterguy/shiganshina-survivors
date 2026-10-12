extends RefCounted
var Model = load("res://game/combat/enemy_attack_model.gd")
var Budget = load("res://game/combat/enemy_threat_budget.gd")
const Catalog = preload("res://game/combat/enemy_role_catalog.gd")
const F = preload("res://tests/enemy_roles/role_fixture.gd")
const WF = preload("res://tests/core_world/new_streamed_helper_fixture.gd")
const H = preload("res://game/core/streamed_run_world.gd")
const World = preload("res://game/combat/world_geometry.gd")
const Behaviors = preload("res://game/combat/enemy_behaviors.gd")
const Hash = preload("res://game/combat/spatial_hash.gd")
var Q
var catalog: Dictionary
func run(t) -> void:
	var path := "res://game/combat/enemy_world_query.gd"
	t.check(FileAccess.file_exists(path),"T1 prepared streamed enemy query adapter exists")
	t.check(Model.has_method("begin_query") and Model.has_method("sample_query") and Model.has_method("visibility_query"),"T1 checked model API exists")
	t.check(Budget.has_method("evaluate_query"),"T1 checked budget API exists")
	if not FileAccess.file_exists(path) or not Model.has_method("begin_query") or not Budget.has_method("evaluate_query"): return
	Q = load(path)
	t.check(Q != null and Q.can_instantiate(),"T1 world query compiles")
	if Q == null or not Q.can_instantiate(): return
	catalog = F.read_catalog(t)
	_checked_source_identity(t)
	_streamed_never_falls_back(t)
	_hand_cap_and_pose(t)
	_finite_differential(t)
	_visibility(t)
	_observations(t)
	_broadphase(t)
func _context() -> Dictionary:
	return {"tick":100,"survival_tick":28800,"move_speed":150.0,"player_radius":8.0,"reaction_ticks":21,"margin":8.0,"candidate_wait_since":80,"geometry_fully_loaded":true,"max_work_units":8192,"grab_reach_caps":{},"legacy_cover_modes":{},"observed_bodies":[],"observation_work_units":0,"observation_counts":{}}
func _prepared() -> Dictionary:
	var helper = H.new(WF.definitions())
	var state := WF.state(helper)
	var prepared: Dictionary = helper.prepare(state,WF.hydration(H.requirements(state)))
	return {"helper":helper,"state":state,"prepared":prepared}
func _begin(query, role: String = "grabber", origin: Array = [384,384], target: Array = [554,384], source: int = 1) -> Dictionary:
	var actor := F.actor(role,origin); actor.id = source
	return Model.begin_query(actor,F.player(target),100,Catalog.profile(catalog,role),query,"run:enemy:%d:1" % source)
func _streamed_never_falls_back(t) -> void:
	var f := _prepared(); var q = Q.for_streamed(f.helper,f.state)
	t.check(f.prepared.ok and q.status().ok,"actual prepared helper admits enemy query")
	var props: Array = f.helper.props_query(Rect2(-768,-768,2304,2304)).props
	t.check(props.size() > 32,"actual prepared city contains more than finite 32 prop limit")
	var witnessed := false
	for index in range(32,props.size()):
		var prop: Dictionary = props[index]
		if (int(prop.collision_mask)&3) == 0: continue
		var box: Rect2 = prop.ground_footprint
		var origin := Vector2(box.position.x-40,box.get_center().y)
		if not f.helper.walkable(origin,22).get("walkable",false): continue
		var expected: Dictionary = f.helper.sweep(origin,Vector2(120,0),22)
		if expected.get("hit_prop_id") != prop.prop_id: continue
		var actual: Dictionary = q.sweep(origin,Vector2(120,0),22)
		t.check(actual == expected and actual.fraction < 1.0,"prop beyond first32 retains exact blocker ID/fraction/position")
		witnessed = true; break
	t.check(witnessed,"beyond32 actual blocking prop witnessed")
	var bad: Dictionary = f.state.duplicate(true); bad.run_id = "other"
	t.check(not Q.for_streamed(f.helper,bad).status().ok,"foreign run helper fails")
	bad = f.state.duplicate(true); bad.world.origin_revision += 1
	t.check(not Q.for_streamed(f.helper,bad).status().ok,"stale origin helper fails")
	t.check(not Q.for_streamed(H.new(WF.definitions()),f.state).status().ok,"unprepared city never falls back to empty finite world")
	bad = f.state.duplicate(true); bad.world = {}
	t.check(not Q.for_streamed(f.helper,bad).status().ok,"empty city world rejected")
	bad = f.state.duplicate(true); bad.entities.append({"position":[5000,5000],"radius":20,"speed":30})
	t.check(Q.for_streamed(f.helper,bad).status().get("error_code") == H.requirements(bad).get("error_code") and not H.requirements(bad).ok,"over49 required chunks propagate capacity error: "+str(Q.for_streamed(f.helper,bad).status()))
	var late: Dictionary = q.sweep(Vector2(384,384),Vector2(8000,0),22)
	t.check(not late.ok and late.error_code == "world_not_ready","missing sweep coverage is explicit failure")
	t.check(not q.walkable(Vector2(384,384),8).ok and not f.helper.query_status().ok,"later valid query cannot erase sticky failure")
	t.check(not Q.for_streamed(f.helper,f.state).status().ok,"new adapter cannot reset existing helper failure")
	var a: Dictionary = Model.begin(F.actor("grabber",[384,384]),F.player([554,384]),100,Catalog.profile(catalog,"grabber"),{},"run:enemy:1:1").attack
	t.check(not Model.sample_query(a,160,q,210).ok,"query failure is not finished or harmless sample")
	var c := _context(); c.grab_reach_caps[a.attack_id] = 210.0
	var result: Dictionary = Budget.evaluate_query(a,_attacks(),F.player([554,384]),q,c)
	t.check(not result.accepted and result.reason == "world_unavailable" and result.diagnostics.get("query_error",{}).get("error_code") == "world_not_ready","budget propagates exact sticky query failure")
	c.geometry_fully_loaded = false
	result = Budget.evaluate_query(a,_attacks(),F.player([554,384]),q,c)
	t.check(result.reason == "world_unavailable" and result.diagnostics.get("query_error",{}).get("error_code") == "world_not_ready","false coverage flag preserves an already failed valid query error")
func _hand_cap_and_pose(t) -> void:
	var world := {"bounds":[-500,-500,1000,1000],"obstacles":[[100,-100,20,200]]}
	var q = Q.for_finite(world); var b := _begin(q,"grabber",[0,0],[80,0])
	t.check(b.ok and is_equal_approx(b.grab_reach_cap,78.0),"begin locks clipped hand reach")
	if not b.ok: return
	var a: Dictionary = b.attack; var cap: float = b.grab_reach_cap
	t.check(a.size() == Model.FIELDS.size() and Model.validate(a,a.profile).is_empty(),"reach cap is outside strict raw attack fields")
	for invalid in [-1.0,NAN,INF,211.0]:
		t.check(not Model.sample_query(a,160,q,invalid).ok,"checked grab sample requires finite owner cap")
	for tick in [100,159,160,175,176,259,260]:
		var r: Dictionary = Model.sample_query(a,tick,q,cap)
		t.check(r.ok and r.sample.position == [0.0,0.0],"same sample keeps torso fixed")
		if not r.ok: continue
		var s: Dictionary = r.sample
		for point in s.hand_pose.values(): t.check(float(point[0]) <= cap+0.0001,"every hand point respects announced cap")
		if tick >= 176: t.check(s.damage_geometry.is_empty(),"hand recovery and finish harmless")
		if tick == 160: t.check(is_equal_approx(s.hand_pose.current[0],50.625),"first active step uses original 40 to210 interpolation")
		if tick == 259: t.check(s.hand_pose.current == s.hand_pose.rest,"last recovery sample returns exactly to rest")
	var removed = Q.for_finite({"bounds":world.bounds,"obstacles":[]})
	t.check(Model.sample_query(a,175,removed,cap).sample.hand_pose.current == [78.0,0.0],"local blocker removal cannot enlarge original warning")
	var closer = Q.for_finite({"bounds":world.bounds,"obstacles":[[60,-100,20,200]]})
	t.check(Model.sample_query(a,175,closer,cap).sample.hand_pose.current == [38.0,0.0],"new closer blocker shortens hand below cap")
	var illegal = Q.for_finite({"bounds":world.bounds,"obstacles":[[-10,-10,20,20]]})
	t.check(not Model.sample_query(a,160,illegal,cap).ok,"illegal origin fails explicitly")
	var open := _begin(Q.for_finite({}),"grabber",[0,0],[190,0])
	t.check(open.grab_reach_cap == 210.0,"open begin locks full210")
	var s: Dictionary = Model.sample_query(open.attack,176,Q.for_finite({}),210).sample
	t.check(is_equal_approx(s.hand_pose.current[0],lerpf(210,40,1.0/84.0)),"first recovery tick retracts 1of84 without damage")
	_real_cap_changes(t)
func _real_cap_changes(t) -> void:
	var f := _prepared(); var props: Array = f.helper.props_query(Rect2(0,0,768,768)).props
	var chosen := {}; var begun := {}; var origin := Vector2.ZERO
	for prop in props:
		if not prop.destructible: continue
		var box: Rect2 = prop.ground_footprint; origin = Vector2(box.position.x-90,box.get_center().y)
		if not f.helper.walkable(origin,22).get("walkable",false): continue
		var q = Q.for_streamed(f.helper,f.state)
		begun = _begin(q,"grabber",[origin.x,origin.y],[origin.x+80,origin.y])
		if begun.ok and begun.grab_reach_cap < 210: chosen = prop; break
	t.check(not chosen.is_empty(),"real city clipped reach fixture found")
	if chosen.is_empty(): return
	var a: Dictionary = begun.attack; var cap: float = begun.grab_reach_cap
	var before: Dictionary = Model.sample_query(a,175,Q.for_streamed(f.helper,f.state),cap)
	var remote: Dictionary = {}
	for prop in props:
		if prop.destructible and prop.prop_id != chosen.prop_id and prop.ground_footprint.get_center().distance_to(origin) > 250:
			remote = prop; break
	t.check(not remote.is_empty(),"distant destructible city fixture exists")
	if remote.is_empty(): return
	var changed: Dictionary = f.state.duplicate(true)
	changed.world.world_revision = 1
	changed.world.dirty_chunks = [{"chunk":["0","0"],"props":[{"slot_id":remote.slot_id,"hp":0,"destroyed":true}]}]
	t.check(f.helper.prepare(changed,WF.hydration(H.requirements(changed))).ok,"actual remote prop removal re-prepares")
	var after: Dictionary = Model.sample_query(a,175,Q.for_streamed(f.helper,changed),cap)
	t.check(after.ok and after.sample == before.sample,"unrelated world revision preserves clock and hand sample")
	changed.world.world_revision = 2
	changed.world.dirty_chunks = [{"chunk":["0","0"],"props":[{"slot_id":chosen.slot_id,"hp":0,"destroyed":true}]}]
	t.check(f.helper.prepare(changed,WF.hydration(H.requirements(changed))).ok,"actual local blocker removal re-prepares")
	after = Model.sample_query(a,175,Q.for_streamed(f.helper,changed),cap)
	t.check(after.ok and after.sample.hand_pose.current == before.sample.hand_pose.current,"real local removal retains cap")
func _finite_differential(t) -> void:
	for world in [{},{"bounds":[-500,-500,1000,1000],"obstacles":[[100,-100,20,200]]}]:
		for role in F.ROLE_IDS:
			var p := Catalog.profile(catalog,role); var actor := F.actor(role); var player := F.player([20,0])
			var before: Array = [actor.duplicate(true),player.duplicate(true),world.duplicate(true)]
			var old: Dictionary = Model.begin(actor,player,100,p,world,"run:enemy:1:1")
			var checked: Dictionary = Model.begin_query(actor,player,100,p,Q.for_finite(world),"run:enemy:1:1")
			t.check(old.ok and checked.ok and old.attack == checked.attack,"finite begin differential "+role)
			for tick in [99,100,int(old.attack.active_from_tick)-1,int(old.attack.active_from_tick),int(old.attack.attack_ends_tick)-1,int(old.attack.attack_ends_tick),int(old.attack.recover_ends_tick)]:
				var sampled: Dictionary = Model.sample_query(old.attack,tick,Q.for_finite(world),checked.get("grab_reach_cap",-1.0))
				t.check(sampled.ok,"finite checked sample succeeds "+role)
				if sampled.ok:
					var comparable: Dictionary = sampled.sample.duplicate(true); comparable.erase("hand_pose")
					t.check(comparable == Model.sample(old.attack,tick,world),"finite sample differential "+role)
			t.check([actor,player,world] == before,"checked API inputs remain immutable")
			var c := _context(); c.grab_reach_caps[old.attack.attack_id] = checked.get("grab_reach_cap",-1.0)
			var legacy: Dictionary = Budget.evaluate(old.attack,_attacks(),player,world,c)
			var newer: Dictionary = Budget.evaluate_query(old.attack,_attacks(),player,Q.for_finite(world),c)
			t.check(legacy.accepted == newer.accepted and legacy.reason == newer.reason and legacy.safe_path == newer.safe_path and legacy.diagnostics.work_units == newer.diagnostics.work_units,"finite budget path/order/charging differential "+role)
func _visibility(t) -> void:
	var s := {"requires_visibility":true,"visibility_origin":[0,0]}
	var q = Q.for_finite({"bounds":[-500,-500,1000,1000],"obstacles":[[26,-100,10,200]]})
	t.check(not Model.visibility_query(s,Vector2(60,10),q,Vector2(60,-10)).visible,"same convex blocker proves swept occlusion")
	var split = Q.for_finite({"bounds":[-500,-500,1000,1000],"obstacles":[[26,2,10,100],[26,-102,10,100]]})
	t.check(Model.visibility_query(s,Vector2(60,30),split,Vector2(60,-30)).visible,"different blockers cannot prove whole swept path hidden")
	t.check(not Model.visibility_query({},Vector2.ZERO,q).ok,"visibility discriminator cannot silently exempt malformed input")
func _observations(t) -> void:
	var f := _prepared(); var q = Q.for_streamed(f.helper,f.state)
	var b := _begin(q); t.check(b.ok,"mixed fixture actual grab begins")
	if not b.ok: return
	var c := _context(); c.grab_reach_caps[b.attack.attack_id] = b.grab_reach_cap
	var p: Dictionary = Behaviors.profile({"enemy_id":"runner"})
	var legacy := {"legacy_projection":true,"attack_id":"legacy:2:100","source_id":2,"active_from_tick":145,"attack_ends_tick":165,"threat_cost":2,"damage_geometry":[Model._line(Vector2(384,460),Vector2(384+float(p.rush_speed)*int(p.active_ticks)/60.0,460),float(p.width))]}
	c.legacy_cover_modes[legacy.attack_id] = ["legacy_mask4"]
	var start := Time.get_ticks_usec()
	var result: Dictionary = Budget.evaluate_query(b.attack,_attacks([legacy]),F.player([554,384]),q,c)
	print("T1 MIXED accepted=%s reason=%s work=%s elapsed_us=%s query=%s" % [result.accepted,result.reason,result.diagnostics.work_units,Time.get_ticks_usec()-start,q.status()])
	t.check(result.accepted and result.diagnostics.strong_slots_used == 3,"actual prepared city admits cost1 grab plus cost2 legacy runner")
	var two := legacy.duplicate(true); two.attack_id = "legacy:3:100"; two.source_id = 3; c.legacy_cover_modes[two.attack_id] = ["none"]
	t.check(Budget.evaluate_query(b.attack,_attacks([legacy,two]),F.player([554,384]),q,c).reason == "budget_full","two observed cost2 reservations exceed strong slots")
	c.legacy_cover_modes.erase(legacy.attack_id)
	t.check(Budget.evaluate_query(b.attack,_attacks([legacy]),F.player([554,384]),q,c).reason == "invalid_candidate","missing cover sidecar rejected")
	c.legacy_cover_modes[legacy.attack_id] = []
	t.check(Budget.evaluate_query(b.attack,_attacks([legacy]),F.player([554,384]),q,c).reason == "invalid_candidate","cover sidecar length mismatch rejected")
	c.legacy_cover_modes = {}; c.observed_bodies = [{"source_id":8,"origin":[600,384],"body_radius":18.0,"move_speed":43.0,"observed_until_tick":121}]
	var pressured: Dictionary = Budget.evaluate_query(b.attack,_attacks(),F.player([554,384]),q,c)
	t.check(pressured.reason == "no_safe_path" and pressured.diagnostics.detail == "observed_body_pressure" and pressured.diagnostics.observed_body_tests == 1,"reaction body bound checked once before272 search")
	c.observed_bodies[0].observed_until_tick = 122
	t.check(Budget.evaluate_query(b.attack,_attacks(),F.player([554,384]),q,c).reason == "invalid_candidate","body observation past common reaction prefix rejected")
	c.observed_bodies = []; c.observation_work_units = 8192
	t.check(Budget.evaluate_query(b.attack,_attacks(),F.player([554,384]),q,c).reason == "work_budget_exhausted","collection cost charged before search without bypass")
func _broadphase(t) -> void:
	# Constructed current observations, not the later Core collector implementation.
	var entities: Array = [{"id":1,"enemy_id":"grabber","position":[384,384],"radius":20,"speed":50,"action_state":"windup"},{"id":2,"enemy_id":"runner","position":[600,420],"radius":16,"speed":34,"action_state":"windup"}]
	for index in 178: entities.append({"id":index+3,"enemy_id":"walker","position":[2000+index*64,2000],"radius":18,"speed":24,"action_state":"move"})
	var hash = Hash.new(); hash.rebuild(entities)
	var player := Vector2(554,384); var radius := 32.0+43.0*21.0/60.0+16.0
	var ids: Array = hash.query(player,radius)
	var brute: Array = []
	var filtered: Array = []
	for i in entities.size():
		var e: Dictionary = entities[i]
		if e.action_state == "move" and player.distance_to(Model._vec(e.position)) <= float(e.radius)+float(e.speed)*21/60.0+16: brute.append(e.id)
	for i in ids:
		var e: Dictionary = entities[i]
		if e.action_state == "move" and player.distance_to(Model._vec(e.position)) <= float(e.radius)+float(e.speed)*21/60.0+16: filtered.append(e.id)
	t.check(entities.size() == 180 and ids.size() < 3 and filtered == brute,"real point hash180 mostly far equals exhaustive relevant input without truncation")
	var f := _prepared(); var q = Q.for_streamed(f.helper,f.state); var b := _begin(q)
	var c := _context(); c.grab_reach_caps[b.attack.attack_id] = b.grab_reach_cap
	var legacy := {"legacy_projection":true,"attack_id":"legacy:2:100","source_id":2,"active_from_tick":145,"attack_ends_tick":165,"threat_cost":2,"damage_geometry":[Model._line(Vector2(600,420),Vector2(680,420),32.0)]}
	c.legacy_cover_modes[legacy.attack_id] = ["legacy_mask4"]
	var near: Dictionary = Budget.evaluate_query(b.attack,_attacks([legacy]),F.player([554,384]),q,c)
	var minimum := Vector2i(floor((player.x-radius)/hash.cell_size),floor((player.y-radius)/hash.cell_size))
	var maximum := Vector2i(floor((player.x+radius)/hash.cell_size),floor((player.y+radius)/hash.cell_size))
	var cells := (maximum.x-minimum.x+1)*(maximum.y-minimum.y+1)
	c.observation_work_units = entities.size()+ids.size()+cells
	c.observation_counts = {"entity_count":entities.size(),"hash_candidates":ids.size(),"hash_cells":cells}
	var crowded: Dictionary = Budget.evaluate_query(b.attack,_attacks([legacy]),F.player([554,384]),q,c)
	t.check(near.accepted and crowded.accepted and near.safe_path == crowded.safe_path,"far180 fixture preserves actual acceptance and safe path")
	t.check(crowded.diagnostics.work_units == near.diagnostics.work_units+c.observation_work_units,"far fixture reports collection cost alongside attack acceptance")
	print("T1 BROADPHASE total=%d returned=%d exact=%d accepted=%s work=%d" % [entities.size(),ids.size(),filtered.size(),crowded.accepted,crowded.diagnostics.work_units])

func _checked_source_identity(t) -> void:
	for source in ["district:7","region:enemy:8"," \t "]:
		var actor := F.actor("grabber"); actor.id = source
		var id: String = "run:enemy:prefix:enemy:"+source+":12"
		var p := Catalog.profile(catalog,"grabber")
		var b: Dictionary = Model.begin_query(actor,F.player([190,0]),100,p,Q.for_finite({}),id)
		t.check(b.ok,"checked begin preserves exact Core String source: "+source)
		t.check(not Model.begin(actor,F.player([190,0]),100,p,{},id).ok,"finite begin legacy source rejection unchanged")
		if not b.ok: continue
		t.check(Model.validate_checked(b.attack,p).is_empty(),"checked exact source suffix validates")
		for suffix in ["0","01","+1","-1","1.0","12:3"]:
			var a: Dictionary = b.attack.duplicate(true); a.attack_id = "run:enemy:"+source+":"+suffix
			t.check(not Model.validate_checked(a,p).is_empty(),"checked rejects noncanonical serial: "+suffix)
		var bad: Dictionary = b.attack.duplicate(true); bad.source_id = "other"
		t.check(not Model.validate_checked(bad,p).is_empty(),"checked rejects wrong exact source suffix")

func _attacks(values: Array = []) -> Array[Dictionary]:
	var typed: Array[Dictionary] = []
	for value in values: typed.append(value)
	return typed
