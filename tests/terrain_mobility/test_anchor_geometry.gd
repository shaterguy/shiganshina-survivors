extends RefCounted
const PATH := "res://game/world/mobility_anchor_query.gd"
const F = preload("res://tests/terrain_mobility/anchor_fixture.gd")
const H = preload("res://game/core/streamed_run_world.gd")
const Catalog = preload("res://game/world/world_prop_catalog.gd")
func run(t) -> void:
	var definitions := F.F.definitions()
	for id in ["house_narrow","house_bakery","house_warehouse"]:
		t.check(definitions.props.definitions[id].has("mobility_anchor"),"dev5 allowed roof declares actual height and passage: "+id)
	t.check(FileAccess.file_exists(PATH),"bounded deterministic roof path planner exists")
	if not FileAccess.file_exists(PATH): return
	var planner = load(PATH)
	t.check(planner != null and planner.can_instantiate(),"roof planner compiles")
	if planner == null or not planner.can_instantiate(): return
	var s := F.make()
	t.check(s.prepared.get("ok",false),"roof fixture uses prepared real city geometry")
	if not s.prepared.get("ok",false): return
	var before: Dictionary = s.state.duplicate(true)
	var result: Dictionary = planner.plan(s.state,Vector2.UP,s.helper)
	t.check(result.get("ok",false),"intact forward roof offers a legal short path")
	if not result.get("ok",false): return
	t.check(s.state == before,"planner proposes without mutating authority")
	t.check(result.path.size() == 4 and result.anchor.prop_id == "city:city_v1:0:0:roof_a","path has four bounded phases and exact absolute prop identity")
	t.check(result.anchor.geometry_revision is String and result.anchor.geometry_revision.length() == 64,"stored geometry revision is deterministic physical signature")
	var start: Vector2 = F.point(result.path[0],s.state.world.origin_chunk)
	var landing: Vector2 = F.point(result.landing,s.state.world.origin_chunk)
	t.check(start == Vector2(144,256) and landing.x == start.x and landing.y < start.y and start.distance_to(landing) <= 320,"path preserves current input and never auto-returns")
	t.check(s.helper.walkable(landing,8).get("walkable",false),"actual landing is outside every real solid")
	for point in result.path:
		t.check(point.has_all(["chunk","local","height","geometry_revision"]),"all path coordinates carry absolute chunk and revision")
	var rise: Vector2 = F.point(result.path[1],s.state.world.origin_chunk)
	var over: Vector2 = F.point(result.path[2],s.state.world.origin_chunk)
	t.check(s.helper.sweep(rise,over-rise,8).fraction < 1,"control: normal physical sweep remains blocked by roof building")
	var roof_sweep: Dictionary = s.helper.mobility_sweep(s.state,rise,over-rise,8,result.anchor,float(result.anchor.roof_height))
	t.check(roof_sweep.get("ok",false) and roof_sweep.get("fraction",0.0) == 1.0,"only approved roof at required height may pass")
	var partial: Dictionary = s.helper.mobility_sweep(s.state,rise.lerp(over,0.25),(over-rise)*0.5,8,result.anchor,float(result.anchor.roof_height))
	t.check(partial.get("ok",false) and partial.get("fraction",0.0) == 1.0,"approved over-roof subsegment remains legal")
	var off_line: Dictionary = s.helper.mobility_sweep(s.state,rise+Vector2(20,0),over-rise,8,result.anchor,200.0)
	t.check(not off_line.get("ok",false),"height and building ID cannot authorize a parallel unapproved route")
	var overlong: Dictionary = s.helper.mobility_sweep(s.state,start,landing-start,8,result.anchor,200.0)
	t.check(not overlong.get("ok",false),"rise/land positions outside the approved roof segment cannot skip ground collision")
	var forged_range: Dictionary = result.anchor.duplicate(true)
	forged_range.pass_range = [-700,-500,1400,1000]
	t.check(not s.helper.mobility_sweep(s.state,rise,over-rise,8,forged_range,200.0).get("ok",false),"forged pass range cannot expand roof permission")
	var too_low: Dictionary = s.helper.mobility_sweep(s.state,rise,over-rise,8,result.anchor,float(result.anchor.roof_height)-0.01)
	t.check(too_low.get("ok",false) and too_low.get("fraction",1.0) < 1.0,"roof mask never turns off below declared height")
	t.check(not planner.plan(s.state,Vector2.DOWN,s.helper).get("ok",false) and not planner.plan(s.state,Vector2.ZERO,s.helper).get("ok",false),"rear roof and released input cannot select an anchor")
	_revisions(t,planner,s,result)
	_obstacles(t,planner)
	_stable_candidates(t,planner)
	_coverage_and_rebase(t,planner)
	_metadata_rejection(t,definitions)
