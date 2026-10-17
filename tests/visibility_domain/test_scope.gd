extends RefCounted
# Current-dev18 A/B scope checks. Use actual native identities on both lanes;
# the oracle changes only its self/resource names, never algorithm statements.
const S = preload("res://tests/visibility_domain/support.gd")
const Nav = preload("res://game/world/city_navigation.gd")
const Precise = preload("res://game/world/precise_city_navigation.gd")
const Oracle = preload("res://tests/visibility_domain/oracle_city_navigation.gd")
const OraclePrecise = preload("res://tests/visibility_domain/oracle_precise_city_navigation.gd")
const CustomNav = preload("res://tests/visibility_domain/scope_custom_navigation.gd")
const CustomOracle = preload("res://tests/visibility_domain/scope_custom_oracle_navigation.gd")
const CustomWorld = preload("res://tests/visibility_domain/custom_stream.gd")
const CustomCached = preload("res://tests/visibility_domain/custom_cached.gd")
const CustomView = preload("res://tests/visibility_domain/custom_view.gd")
func run(t) -> void:
	var before: int = t.cases.size()
	for cached in [false,true]:
		_smooth_cases(t,cached)
		for kind in ["navigation","view","world"]:
			var p: Dictionary = _pair(t,cached,_wall(),[],["0","0"],false,kind)
			_live(p)
			_smooth(t,p,Vector2(64,128),_route(),8.0,"derived_"+kind)
			if kind == "navigation":
				t.check(p.navs[0].preparation_calls == 0 and p.navs[1].preparation_calls == 0,"derived same-name preparation callback is never invoked")
				t.check(S.same(p.navs[0].rays,p.navs[1].rays) and p.navs[0].rays.size() > 1,"derived navigation complete ray order and second-call callback retained")
			elif kind == "view": t.check(S.same(p.views[0].sweep_calls,p.views[1].sweep_calls),"derived View complete callback order")
			else: t.check(S.same(p.worlds[0].sweep_calls,p.worlds[1].sweep_calls) and S.same(p.worlds[0].public_calls,p.worlds[1].public_calls),"derived World complete sweep/owned-query order")
		_mutations(t,cached)
		_public_routes(t,cached)
		if t.mode == "scope-candidate": _proof_cases(t,cached)
	var expected: int = 120 if t.mode == "scope-candidate" else 80
	t.check(t.cases.size()-before == expected,"scope complete fixed matrix")
	t.completed.append("test_scope.gd")
func _wall() -> Array:
	return [S.prop("wall",Rect2(144,80,32,112))]
func _route() -> Array:
	return [Vector2(96,224),Vector2(224,224),Vector2(320,128)]
func _pair(t, cached: bool, records: Array = [], chunks: Array = [], origin: Array = ["0","0"], precise: bool = false, kind: String = "", center: Array = []) -> Dictionary:
	if chunks.is_empty(): chunks = S.neighborhood(origin)
	var worlds: Array = []
	var views: Array = []
	var navs: Array = []
	for i in 2:
		var script = S.Cached if cached else S.Stream
		if kind == "world": script = CustomCached if cached else CustomWorld
		var world = script.new(S.Generator.new(records,origin),42)
		t.check(world.prepare(chunks,[],S.F.hydration(chunks),origin,center).get("ok",false),"scope real native prepare "+str(i))
		var view = CustomView.new(world) if kind == "view" else S.View.new(world)
		var nav_script = Precise if precise else Nav
		if i == 1: nav_script = OraclePrecise if precise else Oracle
		if kind == "navigation": nav_script = CustomNav if i == 0 else CustomOracle
		var nav = nav_script.new(view)
		t.check(world.get_script() == script and nav.get_script() == nav_script and view.get_script() == (CustomView if kind == "view" else S.View),"scope native exact selected identities "+str(i))
		worlds.append(world); views.append(view); navs.append(nav)
	return {"worlds":worlds,"views":views,"navs":navs,"cached":cached,"chunks":chunks,"origin":origin}
func _live(p: Dictionary) -> void:
	for nav in p.navs:
		nav._direction_los = nav._direction_reuse_scope()
		if not nav._direction_los.is_empty(): nav._direction_los.tick = 10
		nav._tick_los = nav._direction_los
