extends RefCounted
const F = preload("res://tests/world/fixtures/city_fixture.gd")
const Exact = preload("res://game/world/streamed_world.gd")
const Cached = preload("res://game/world/cached_streamed_world.gd")
const Address = preload("res://game/world/world_address.gd")
# This derived control uses the preserved public query algorithm and owned
# snapshots; all inherited movement/coverage/slab calculations are identical.
class Reference:
	extends "res://game/world/cached_streamed_world.gd"
	func _collision_query_props(aabb: Rect2) -> Array: return query_props(aabb)
class DerivedExact:
	extends "res://game/world/streamed_world.gd"
class DerivedCached:
	extends "res://game/world/cached_streamed_world.gd"
func _world(script, origin: Array = ["0","0"]):
	var w = script.new(F.generator(),42)
	var chunks := _chunks(origin)
	w.prepare(chunks,[],F.hydration(chunks),origin)
	return w
func _chunks(origin: Array) -> Array:
	var chunks := []
	for y in range(-1,2):
		for x in range(-1,2): chunks.append([str(Address.add(origin[0].to_int(),x).value),str(Address.add(origin[1].to_int(),y).value)])
	return chunks
func run(t) -> void:
	for script in [Exact,Cached]:
		var w = _world(script)
		var rect := Rect2(120,190,120,100)
		w._collision_query_props(rect)
		t.check(w.get("_collision_bucket_cache") is Dictionary and not w.get("_collision_bucket_cache").is_empty(),"repeated exact collision queries retain their sorted bucket candidates")
		if not w.get("_collision_bucket_cache") is Dictionary: return
		var keys: Array = w._collision_bucket_cache.keys()
		var first: Array = w._collision_bucket_cache[keys[0]]
		var initial_count: int = w.diagnostics().query_count
		for i in 20:
			var moved := Rect2(rect.position+Vector2(i*0.125,0),rect.size-Vector2(i*0.125,0))
			t.check(w._collision_query_props(moved) == w.query_props(moved),"warm candidates still filter every exact, shifted query rectangle")
		t.check(is_same(first,w._collision_bucket_cache[keys[0]]) and w._collision_bucket_cache.size() == 1,"one exact bucket span reuses the same candidate array without sorting again")
		t.check(w.diagnostics().query_count == initial_count+40,"candidate reuse preserves the per-query diagnostic counter")
		_boundary_queries(t,w)
		_lifecycle(t,script)
		_bounded_cache(t,script)
		_coverage_retirement(t,script)
	for script in [DerivedExact,DerivedCached]:
		var w = _world(script)
		w.walkable(Vector2(384,384),8)
		w.sweep(Vector2(16,200),Vector2(200,0),8)
		t.check(w._collision_bucket_cache.is_empty(),"derived callback implementations retain the uncached owned public path")
	_invalid_queries(t)
func _boundary_queries(t,w) -> void:
	for x in [-128.00002,-128.0,-127.99999,-0.00001,0.0,0.00001,127.99999,128.0,128.00002,255.99998,256.0,767.99994,768.0]:
		for size in [0.0,0.00001,8.0,32.0,128.0]:
			for y in [127.99999,128.0,190.0]:
				var rect := Rect2(x,y,size,size)
				t.check(w._collision_query_props(rect) == w.query_props(rect),"cached candidates preserve inclusive footprint/bucket floating boundaries "+str(rect))
	var public: Array = w.query_props(Rect2(0,0,768,768))
	if not public.is_empty():
		var id: String = public[0].prop_id
		var hp = w._props[id].hp
		public[0].hp = -99
		t.check(w._props[id].hp == hp,"public query results remain caller-owned after cache warming")
func _lifecycle(t,script) -> void:
	for origin in [["0","0"],["9007199254740993","-9007199254740994"]]:
		var w = _world(script,origin)
		var reference = _world(Reference,origin)
		var prop := {}
		for item in w.localized_chunk(Address.key(origin)).props:
			if item.destructible: prop = item; break
		t.check(not prop.is_empty(),"actual destruction fixture has a destructible prop")
		if prop.is_empty(): return
		var point: Vector2 = prop.ground_footprint.get_center()
		_compare_motion(t,w,reference,point)
		var old_cache: Dictionary = w._collision_bucket_cache.duplicate()
		var failed: Dictionary = w.prepare(_chunks(origin),[],{},origin)
		reference.prepare(_chunks(origin),[],{},origin)
		t.check(not failed.ok and w._collision_bucket_cache == old_cache,"failed prepare never invalidates or publishes collision geometry")
		_compare_motion(t,w,reference,point)
		var changes := [{"chunk":origin,"props":[{"slot_id":prop.slot_id,"hp":0,"destroyed":true}]}]
		t.check(w.apply_props(changes,1).ok and reference.apply_props(changes,1).ok,"actual terrain revision is published")
		t.check(w._collision_bucket_cache.is_empty(),"published terrain rebuild immediately discards all borrowed candidates")
		_compare_motion(t,w,reference,point)
		old_cache = w._collision_bucket_cache.duplicate()
		t.check(not w.apply_props(changes,1).ok and not reference.apply_props(changes,1).ok and w._collision_bucket_cache == old_cache,"stale terrain revision refusal leaves current candidates unchanged")
		var next_origin := [str(Address.add(origin[0].to_int(),1).value),origin[1]]
		var chunks := _chunks(next_origin)
		t.check(w.prepare(chunks,[],F.hydration(chunks),next_origin).ok and reference.prepare(chunks,[],F.hydration(chunks),next_origin).ok,"actual origin/coverage publication succeeds")
		t.check(w._collision_bucket_cache.is_empty(),"rebase and residency changes discard old localized candidate records")
		_compare_motion(t,w,reference,point-Vector2(768,0))
		var fresh = _world(script,next_origin)
		t.check(fresh._collision_bucket_cache.is_empty(),"restore-style new world starts without another world's derived cache")
		var before: Dictionary = w._collision_bucket_cache.duplicate(true)
		fresh.sweep(Vector2(384,384),Vector2(80,40),8)
		t.check(w._collision_bucket_cache == before,"independent restored world cannot mutate the first world's cached records")
