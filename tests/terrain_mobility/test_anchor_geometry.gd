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
	var s := F.corridor(t)
	t.check(s.prepared.get("ok",false),"roof fixture uses prepared real city geometry")
	if not s.prepared.get("ok",false): return
	var before: Dictionary = s.state.duplicate(true)
	var result: Dictionary = planner.plan(s.state,Vector2.UP,s.helper)
	t.check(result.get("ok",false),"intact opposite-side anchors offer a legal forward corridor")
	if not result.get("ok",false): return
	t.check(s.state == before,"planner proposes without mutating authority")
	t.check(result.path.size() == 2 and result.anchors.size() == 2 and result.anchors[0].slot_id == "left" and result.anchors[1].slot_id == "right","path has two grounded endpoints and exact paired prop identities")
	t.check(result.anchors.all(func(a): return a.geometry_revision is String and a.geometry_revision.length() == 64),"stored geometry revision is deterministic physical signature")
	var start: Vector2 = F.point(result.path[0],s.state.world.origin_chunk)
	var landing: Vector2 = F.point(result.landing,s.state.world.origin_chunk)
	t.check(start == Vector2(180,256) and landing.x == start.x and landing.y < start.y and start.distance_to(landing) <= 320,"path preserves current input and never auto-returns")
	t.check(s.helper.walkable(landing,8).get("walkable",false),"actual landing is outside every real solid")
	for point in result.path:
		t.check(point.has_all(["chunk","local","height","geometry_revision"]),"all path coordinates carry absolute chunk and revision")
	var normal: Dictionary = s.helper.sweep(start,landing-start,8)
	t.check(normal.get("ok",false) and normal.get("fraction",0.0) == 1.0,"paired corridor uses ordinary collision across its entire straight path")
	t.check(s.helper.mobility_pair_check(s.state,result.anchors).get("ok",false),"both physical anchor records match real current props")
	for point in result.path: t.check(point.height == 0.0,"new route never grants height or roof collision bypass")
	t.check(not planner.plan(s.state,Vector2.DOWN,s.helper).get("ok",false) and not planner.plan(s.state,Vector2.ZERO,s.helper).get("ok",false),"rear roof and released input cannot select an anchor")
	_legacy_admission_geometry(t)
	_revisions(t,planner,s,result)
	_obstacles(t,planner)
	_stable_candidates(t,planner)
	_coverage_and_rebase(t,planner)
	_metadata_rejection(t,definitions)
func _legacy_admission_geometry(t) -> void:
	var s := F.legacy()
	t.check(s.prepared.get("ok",false),"captured v1 over checkpoint prepares admission-only geometry")
	if not s.prepared.get("ok",false): return
	var saved: Dictionary = s.state.player_mobility
	var start := F.point(saved.path[0],s.state.world.origin_chunk)
	var landing := F.point(saved.landing,s.state.world.origin_chunk)
	var rise: Vector2 = F.point(saved.path[1],s.state.world.origin_chunk)
	var over: Vector2 = F.point(saved.path[2],s.state.world.origin_chunk)
	t.check(s.helper.sweep(rise,over-rise,8).fraction < 1,"control: normal physical sweep remains blocked by roof building")
	var roof_sweep: Dictionary = s.helper.mobility_sweep(s.state,rise,over-rise,8,saved.anchor,float(saved.anchor.roof_height))
	t.check(roof_sweep.get("ok",false) and roof_sweep.get("fraction",0.0) == 1.0,"only approved roof at required height may pass")
	var partial: Dictionary = s.helper.mobility_sweep(s.state,rise.lerp(over,0.25),(over-rise)*0.5,8,saved.anchor,float(saved.anchor.roof_height))
	t.check(partial.get("ok",false) and partial.get("fraction",0.0) == 1.0,"approved over-roof subsegment remains legal")
	var off_line: Dictionary = s.helper.mobility_sweep(s.state,rise+Vector2(20,0),over-rise,8,saved.anchor,200.0)
	t.check(not off_line.get("ok",false),"height and building ID cannot authorize a parallel unapproved route")
	var overlong: Dictionary = s.helper.mobility_sweep(s.state,start,landing-start,8,saved.anchor,200.0)
	t.check(not overlong.get("ok",false),"rise/land positions outside the approved roof segment cannot skip ground collision")
	var forged_range: Dictionary = saved.anchor.duplicate(true)
	forged_range.pass_range = [-700,-500,1400,1000]
	t.check(not s.helper.mobility_sweep(s.state,rise,over-rise,8,forged_range,200.0).get("ok",false),"forged pass range cannot expand roof permission")
	var too_low: Dictionary = s.helper.mobility_sweep(s.state,rise,over-rise,8,saved.anchor,float(saved.anchor.roof_height)-0.01)
	t.check(too_low.get("ok",false) and too_low.get("fraction",1.0) < 1.0,"roof mask never turns off below declared height")