func _plain(value, view, world):
	# Strip only object identities, which differ between independently prepared
	# native worlds. Preserve every scalar, key, insertion order and array slot.
	if value is Object: return "view_identity" if value == view else ("source_identity" if value == world else "unexpected_object")
	if value is Dictionary:
		var result := {}
		for key in value: result[key] = _plain(value[key],view,world)
		return result
	if value is Array:
		var result: Array = []
		for item in value: result.append(_plain(item,view,world))
		return result
	return value
func _digest(value) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(var_to_bytes(value))
	return context.finish().hex_encode()
func _world_state(world, cached: bool) -> Dictionary:
	return {"diagnostics":world.diagnostics(),"last_error":world._last_error,"collision_cache":world._collision_bucket_cache.duplicate(true),"collision_key_order":world._collision_bucket_cache.keys(),"clearance_cache":world._clearance_cache.duplicate(true),"coverage":world.coverage_cache_stats() if cached else {},"coverage_cells":world._covered_cells.duplicate(true) if cached else {}}
func _state(p: Dictionary, i: int) -> Dictionary:
	var nav = p.navs[i]
	var view = p.views[i]
	return {"world":_world_state(p.worlds[i],p.cached),"view_latch":view._query_failure.duplicate(true),"view_status":view.navigation_query_status(),"view_revisions":[view._coverage_revision,view._world_revision],"view_index":view._by_origin.duplicate(true),"navigation":nav.diagnostics(),"grids":_plain(nav._grids,view,p.worlds[i]),"direction_memo":_plain(nav._direction_los,view,p.worlds[i]),"tick_memo":_plain(nav._tick_los,view,p.worlds[i])}
func _known_objects(value, view, world) -> bool:
	if value is Object: return value == view or value == world
	if value is Dictionary:
		for key in value:
			if not _known_objects(key,view,world) or not _known_objects(value[key],view,world): return false
	if value is Array:
		for item in value:
			if not _known_objects(item,view,world): return false
	return true
func _equal(t, p: Dictionary, label: String) -> void:
	for i in 2:
		var nav = p.navs[i]
		var view = p.views[i]
		var world = p.worlds[i]
		t.check(nav._world == view and view._world == world,label+": native navigation/View/source bindings")
		for memo in [nav._direction_los,nav._tick_los]:
			if not memo.is_empty(): t.check(memo.view == view and memo.source == world,label+": nonempty memo belongs to exact current lane objects")
		for grid in nav._grids.values():
			if grid.has("distance_inputs"): t.check(grid.distance_inputs[0] == view and grid.distance_inputs[1] == world,label+": grid reuse inputs bind current exact objects")
		t.check(_known_objects([nav._grids,nav._direction_los,nav._tick_los],view,world),label+": no unrelated Object is normalized away")
	t.check(S.same(_state(p,0),_state(p,1)),label+": full diagnostics/query_count/latches/grids/memo/bucket/coverage state and order")
func _alias(t, nav, label: String) -> void:
	if nav._direction_los.is_empty(): return
	var key: Array = [Vector2(-30000,-30000),Vector2(-30001,-30000),0.0]
	nav._direction_los.queries[key] = false
	t.check(nav._tick_los.queries.has(key),label+": direction/tick query dictionary alias retained")
	nav._direction_los.queries.erase(key)
func _smooth(t, p: Dictionary, start: Vector2, points: Array, radius: float, label: String) -> void:
	var actual: Array = p.navs[0]._smooth(start,points,radius)
	var baseline: Array = p.navs[1]._smooth(start,points,radius)
	t.check(S.same(actual,baseline),label+": complete ordered smoothed waypoints")
	t.check(S.same(Nav._success(start,actual),Oracle._success(start,baseline)),label+": complete success direction/length/waypoints dictionary")
	_equal(t,p,label)
	for nav in p.navs: _alias(t,nav,label)
	# A following ordinary ray must see precisely the same memo/cache/error state.
	var later_a: bool = p.navs[0]._visible(Vector2(100,120),Vector2(768,120),0.0)
	var later_b: bool = p.navs[1]._visible(Vector2(100,120),Vector2(768,120),0.0)
	t.check(later_a == later_b,label+": subsequent ordinary ray")
	_equal(t,p,label+" subsequent")
	t.cases.append({"kind":"common","name":"scope_"+label,"cached":p.cached,"input_sha256":_digest([start,points,radius]),"result_sha256":_digest(Nav._success(start,actual)),"state_sha256":_digest(_state(p,0)),"strict_query_and_cache_equality":true})