func _compare_motion(t,w,reference,point: Vector2) -> void:
	for radius in [0.0,7.999999,8.0,8.000001,16.0,31.999999,32.0]:
		for delta in [Vector2.ZERO,Vector2(256,0),Vector2(0,256),Vector2(255.99998,-256.00003)]:
			var start: Vector2 = point-delta*0.5
			t.check(w.sweep(start,delta,radius) == reference.sweep(start,delta,radius),"all exact sweep fields survive radius/axis/diagonal/lifecycle changes")
			t.check(w.move(start,delta,radius) == reference.move(start,delta,radius),"axis-separated movement is unchanged")
			for mask in [0,1,3,31]:
				t.check(w.cover_sweep(start,delta,radius,mask) == reference.cover_sweep(start,delta,radius,mask),"cover masks and equal-hit ID ordering are unchanged")
		t.check(w.diagnostics().last_error == reference.diagnostics().last_error,"coverage diagnostics match the unchanged reference")
func _invalid_queries(t) -> void:
	var w = _world(Cached)
	var reference = _world(Reference)
	for query in [[Vector2(NAN,0),Vector2.ZERO,8.0],[Vector2(INF,0),Vector2.ZERO,8.0],[Vector2.ZERO,Vector2(INF,0),8.0],[Vector2.ZERO,Vector2.ZERO,-1.0],[Vector2.ZERO,Vector2.ZERO,NAN],[Vector2.ZERO,Vector2.ZERO,32.00001],[Vector2(49153,0),Vector2.ZERO,8.0],[Vector2.ZERO,Vector2(49153,0),8.0],[Vector2(4000,4000),Vector2.ONE,8.0]]:
		var got: Dictionary = w.sweep(query[0],query[1],query[2])
		var expected: Dictionary = reference.sweep(query[0],query[1],query[2])
		t.check(got.ok == expected.ok and got.error_code == expected.error_code and got.fraction == expected.fraction and got.hit_prop_id == expected.hit_prop_id,"invalid and missing-coverage results still take the authoritative guard path")
		t.check(w.diagnostics() == reference.diagnostics(),"invalid queries preserve exact error ordering and query counters")
		t.check(w._collision_bucket_cache.is_empty(),"invalid or uncovered sweeps never populate broadphase candidates")
func _bounded_cache(t,script) -> void:
	var w = _world(script)
	for i in 600:
		var rect := Rect2((i%30-15)*128,(i/30-10)*128,0,0)
		t.check(w._collision_query_props(rect) == w.query_props(rect),"cache-cap overflow retains the exact authoritative query")
	t.check(w._collision_bucket_cache.size() == 512,"retained candidate spans are strictly bounded")
	var before: int = w._collision_bucket_cache.size()
	var large := Rect2(-768,-768,2304,2304)
	t.check(w._collision_query_props(large) == w.query_props(large) and w._collision_bucket_cache.size() == before,"large spans fall back without increasing the cache")
	var fresh = _world(script)
	t.check(fresh._collision_query_props(large) == fresh.query_props(large) and fresh._collision_bucket_cache.is_empty(),"large-span fallback applies even when retained cache capacity is available")
func _coverage_retirement(t,script) -> void:
	var w = _world(script)
	var reference = _world(Reference)
	var start := Vector2(384,384)
	t.check(w.sweep(start,Vector2(32,0),8) == reference.sweep(start,Vector2(32,0),8) and not w._collision_bucket_cache.is_empty(),"valid movement warms the actual collision candidates")
	var chunks := [["1","0"]]
	t.check(w.prepare(chunks,[],F.hydration(chunks),["0","0"]).ok and reference.prepare(chunks,[],F.hydration(chunks),["0","0"]).ok,"coverage can retire the previously warm cell without rebasing")
	var got: Dictionary = w.sweep(start,Vector2(32,0),8)
	t.check(got == reference.sweep(start,Vector2(32,0),8) and not got.ok and got.error_code == "world_not_ready","retired coverage cannot reuse a warm collision candidate as successful movement")
	t.check(w._collision_bucket_cache.is_empty() and w.diagnostics() == reference.diagnostics(),"coverage refusal preserves exact error/query counters and no retired records")