func _revisions(t,planner,s: Dictionary,result: Dictionary) -> void:
	var stale: Array = result.anchors.duplicate(true)
	stale[0].geometry_revision = "f".repeat(64)
	t.check(not s.helper.mobility_pair_check(s.state,stale).get("ok",false),"forged or stale physical revision is rejected")
	var cold := H.new(s.definitions)
	t.check(cold.prepare(s.state,s.hydration).ok,"cold fixture prepares same hydrated geometry")
	t.check(planner.plan(s.state,Vector2.UP,cold) == result,"cold cache counters do not alter saved anchors or path")
	for hp in [0,2]:
		var changed := F.changed(s,[{"slot_id":"left","hp":hp,"destroyed":hp == 0}])
		t.check(s.helper.prepare(changed,s.hydration).ok,"real damaged/destroyed anchor hydrates atomically")
		t.check(not planner.plan(changed,Vector2.UP,s.helper).get("ok",false),"only two intact anchors can create a fresh corridor")
		t.check(not s.helper.mobility_pair_check(changed,result.anchors).get("ok",false),"damaged original anchor invalidates saved pair")
	var pair := F.corridor(t,[F.slot("left","house_narrow",[144,224]),F.slot("right","house_narrow",[260,224]),F.slot("other","house_narrow",[624,704])])
	var prior: Dictionary = planner.plan(pair.state,Vector2.UP,pair.helper)
	var unrelated := F.changed(pair,[{"slot_id":"other","hp":0,"destroyed":true}])
	t.check(pair.helper.prepare(unrelated,pair.hydration).ok,"unrelated prop changes real global world revision")
	var later: Dictionary = planner.plan(unrelated,Vector2.UP,pair.helper)
	t.check(prior.get("ok",false) and later.get("ok",false) and prior.anchors == later.anchors,"unrelated destruction does not stale identical paired geometry")
func _obstacles(t,planner) -> void:
	for definition in ["refugee_wagon","cannon_prop","house_ruined","house_warehouse"]:
		var s := F.corridor(t,[F.slot("left","house_narrow",[144,224]),F.slot("right","house_narrow",[260,224]),F.slot("blocker",definition,[180,200])])
		t.check(s.prepared.get("ok",false),"real blocked-corridor fixture prepares: "+definition)
		t.check(not planner.plan(s.state,Vector2.UP,s.helper).get("ok",false),"solid before both hooks blocks the whole proposal: "+definition)
	var crossing := F.corridor(t,[F.slot("left","house_narrow",[144,224]),F.slot("right","house_narrow",[260,224]),F.slot("wagon","refugee_wagon",[180,208])])
	t.check(not planner.plan(crossing.state,Vector2.UP,crossing.helper).get("ok",false),"another solid inside the proposed corridor cannot be ignored")
	for definition in ["refugee_wagon","cannon_prop","house_ruined","burning_rubble"]:
		var s := F.corridor(t,[F.slot("left","house_narrow",[144,224]),F.slot("not_anchor",definition,[200,224])])
		t.check(not planner.plan(s.state,Vector2.UP,s.helper).get("ok",false),"undeclared landmark cannot supply the second anchor: "+definition)
func _stable_candidates(t,planner) -> void:
	var offset: float = float(F.F.definitions().props.definitions.house_narrow.mobility_anchor.connection[0])
	# Keep actual connection points symmetric after wall/anchor calibration.
	var s := F.corridor(t,[F.slot("z","house_narrow",[220-offset,224]),F.slot("a","house_narrow",[140-offset,224])])
	var ordered: Dictionary = planner.candidates(s.state,Vector2.UP,s.helper)
	t.check(ordered.get("ok",false) and ordered.get("anchors",[]).size() == 2,"equal-distance front roofs are discoverable before collision filtering")
	if not ordered.get("ok",false) or ordered.get("anchors",[]).size() != 2: return
	t.check(ordered.anchors[0].slot_id == "a" and ordered.anchors[1].slot_id == "z","distance and direction ties resolve by stable absolute prop ID")
	s.definitions.templates.templates.reverse()
	var another := H.new(s.definitions)
	t.check(another.prepare(s.state,s.hydration).ok and planner.candidates(s.state,Vector2.UP,another) == ordered,"candidate order does not depend on template insertion order")
func _coverage_and_rebase(t,planner) -> void:
	var s := F.corridor(t,[], ["9007199254740993","-9007199254740994"])
	var result: Dictionary = planner.plan(s.state,Vector2.UP,s.helper)
	t.check(result.get("ok",false) and result.anchors.all(func(a): return a.chunk == s.state.world.origin_chunk),"anchor preserves absolute integers beyond JSON float precision")
	var cold := H.new(s.definitions)
	t.check(not planner.plan(s.state,Vector2.UP,cold).get("ok",false),"unprepared geometry cannot produce a plan")
	var normal := F.corridor(t)
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
	var uncovered := F.corridor(t)
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