func _smooth_cases(t, cached: bool) -> void:
	for label in ["cold","warm_hits","cap4095","cap4096","no_memo","empty","one","repeated","signed_zero","subnormal","rounded_endpoint_missing","unused_corner","later_invalid","span_refusal","coordinate_refusal"]:
		var chunks: Array = []
		var start := Vector2(64,128)
		var points: Array = _route()
		var radius := 8.0
		var records: Array = _wall()
		if label == "empty": points = []
		if label == "one": points = [Vector2(96,224)]
		if label == "repeated": points = [start,start,Vector2(96,224),Vector2(96,224)]
		if label == "signed_zero":
			start = Vector2(_zero_with_sign(true),120); points = [Vector2(_zero_with_sign(false),120),Vector2(128,120)]; radius = _zero_with_sign(true); records = []
			t.check(_float32_bits(start.x) == 0x80000000 and _float32_bits(points[0].x) == 0 and _float32_bits(radius) == 0x80000000,"scope runtime signed-zero input bits retained")
		if label == "subnormal": start = Vector2(0,120); points = [Vector2(0,120),Vector2(0.00000095367431640625,120)]; radius = 7.006492321624085e-46; records = []
		if label == "rounded_endpoint_missing": start = Vector2(768,120); points = [Vector2(1000,120),Vector2(1536,120)]; radius = 0.00005; chunks = [["0","0"],["1","0"]]; records = []
		if label == "unused_corner": start = Vector2(100,100); points = [Vector2(100,900),Vector2(900,100)]; radius = 0; chunks = [["0","0"],["0","1"],["1","0"]]; records = []
		if label == "later_invalid": points.append(Vector2(100000,120))
		if label == "span_refusal": points = [Vector2(100,120),Vector2(7000,120)]; records = []
		if label == "coordinate_refusal": points = [Vector2(8192.0009765625,120)]; records = []
		var p: Dictionary = _pair(t,cached,records,chunks)
		if label != "no_memo": _live(p)
		if label == "warm_hits":
			for nav in p.navs:
				t.check(not nav._visible(start,points.back(),radius),"warm false hit is actual blocked ray")
				t.check(nav._visible(start,points[0],radius),"warm true hit is actual visible ray")
		if label in ["cap4095","cap4096"]:
			var count: int = 4095 if label == "cap4095" else 4096
			for nav in p.navs:
				for i in count: nav._direction_los.queries[[Vector2(-10000-i,1),Vector2(-10000-i,2),8.0]] = i%2 == 0
		_smooth(t,p,start,points,radius,label)
		if label in ["cap4095","cap4096"]:
			for nav in p.navs: t.check(nav._direction_los.queries.size() == 4096,"exact 4096 memo cap after misses")
		if label == "cold":
			var warm: Array = p.navs[0]._smooth(start,points,radius)
			var old_warm: Array = p.navs[1]._smooth(start,points,radius)
			t.check(S.same(warm,old_warm),"repeat warm route identical")
			_equal(t,p,"repeat warm route")
func _mutations(t, cached: bool) -> void:
	for label in ["invalidate","geometry","residency","rebase","int64_rebase","view_replace","world_replace","view_error","world_error","stale_origin"]:
		var origin: Array = ["9007199254740993","-9007199254740993"] if label == "int64_rebase" else ["0","0"]
		var p: Dictionary = _pair(t,cached,_wall(),[],origin)
		_live(p)
		for nav in p.navs: nav._smooth(Vector2(64,128),_route(),8.0)
		_equal(t,p,label+" warm prefix")
		for i in 2:
			var world = p.worlds[i]
			var nav = p.navs[i]
			if label == "invalidate": nav.invalidate(world.chunk_keys())
			elif label == "geometry": t.check(world.apply_props([{"chunk":origin,"props":[{"slot_id":"wall","hp":0,"destroyed":true}]}],1).get("ok",false),"scope public destruction")
			elif label == "residency": t.check(world.prepare([origin],[],S.F.hydration([origin]),origin).get("ok",false),"scope public residency retirement")
			elif label in ["rebase","int64_rebase"]:
				var shifted: Array = ["9007199254740994","-9007199254740993"] if label == "int64_rebase" else ["1","0"]
				t.check(world.prepare(p.chunks,[],S.F.hydration(p.chunks),shifted).get("ok",false),"scope public origin change")
			elif label in ["view_replace","world_replace"]:
				if label == "world_replace":
					var script = S.Cached if cached else S.Stream
					world = script.new(S.Generator.new(_wall(),origin),42)
					t.check(world.prepare(p.chunks,[],S.F.hydration(p.chunks),origin).get("ok",false),"scope replacement source prepare")
					p.worlds[i] = world
				p.views[i] = S.View.new(world); nav._world = p.views[i]
			elif label == "view_error": p.views[i].sweep(Vector2(100,120),Vector2(100000,0),8.0)
			elif label == "world_error": world.covered(Rect2(10000,10000,1,1))
			elif label == "stale_origin": nav._direction_los.origin = ["-1","0"]
		var points: Array = [Vector2(200,120),Vector2(768,120)] if label == "residency" else _route()
		_smooth(t,p,Vector2(64,128),points,0.0 if label == "residency" else 8.0,"mutation_"+label)