func _revisions(t,planner,s: Dictionary,result: Dictionary) -> void:
	var stale: Dictionary = result.anchor.duplicate(true)
	stale.geometry_revision = "f".repeat(64)
	var start := F.point(result.path[1],s.state.world.origin_chunk)
	var end := F.point(result.path[2],s.state.world.origin_chunk)
	t.check(not s.helper.mobility_sweep(s.state,start,end-start,8,stale,200.0).get("ok",false),"forged or stale physical revision is rejected")
	var cold := H.new(s.definitions)
	t.check(cold.prepare(s.state,s.hydration).ok,"cold fixture prepares same hydrated geometry")
	t.check(planner.plan(s.state,Vector2.UP,cold) == result,"cold cache counters do not alter saved anchor or path")
	var destroyed := F.changed(s,[{"slot_id":"roof_a","hp":0,"destroyed":true}])
	t.check(s.helper.prepare(destroyed,s.hydration).ok,"real destruction hydrates atomically")
	t.check(not planner.plan(destroyed,Vector2.UP,s.helper).get("ok",false),"destroyed structure supplies no new roof anchor")
	t.check(not s.helper.mobility_sweep(destroyed,start,end-start,8,result.anchor,200.0).get("ok",false),"destroyed original anchor invalidates saved roof permission")
	var damaged := F.make()
	var changed := F.changed(damaged,[{"slot_id":"roof_a","hp":2,"destroyed":false}])
	t.check(damaged.helper.prepare(changed,damaged.hydration).ok,"damaged fixture hydrates")
	t.check(not planner.plan(changed,Vector2.UP,damaged.helper).get("ok",false),"only intact allowed roofs become fresh anchors")
	var pair := F.make([F.slot("roof_a","house_narrow",[144,224]),F.slot("other","house_narrow",[624,704])])
	var prior: Dictionary = planner.plan(pair.state,Vector2.UP,pair.helper)
	var unrelated := F.changed(pair,[{"slot_id":"other","hp":0,"destroyed":true}])
	t.check(pair.helper.prepare(unrelated,pair.hydration).ok,"unrelated prop changes real global world revision")
	var later: Dictionary = planner.plan(unrelated,Vector2.UP,pair.helper)
	t.check(prior.get("ok",false) and later.get("ok",false) and prior.anchor == later.anchor,"unrelated destruction does not stale identical anchor geometry")
func _obstacles(t,planner) -> void:
	for definition in ["refugee_wagon","cannon_prop","house_ruined","house_warehouse"]:
		var s := F.make([F.slot("roof_a","house_narrow",[144,224]),F.slot("blocker",definition,[144,152])])
		t.check(s.prepared.get("ok",false),"real blocked-landing fixture prepares: "+definition)
		if s.prepared.get("ok",false): t.check(not planner.plan(s.state,Vector2.UP,s.helper).get("ok",false),"other solid cannot be ignored at exit/landing: "+definition)
	var crossing := F.make([F.slot("roof_a","house_narrow",[144,224]),F.slot("wagon","refugee_wagon",[144,208])])
	t.check(crossing.prepared.get("ok",false) and not planner.plan(crossing.state,Vector2.UP,crossing.helper).get("ok",false),"another solid inside over-roof corridor blocks the whole proposal")
	for definition in ["refugee_wagon","cannon_prop","house_ruined","burning_rubble"]:
		var s := F.make([F.slot("not_roof",definition,[144,224])])
		t.check(not planner.plan(s.state,Vector2.UP,s.helper).get("ok",false),"undeclared landmark never supplies roof anchor: "+definition)
