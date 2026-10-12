extends RefCounted
const F = preload("res://tests/core_world/new_streamed_helper_fixture.gd")
const Helper = preload("res://game/core/streamed_run_world.gd")
const Generator = preload("res://game/world/city_generator.gd")
const Navigation = preload("res://game/world/city_navigation.gd")
const CountingStream = preload("res://tests/navigation_view/counting_stream.gd")
const PATH := "res://game/world/streamed_navigation_view.gd"
const A := Vector2(496,194)
const B := Vector2(1152,384)
func run(t) -> void:
	t.check(FileAccess.file_exists(PATH),"NEW read-only navigation adapter exists")
	if not FileAccess.file_exists(PATH): return
	var View = load(PATH)
	t.check(View != null and View.can_instantiate(),"NEW navigation adapter loads")
	if View == null or not View.can_instantiate(): return
	_equivalence_and_no_copies(t,View)
	_damage_and_isolation(t,View)
	_coverage_and_rebase(t,View)
	_restore_and_failed_candidate(t,View)
	_large_address_mapping(t,View)
func _fixture(large: bool = false) -> Dictionary:
	var helper = Helper.new(F.definitions())
	var state: Dictionary = F.state(helper)
	if large: state.telegraphs = [{"position":[384.0,384.0],"radius":2600.0}]
	var needed: Dictionary = helper.requirements(state)
	var hydration: Dictionary = F.hydration(needed)
	var world = CountingStream.new(helper.get("_generator"),int(state.seed))
	var prepared: Dictionary = world.prepare(needed.chunks,[],hydration,state.world.origin_chunk)
	return {"helper":helper,"state":state,"hydration":hydration,"needed":needed,"world":world,"prepared":prepared}
func _equivalence_and_no_copies(t,View) -> void:
	var f := _fixture(true)
	t.check(f.prepared.ok,"real 49-chunk fixture prepares")
	var view = View.new(f.world)
	var direct = Navigation.new(f.world)
	var nav = Navigation.new(view)
	var expected: Dictionary = direct.direction(A,B,8,0)
	t.check(expected.ok and f.world.sweep(A,B-A,8).fraction < 1,"route is genuinely obstructed and crosses chunks")
	t.check(nav.direction(A,B,8,0) == expected,"adapter returns exact recovered cold route")
	var before_local: int = f.world.localized_calls
	var before_render: int = f.world.render_calls
	var before_sweep: int = f.world.sweep_calls
	var before_walkable: int = f.world.walkable_calls
	for tick in 120:
		t.check(nav.direction(A,B,8,tick) == expected,"warm advancing-tick route exact: "+str(tick))
	t.check(f.world.localized_calls == before_local and f.world.render_calls == before_render,"120 warm routes create no localized chunk or full render copy")
	t.check(f.world.sweep_calls > before_sweep and f.world.walkable_calls > before_walkable,"warm routes delegate actual collision and walkability")
	var snapshot: Dictionary = view.render_view()
	t.check(snapshot.is_read_only() and snapshot.chunks.is_read_only(),"navigation snapshot envelope and chunk array are immutable")
	t.check(snapshot.chunks.size() == 49,"prepared coverage includes every chunk")
	for chunk in snapshot.chunks:
		t.check(chunk.is_read_only() and chunk.props.is_read_only(),"chunk and props array immutable: "+chunk.chunk_id)
		for prop in chunk.props:
			t.check(prop.is_read_only() and prop.size() == 2,"geometry record is minimal immutable collision data")
	var keys: Array = view.chunk_keys()
	t.check(keys.is_read_only(),"cached chunk key array is immutable")
	for pair in [[A,B,33.0],[Vector2(9000,9000),B,8.0],[Vector2(384,384),Vector2(640,384),8.0]]:
		t.check(nav.direction(pair[0],pair[1],pair[2],121) == direct.direction(pair[0],pair[1],pair[2],121),"unsupported/blocked/visible route semantics unchanged")