func _public_routes(t, cached: bool) -> void:
	for precise in [false,true]:
		for label in ["clear","detour","blocked_source","missing_endpoint","invalid_length","unsupported_radius"]:
			var records: Array = _wall() if label in ["detour","blocked_source"] else []
			var p: Dictionary = _pair(t,cached,records,[["0","0"]], ["0","0"],precise)
			var start := Vector2(150,120) if label == "blocked_source" else Vector2(64,128)
			var target := Vector2(768,120) if label == "missing_endpoint" else Vector2(320,128)
			if label == "invalid_length": target = Vector2(40000,40000)
			var radius := 33.0 if label == "unsupported_radius" else 8.0
			var steps: Array = []
			for tick in [10,10,11,25]:
				var actual: Dictionary = p.navs[0].direction(start,target,radius,tick)
				var baseline: Dictionary = p.navs[1].direction(start,target,radius,tick)
				t.check(S.same(actual,baseline),"public complete route "+label+" precise="+str(precise)+" tick="+str(tick))
				_equal(t,p,"public "+label+" "+str(tick))
				for nav in p.navs: t.check(nav._direction_los.is_empty(),"public direction retires invocation memo")
				steps.append({"input_sha256":_digest([start,target,radius,tick]),"result_sha256":_digest(actual),"state_sha256":_digest(_state(p,0))})
			t.cases.append({"kind":"common","name":"scope_public_"+label,"cached":cached,"precise":precise,"steps":steps,"strict_query_and_cache_equality":true})
func _proof_cases(t, cached: bool) -> void:
	var negative_zero: float = _zero_with_sign(true)
	var positive_zero: float = _zero_with_sign(false)
	t.check(_float32_bits(negative_zero) == 0x80000000 and _float32_bits(positive_zero) == 0,"scope proof runtime signed-zero bits")
	for entry in [
		["interior",Vector2(64,128),_route(),8.0,true,[],[]],
		["unused_corner",Vector2(100,100),[Vector2(100,900),Vector2(900,100)],0.0,false,[["0","0"],["0","1"],["1","0"]],[]],
		["endpoint_missing",Vector2(100,120),[Vector2(768,120)],0.0,false,[["0","0"]],[]],
		["endpoint_present",Vector2(100,120),[Vector2(768,120)],0.0,true,[["0","0"],["1","0"]],[]],
		["rounded_missing",Vector2(768,120),[Vector2(1536,120)],0.00005,false,[["0","0"],["1","0"]],[]],
		["rounded_present",Vector2(768,120),[Vector2(1536,120)],0.00005,true,[["0","0"],["1","0"],["2","0"]],[]],
		["signed_zero",Vector2(negative_zero,120),[Vector2(positive_zero,120)],negative_zero,true,[],[]],
		["subnormal",Vector2(0,120),[Vector2(0,120)],7.006492321624085e-46,true,[],[]],
		["empty_span",Vector2(0,120),[Vector2(0.00000095367431640625,120)],0.0,true,[],[]],
		["empty",Vector2(100,120),[],8.0,false,[],[]],
		["wrong_point",Vector2(100,120),["not_vector"],8.0,false,[],[]],
		["nan_point",Vector2(100,120),[Vector2(NAN,120)],8.0,false,[],[]],
		["inf_start",Vector2(INF,120),[Vector2(100,120)],8.0,false,[],[]],
		["positive_resident_edge",Vector2(6910,120),[Vector2(6910,120)],0.0,true,[["8","0"]],["8","0"]],
		["negative_resident_edge",Vector2(-6143,120),[Vector2(-6143,120)],0.0,true,[["-8","0"]],["-8","0"]],
		["above_limit",Vector2(8192.0009765625,120),[Vector2(8192,120)],0.0,false,[["8","0"]],["8","0"]],
		["negative_radius",Vector2(100,120),[Vector2(200,120)],-1.0,false,[],[]],
		["large_radius",Vector2(100,120),[Vector2(200,120)],32.00001,false,[],[]],
		["nan_radius",Vector2(100,120),[Vector2(200,120)],NAN,false,[],[]],
		["span_gt_eight",Vector2(100,120),[Vector2(7000,120)],0.0,false,[],[]]
	]:
		if entry[0] == "interior": _navigation_admission(t,cached)
		var p: Dictionary = _pair(t,cached,[],entry[5],["0","0"],false,"",entry[6])
		var world = p.worlds[0]
		var view = p.views[0]
		var prior: Dictionary = _world_state(world,cached)
		var ready: bool = view._smoothing_scope_ready(entry[1],entry[2],entry[3])
		t.check(ready == entry[4],"scope proof independent expectation "+str(entry[0]))
		if entry[0] == "above_limit":
			t.check(not view._smoothing_scope_ready(Vector2(8192,120),[Vector2(8192,120)],0.0),"scope exact positive scalar limit refuses uncovered cell")
			t.check(not view._smoothing_scope_ready(Vector2(-8192,120),[Vector2(-8192,120)],0.0),"scope exact negative scalar limit refuses uncovered cell")
		if ready:
			var sources: Array = [entry[1]]
			sources.append_array(entry[2])
			for source in sources:
				for first in range(entry[2].size()): t.check(view.smoothing_queries_safe(source,entry[2],first,entry[3]),"admission implies every original suffix predicate")
				for target in entry[2]:
					var delta: Vector2 = target-source
					var bounds: Rect2 = S.Stream._swept_rect(source,delta,entry[3])
					t.check(S.Stream._valid_query(source,delta,entry[3]) and view._visibility_domain_ready(bounds,source,delta,entry[3]),"admission implies every original ray-domain predicate")
		t.check(S.same(prior,_world_state(world,cached)) and view._query_failure.is_empty(),"scope proof leaves full query/cache/error state untouched")
		t.cases.append({"kind":"proof","name":"scope_proof_"+str(entry[0]),"cached":cached,"ready":ready,"expected":entry[4],"strict_query_and_cache_equality":true})