func _stable_candidates(t,planner) -> void:
	var offset: float = float(F.F.definitions().props.definitions.house_narrow.mobility_anchor.connection[0])
	# Keep actual connection points symmetric after wall/anchor calibration.
	var s := F.make([F.slot("z","house_narrow",[184-offset,224]),F.slot("a","house_narrow",[104-offset,224])])
	var ordered: Dictionary = planner.candidates(s.state,Vector2.UP,s.helper)
	t.check(ordered.get("ok",false) and ordered.get("anchors",[]).size() == 2,"equal-distance front roofs are discoverable before collision filtering")
	if not ordered.get("ok",false) or ordered.get("anchors",[]).size() != 2: return
	t.check(ordered.anchors[0].slot_id == "a" and ordered.anchors[1].slot_id == "z","distance and direction ties resolve by stable absolute prop ID")
	s.definitions.templates.templates.reverse()
	var another := H.new(s.definitions)
	t.check(another.prepare(s.state,s.hydration).ok and planner.candidates(s.state,Vector2.UP,another) == ordered,"candidate order does not depend on template insertion order")
func _coverage_and_rebase(t,planner) -> void:
	var s := F.make([], ["9007199254740993","-9007199254740994"])
	var result: Dictionary = planner.plan(s.state,Vector2.UP,s.helper)
	t.check(result.get("ok",false) and result.anchor.chunk == s.state.world.origin_chunk,"anchor preserves absolute integers beyond JSON float precision")
	var cold := H.new(s.definitions)
	t.check(not planner.plan(s.state,Vector2.UP,cold).get("ok",false),"unprepared geometry cannot produce a plan")
	var normal := F.make()
	var prepared: Dictionary = planner.plan(normal.state,Vector2.UP,normal.helper)
	if not prepared.get("ok",false): return
	var shifted: Dictionary = normal.state.duplicate(true)
	shifted.world.origin_chunk = ["1","0"]
	shifted.world.origin_revision = 1
	shifted.player.position[0] -= 768.0
	var hydration := F.F.hydration(H.requirements(shifted))
	t.check(normal.helper.prepare(shifted,hydration).ok,"same absolute player prepares under another origin")
	var after: Dictionary = planner.plan(shifted,Vector2.UP,normal.helper)
	t.check(after == prepared,"absolute path and anchor do not shift twice on origin rebase")
	var uncovered := F.make()
	uncovered.helper._world._chunks.erase("0,0")
	uncovered.helper._world._coverage_revision += 1
	t.check(not planner.plan(uncovered.state,Vector2.UP,uncovered.helper).get("ok",false),"missing covered chunk refuses without partial output")
func _metadata_rejection(t,definitions: Dictionary) -> void:
	var malformed: Dictionary = definitions.props.duplicate(true)
	malformed.definitions.house_narrow.mobility_anchor = {"kind":"roof","connection":[0,-26],"roof_height":-1,"pass_range":[-70,-52,140,52]}
	t.check(not Catalog.validate(malformed,definitions.asset_manifest).is_empty(),"negative roof height is invalid definition data")
	malformed.definitions.house_narrow.mobility_anchor.roof_height = 144
	malformed.definitions.house_narrow.mobility_anchor.pass_range = [-700,-52,1400,52]
	t.check(not Catalog.validate(malformed,definitions.asset_manifest).is_empty(),"pass range cannot grant permission beyond the declared building footprint")
