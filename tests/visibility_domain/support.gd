extends RefCounted
const Stream = preload("res://game/world/streamed_world.gd")
const Cached = preload("res://game/world/cached_streamed_world.gd")
const View = preload("res://game/world/streamed_navigation_view.gd")
const Helper = preload("res://game/core/streamed_run_world.gd")
const Old = preload("res://tests/visibility_domain/oracle_old_view.gd")
const Generator = preload("res://tests/visibility_domain/fixture_generator.gd")
const Address = preload("res://game/world/world_address.gd")
const F = preload("res://tests/world/fixtures/city_fixture.gd")
static func same(a, b) -> bool:
	# Values compared here contain no Object references; retain NAN bit patterns.
	return var_to_bytes(a) == var_to_bytes(b)
static func prop(id: String, bounds: Rect2, mask: int = 1, cover: int = 0) -> Dictionary:
	return {"id":id,"bounds":bounds,"mask":mask,"cover":cover}
static func neighborhood(origin: Array = ["0","0"], extent: int = 1) -> Array:
	var chunks: Array = []
	for y in range(-extent,extent+1):
		for x in range(-extent,extent+1): chunks.append(Address.normalize(origin,Vector2(x*768,y*768)).chunk)
	return chunks
static func pair(t, cached: bool, records: Array = [], chunks: Array = [], origin: Array = ["0","0"], real: bool = false) -> Dictionary:
	if chunks.is_empty(): chunks = neighborhood(origin)
	var script = Cached if cached else Stream
	var worlds: Array = []
	var views: Array = []
	var helpers: Array = []
	for index in 3:
		var generator = F.generator() if real else Generator.new(records,origin)
		var world = script.new(generator,42)
		t.check(world.prepare(chunks,[],F.hydration(chunks),origin).get("ok",false),"fixture prepares "+str(index))
		var view = View.new(world)
		var helper = Helper.new()
		helper._world = world
		worlds.append(world); views.append(view); helpers.append(helper)
		t.check(world.get_script() == script and view.get_script() == View,"actual native World/View identities "+str(index))
	return {"worlds":worlds,"views":views,"helpers":helpers,"cached":cached,"chunks":chunks,"origin":origin}
static func diagnostics_without_work_count(world) -> Dictionary:
	var value: Dictionary = world.diagnostics().duplicate(true)
	value.erase("query_count")
	return value
static func query(t, p: Dictionary, start: Vector2, target: Vector2, radius: float, label: String, count_policy: String = "shortcut_or_full") -> Dictionary:
	var before: Array = []
	for world in p.worlds: before.append(world._query_count)
	var actual: Dictionary = p.views[0].visibility_query(start,target,radius)
	var full: Dictionary = p.views[1]._visibility_full_sweep(start,target-start,radius)
	var old: Dictionary = Old.visibility_query(p.views[2],start,target,radius)
	t.check(same(actual,full),label+": exact native full-sweep visibility dictionary")
	t.check(same(actual,old),label+": original View visibility dictionary")
	for index in [1,2]:
		t.check(same(diagnostics_without_work_count(p.worlds[0]),diagnostics_without_work_count(p.worlds[index])),label+": complete world diagnostics except intentionally different query_count "+str(index))
		t.check(same(p.worlds[0]._last_error,p.worlds[index]._last_error),label+": world last_error exact "+str(index))
		t.check(same(p.views[0]._query_failure,p.views[index]._query_failure),label+": full raw View first-failure latch "+str(index))
		t.check(same(p.views[0].navigation_query_status(),p.views[index].navigation_query_status()),label+": public View error status "+str(index))
	# Exercise the actual helper's first-error recorder/status API. This is an
	# isolated propagation-boundary check, not a claim of end-to-end admission.
	for index in 3: p.helpers[index]._query_result(p.views[index].navigation_query_status())
	for index in [1,2]:
		t.check(same(p.helpers[0]._query_failure,p.helpers[index]._query_failure),label+": raw actual helper latch "+str(index))
		t.check(same(p.helpers[0].query_status(),p.helpers[index].query_status()),label+": actual helper query_status "+str(index))
	var counts: Array = []
	var coverage: Array = []
	for index in 3:
		counts.append(p.worlds[index]._query_count-before[index])
		if p.cached: coverage.append(p.worlds[index].coverage_cache_stats())
	# Query count measures physical work. Never require count/cache-counter
	# equality for a successful shortcut, and never discard real error fields.
	t.check(counts[0] == 1 or counts[0] == counts[1],label+": actual work is one real query or authoritative full sweep")
	t.check(counts[2] == 1 or counts[2] == counts[1],label+": old work is one real query or authoritative full sweep")
	if count_policy == "full": t.check(counts[0] == counts[1] and counts[2] == counts[1],label+": mandatory fallback retains actual query work")
	if count_policy == "one" and t.mode == "candidate": t.check(counts[0] == 1,label+": candidate admits exact resident domain with one query")
	t.cases.append({"name":label,"cached":p.cached,"actual":actual,"full":full,"old":old,"count_policy":count_policy,"query_deltas_candidate_full_old":counts,"coverage_candidate_full_old":coverage,"last_error":p.worlds[0]._last_error,"view_error":p.views[0]._query_failure.get("error_code",""),"helper_error":p.helpers[0].query_status().get("error_code","")})
	return actual
static func expect_visible(t, result: Dictionary, visible: bool, label: String) -> void:
	t.check(result.get("ok",false) and result.get("visible",not visible) == visible,label+": independent visibility expectation")
static func prepare_all(t, p: Dictionary, chunks: Array, origin: Array) -> void:
	for world in p.worlds: t.check(world.prepare(chunks,[],F.hydration(chunks),origin).get("ok",false),"public prepare updates residency/origin")
	p.chunks = chunks; p.origin = origin
static func expect_status(t, p: Dictionary, world_error: String, view_error: String, helper_error: String, label: String) -> void:
	for index in 3:
		t.check(p.worlds[index]._last_error == world_error,label+": independent world error "+str(index))
		t.check(p.views[index]._query_failure.get("error_code","") == view_error,label+": independent View error "+str(index))
		t.check(p.helpers[index].query_status().get("error_code","") == helper_error,label+": independent helper error "+str(index))