func _navigation_admission(t, cached: bool) -> void:
	# Separate fixtures keep the common cold execution genuinely un-prewarmed.
	for precise in [false,true]:
		var p: Dictionary = _pair(t,cached,_wall(),[],["0","0"],precise)
		var nav = p.navs[0]
		var prior: Dictionary = _world_state(p.worlds[0],cached)
		t.check(not nav._smoothing_scope_ready(Vector2(64,128),_route(),8.0),"no live direction memo refuses navigation admission")
		_live(p)
		t.check(nav._smoothing_scope_ready(Vector2(64,128),_route(),8.0),"exact native City/Precise live scope actually admits")
		t.check(nav._smoothing_scope_ready(Vector2(64,128),_route(),32.0) and p.views[0]._smoothing_scope_ready(Vector2(64,128),_route(),32.0),"maximum radius32 admitted in native Nav and View")
		t.check(not nav._smoothing_scope_ready(Vector2(64,128),[],8.0),"empty route cannot create a scope")
		for field in ["view","source","coverage","revision","origin"]:
			_live(p)
			if field == "view": nav._direction_los.view = p.views[1]
			elif field == "source": nav._direction_los.source = p.worlds[1]
			elif field == "origin": nav._direction_los.origin = ["-1","0"]
			else: nav._direction_los[field] += 1
			t.check(not nav._smoothing_scope_ready(Vector2(64,128),_route(),8.0),"stale "+field+" refuses navigation scope without clearing memo")
			t.check(not nav._direction_los.is_empty(),"refused admission preserves original later memo retirement")
		_live(p)
		nav.invalidate(p.worlds[0].chunk_keys())
		t.check(not nav._smoothing_scope_ready(Vector2(64,128),_route(),8.0),"invalidation retires scope admission")
		t.check(S.same(prior,_world_state(p.worlds[0],cached)),"navigation admission probes leave complete query/cache/error state untouched")
func _zero_with_sign(negative: bool) -> float:
	# Same runtime IEEE-byte construction as the unchanged signedzero-r2 suite.
	var bytes := PackedByteArray([0,0,0,0])
	if negative: bytes[3] = 128
	return bytes.decode_float(0)
func _float32_bits(value: float) -> int:
	var bytes := PackedByteArray([0,0,0,0])
	bytes.encode_float(0,value)
	return bytes.decode_u32(0)