func _damage_and_isolation(t,View) -> void:
	var f := _fixture()
	var other := _fixture()
	var view = View.new(f.world)
	var other_view = View.new(other.world)
	var nav = Navigation.new(view)
	var old: Dictionary = view.localized_chunk("0,0")
	var other_old: Dictionary = other_view.localized_chunk("0,0")
	var prior: Dictionary = nav.direction(A,B,8,0)
	var changes := []
	for prop in f.world.localized_chunk("0,0").props:
		if prop.destructible: changes.append({"slot_id":prop.slot_id,"hp":0,"destroyed":true})
	t.check(not changes.is_empty() and f.world.apply_props([{"chunk":["0","0"],"props":changes}],1).ok,"real prop destruction is applied")
	var changed: Dictionary = view.localized_chunk("0,0")
	t.check(changed.geometry_revision == old.geometry_revision+1 and changed != old,"damage and geometry revision replace cached geometry")
	t.check(old.geometry_revision == 0 and old == other_old,"old snapshot and separate same-revision run remain unchanged")
	t.check(other_view.localized_chunk("0,0") == other_old,"live A damage cannot poison unrelated B cache")
	t.check(nav.direction(A,B,8,1) == Navigation.new(f.world).direction(A,B,8,1),"damage route equals fresh exact navigation")
	t.check(prior == Navigation.new(other_view).direction(A,B,8,1),"unmodified run route stays exact")
	var count: int = f.world.localized_calls
	var invalid: Dictionary = f.world.apply_props([{"chunk":["0","0"],"props":[{"slot_id":"missing","hp":0,"destroyed":true}]}],2)
	t.check(not invalid.ok and view.localized_chunk("0,0") == changed and f.world.localized_calls == count,"failed real geometry candidate does not invalidate published cache")
	var same_geometry: Dictionary = f.world.apply_props([{"chunk":["0","0"],"props":changes}],2)
	t.check(same_geometry.ok and view.localized_chunk("0,0").geometry_revision == 2,"successful retry with new geometry revision refreshes even equal footprints")
func _coverage_and_rebase(t,View) -> void:
	var f := _fixture()
	var view = View.new(f.world)
	var nav = Navigation.new(view)
	var initial: Dictionary = view.render_view()
	var original_route: Dictionary = nav.direction(A,B,8,0)
	var large := _fixture(true)
	t.check(f.world.prepare(large.needed.chunks,[],large.hydration,["0","0"]).ok,"real coverage expands")
	t.check(view.render_view().chunks.size() == 49 and initial.chunks.size() == 9,"coverage expansion replaces immutable snapshot")
	t.check(nav.direction(A,B,8,1) == original_route,"coverage expansion preserves route")
	var rebased_chunks: Array = []
	for y in range(-1,2):
		for x in range(0,3): rebased_chunks.append([str(x),str(y)])
	var hydration := F.hydration({"chunks":rebased_chunks})
	t.check(f.world.prepare(rebased_chunks,[],hydration,["1","0"]).ok,"real origin and coverage rebase prepares")
	var local: Dictionary = view.localized_chunk("0,0")
	t.check(local.local_origin == Vector2(-768,0) and view.render_view().chunks.size() == 9,"origin revision invalidates local geometry at same absolute chunk")
	t.check(view.chunk_at(A).chunk_id == "1,0" and nav.direction(A,B,8,2) == Navigation.new(f.world).direction(A,B,8,2),"same local cell after rebase cannot reuse prior absolute geometry")
	var shifted_a := A-Vector2(768,0)
	var shifted_b := B-Vector2(768,0)
	var rebased: Dictionary = nav.direction(shifted_a,shifted_b,8,2)
	t.check(rebased == Navigation.new(f.world).direction(shifted_a,shifted_b,8,2),"warm rebased grid equals cold exact route")
	t.check(rebased.ok and rebased.length == original_route.length,"same physical route keeps length after rebase")
	for i in rebased.waypoints.size():
		t.check(rebased.waypoints[i] == original_route.waypoints[i]-Vector2(768,0),"rebase shifts route once")
	t.check(view.localized_chunk("-1,0").is_empty() and view.chunk_at(Vector2(-900,384)).is_empty(),"retired coverage cannot leak cached chunks")
