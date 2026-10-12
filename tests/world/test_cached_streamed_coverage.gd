extends RefCounted
const F = preload("res://tests/core_world/new_streamed_helper_fixture.gd")
const H = preload("res://game/core/streamed_run_world.gd")
const Exact = preload("res://game/world/streamed_world.gd")
const Generator = preload("res://game/world/city_generator.gd")
const A = preload("res://game/world/world_address.gd")
const PATH := "res://game/world/cached_streamed_world.gd"
func run(t) -> void:
	t.check(FileAccess.file_exists(PATH),"NEW bounded coverage cache exists")
	if not FileAccess.file_exists(PATH): return
	var Cached = load(PATH)
	t.check(Cached != null and Cached.can_instantiate(),"NEW coverage cache compiles")
	if Cached == null or not Cached.can_instantiate(): return
	for origin in [["0","0"],["9007199254740993","-9007199254740994"]]: _compare(t,Cached,origin)
	var helper := H.new(F.definitions())
	var state := F.state(helper)
	var hydration := F.hydration(H.requirements(state))
	t.check(helper.prepare(state,hydration).ok,"actual helper prepares coverage cache integration control")
	t.check(helper._world.has_method("coverage_cache_stats"),"actual helper publishes the NEW coverage cache subclass")
	if not helper._world.has_method("coverage_cache_stats"): return
	var before: Dictionary = helper._world.coverage_cache_stats()
	var fresh = helper.fresh()
	t.check(fresh.prepare(state,hydration).ok and fresh._world.has_method("coverage_cache_stats"),"fresh restore-style helper owns an independent coverage cache")
	fresh.walkable(Vector2(400,384),8)
	t.check(helper._world.coverage_cache_stats() == before,"candidate B cannot mutate A coverage cache")
func _compare(t,Cached,origin: Array) -> void:
	var definitions := F.definitions()
	var generator := Generator.new(definitions.templates,definitions.props)
	var exact := Exact.new(generator,42)
	var cached = Cached.new(generator,42)
	var missing := Rect2(384,384,0,0)
	t.check(not cached.covered(missing) and cached.coverage_cache_stats().cells == 0,"missing coverage is never cached as a success")
	var chunks := _chunks(origin)
	var hydration := F.hydration({"chunks":chunks})
	t.check(exact.prepare(chunks,[],hydration,origin).ok and cached.prepare(chunks,[],hydration,origin).ok,"exact and cached worlds prepare identical actual chunks")
	var rectangles := []
	for x in [-769.0,-768.0,-767.9999,-0.0001,0.0,0.0001,767.9999,768.0,768.0001,1536.0]:
		for width in [0.0,0.0001,1.0,32.0,768.0]:
			for y in [-768.0,0.0,767.9999]: rectangles.append(Rect2(x,y,width,width))
	rectangles.append_array([Rect2(-800,100,32,32),Rect2(0,0,7000,1),Rect2(100,100,-10,10),Rect2(49153,0,0,0),Rect2(-49153,0,0,0),Rect2(1e20,0,0,0),Rect2(NAN,0,0,0),Rect2(INF,0,0,0),Rect2(0,0,INF,1)])
	for rectangle in rectangles:
		t.check(cached.covered(rectangle) == exact.covered(rectangle),"covered rectangle matches exact boundary/epsilon result: "+str(rectangle))
	var before: Dictionary = cached.coverage_cache_stats()
	for i in 100: cached.covered(Rect2(380,380,8,8))
	var after: Dictionary = cached.coverage_cache_stats()
	t.check(after.cell_checks == before.cell_checks and after.hits > before.hits and after.cells <= chunks.size(),"warm successful coverage reuses only bounded resident cells")
	var absent := Rect2(2000,384,0,0)
	before = cached.coverage_cache_stats()
	cached.covered(absent); cached.covered(absent)
	after = cached.coverage_cache_stats()
	t.check(after.cell_checks == before.cell_checks+2 and after.cells == before.cells,"failed cells are checked again and never retained")
	var failed: Dictionary = cached.prepare(chunks,[],{},origin)
	t.check(not failed.ok and cached.covered(missing) == exact.covered(missing),"failed prepare preserves previously valid coverage")
	var next_origin := [str(A.add(origin[0].to_int(),1).value),origin[1]]
	var rebased := _chunks(next_origin)
	var next_hydration := F.hydration({"chunks":rebased})
	t.check(exact.prepare(rebased,[],next_hydration,next_origin).ok and cached.prepare(rebased,[],next_hydration,next_origin).ok,"actual rebase and residency publication succeeds")
	for rectangle in rectangles: t.check(cached.covered(rectangle) == exact.covered(rectangle),"rebased rectangle matches exact current coverage")
	t.check(cached.coverage_cache_stats().cells <= rebased.size(),"rebase discards previous local-cell cache")
	var prop := {}
	for item in cached.localized_chunk(A.key(next_origin)).props:
		if item.destructible: prop = item; break
	t.check(not prop.is_empty(),"delta fixture has a real destructible prop")
	if prop.is_empty(): return
	var point: Vector2 = prop.ground_footprint.get_center()
	t.check(cached.walkable(point,8) == exact.walkable(point,8),"inherited collision agrees before delta")
	var changes := [{"chunk":next_origin,"props":[{"slot_id":prop.slot_id,"hp":0,"destroyed":true}]}]
	t.check(cached.apply_props(changes,1).ok and exact.apply_props(changes,1).ok,"actual geometry delta publishes without a coverage-rule change")
	t.check(cached.walkable(point,8) == exact.walkable(point,8) and cached.sweep(point-Vector2(100,0),Vector2(200,0),8) == exact.sweep(point-Vector2(100,0),Vector2(200,0),8),"inherited collision and sweep observe destruction with warm coverage cache")
	t.check(cached.coverage_cache_stats().cells <= cached.chunk_keys().size(),"geometry mutation cannot grow cache beyond resident chunks")
func _chunks(origin: Array) -> Array:
	var chunks := []
	for y in range(-1,2):
		for x in range(-1,2): chunks.append([str(A.add(origin[0].to_int(),x).value),str(A.add(origin[1].to_int(),y).value)])
	return chunks