func _restore_and_failed_candidate(t,_View) -> void:
	var f := _fixture(true)
	t.check(f.helper.prepare(f.state,f.hydration).ok,"live A helper prepares")
	t.check(f.helper.get("_navigation").get("_world").get_script().resource_path == PATH,"helper publishes exact navigation with NEW cached view")
	var route: Dictionary = f.helper.direction(A,B,8,40)
	var live_world_id: int = f.helper.get("_world").get_instance_id()
	var live_navigation_id: int = f.helper.get("_navigation").get_instance_id()
	var candidate: Dictionary = JSON.parse_string(JSON.stringify(f.state))
	candidate.world.world_revision = 1
	candidate.world.dirty_chunks = [{"chunk":["0","0"],"props":[{"slot_id":"unknown","hp":0,"destroyed":true}]}]
	t.check(not f.helper.prepare(candidate,f.hydration).ok,"candidate B fails after stream hydration")
	t.check(f.helper.get("_world").get_instance_id() == live_world_id and f.helper.get("_navigation").get_instance_id() == live_navigation_id,"failed B cannot publish its stream or navigation")
	t.check(f.helper.direction(A,B,8,40) == route,"failed B leaves warmed live A route exact")
	var restored_state: Dictionary = JSON.parse_string(JSON.stringify(f.state))
	var restored_hydration: Dictionary = JSON.parse_string(JSON.stringify(f.hydration))
	var restored_before: Dictionary = restored_state.duplicate(true)
	var hydration_before: Dictionary = restored_hydration.duplicate(true)
	var live_before: Dictionary = f.state.duplicate(true)
	var restored = Helper.new(F.definitions())
	t.check(restored.prepare(restored_state,restored_hydration).ok,"JSON-restored snapshot cold helper prepares")
	t.check(restored.get("_navigation").get("_world").get_script().resource_path == PATH,"cold restored helper owns cached view")
	for tick in range(40,80):
		t.check(restored.direction(A,B,8,tick) == f.helper.direction(A,B,8,tick),"warm/cold restored route exact: "+str(tick))
	t.check(restored.get("_navigation").get_instance_id() != live_navigation_id,"restored run owns independent navigation cache")
	t.check(restored_state == restored_before and restored_hydration == hydration_before and f.state == live_before,"navigation never mutates authority or hydration snapshots")

func _large_address_mapping(t,View) -> void:
	var helper = Helper.new(F.definitions())
	var state: Dictionary = F.state(helper)
	state.world.origin_chunk = ["9007199254740993","-9007199254740993"]
	var needed: Dictionary = helper.requirements(state)
	t.check(helper.prepare(state,F.hydration(needed)).ok,"large int64 address helper prepares")
	var world = helper.get("_world")
	var view = View.new(world)
	for key in world.chunk_keys():
		var exact: Dictionary = world.localized_chunk(key)
		var cached: Dictionary = view.chunk_at(exact.local_origin+Vector2(384,384))
		t.check(cached.chunk_id == exact.chunk_id and cached.local_origin == exact.local_origin,"mapping preserves large canonical address: "+key)
	var snapshot: Dictionary = view.render_view()
	var coverage: int = view.diagnostics().coverage_revision
	var failed: Dictionary = world.prepare(needed.chunks,[],{},state.world.origin_chunk)
	t.check(not failed.ok and view.render_view() == snapshot and view.diagnostics().coverage_revision == coverage,"failed coverage prepare cannot replace a live navigation snapshot")
