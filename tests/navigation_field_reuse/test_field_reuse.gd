extends RefCounted
const F = preload("res://tests/world/fixtures/city_fixture.gd")
const N = preload("res://game/world/precise_city_navigation.gd")
const O = preload("res://tests/navigation_field_reuse/oracle_precise.gd")
const V = preload("res://game/world/streamed_navigation_view.gd")
const Cached = preload("res://game/world/cached_streamed_world.gd")
const Derived = preload("res://tests/direction_los_reuse/derived_precise_navigation.gd")
const DerivedScope = preload("res://tests/navigation_field_reuse/derived_scope.gd")
const Tracing = preload("res://tests/direction_los_reuse/tracing_stream.gd")
const Opaque = preload("res://tests/review_smoothing_query_safety/opaque_view.gd")
func _world(cached: bool, chunks: Array = F.neighborhood()):
 if not cached: return F.world(chunks)
 var w = Cached.new(F.generator(),42)
 w.prepare(chunks,[],F.hydration(chunks),["0","0"])
 return w
func _expansions(n) -> int: return int(n.get_meta("field_expansions",0))
func _count_check(t,value: bool,message: String) -> void:
 if OS.get_environment("FIELD_TEST_INSTRUMENTED") == "1": t.check(value,message)
func _seeds(g: Dictionary) -> Array:
 var found: Array = []
 for id in g.distances.size():
  if g.distances[id] == 0: found.append(id)
 return found
func run(t) -> void:
 for cached in [false,true]:
  _field(t,cached)
  _routes(t,cached)
  _seed_boundaries(t,cached)
  _epoch_and_ownership(t,cached)
 _actual_seed_failure(t)
 _fallback(t)
func _field(t,cached: bool) -> void:
 var a = _world(cached); var b = _world(cached)
 var va = V.new(a); var vb = V.new(b); var na = N.new(va); var nb = O.new(vb)
 var ga: Dictionary = na._build_grid(va.localized_chunk("0,0"),8)
 var gb: Dictionary = nb._build_grid(vb.localized_chunk("0,0"),8)
 var goal := Vector2(640,384); var target := 12*24+20
 na._distances(ga,target,goal,8,0); nb._distances(gb,target,goal,8,0)
 var initial := _expansions(na)
 _count_check(t,initial == 1,"instrumentation observes first real BFS expansion")
 for tick in [1,12,2]:
  for radius in [8.0,7.9999999999]:
   goal.x = 640.00006103515625 if tick == 1 else 640.0
   na._distances(ga,target,goal,radius,tick); nb._distances(gb,target,goal,radius,tick)
   t.check(ga.distances == gb.distances and ga.target == gb.target and ga.tick == gb.tick,"exact goal/radius/tick refresh preserves complete field")
   t.check(va.navigation_query_status() == vb.navigation_query_status() and a.diagnostics() == b.diagnostics(),"seed visibility calls and side effects remain identical")
 _count_check(t,_expansions(na) == initial,"same exact seeds reuse the existing distance field")
 t.check(na.diagnostics() == nb.diagnostics(),"route_builds remains the count of logical field refreshes")
 goal = Vector2(672,384); target += 1
 var previous := _seeds(ga)
 var changed_before := _expansions(na)
 na._distances(ga,target,goal,8,13); nb._distances(gb,target,goal,8,13)
 t.check(previous != _seeds(ga) and ga.distances == gb.distances,"changed seed IDs reconstruct the exact field")
 _count_check(t,_expansions(na) == changed_before+1,"changed seeds execute BFS")
 var before := _expansions(na)
 va.begin_navigation_queries(); vb.begin_navigation_queries()
 va.sweep(Vector2(384,384),Vector2(100000,0),8); vb.sweep(Vector2(384,384),Vector2(100000,0),8)
 na._distances(ga,target,goal,8,14); nb._distances(gb,target,goal,8,14)
 _count_check(t,_expansions(na) == before+1,"preexisting real query failure disables reuse")
 t.check(va.navigation_query_status() == vb.navigation_query_status() and ga.distances == gb.distances,"failure path preserves actual sticky query error")
 # Same-chunk flag regeneration and origin/coverage changes use a fresh field.
 for w in [a,b]:
  var changes: Array = []
  for prop in w.localized_chunk("0,0").props:
   if prop.destructible: changes.append({"slot_id":prop.slot_id,"hp":0,"destroyed":true})
  t.check(w.apply_props([{"chunk":["0","0"],"props":changes}],1).ok,"real moving-world geometry mutation")
 va.begin_navigation_queries(); vb.begin_navigation_queries()
 var ca: Dictionary = va.localized_chunk("0,0"); var cb: Dictionary = vb.localized_chunk("0,0")
 ga = na._build_grid(ca,8); gb = nb._build_grid(cb,8)
 before = _expansions(na)
 na._distances(ga,target,goal,8,15); nb._distances(gb,target,goal,8,15)
 _count_check(t,_expansions(na) == before+1 and ga.distances == gb.distances,"new geometry grid cannot borrow the previous field")
 for w in [a,b]: t.check(w.prepare(F.neighborhood(),[],F.hydration(F.neighborhood()),["1","0"]).ok,"public origin/coverage rebase")
 before = _expansions(na)
 na._distances(ga,target,goal,8,16); nb._distances(gb,target,goal,8,16)
 _count_check(t,_expansions(na) == before+1 and ga.distances == gb.distances,"changed coverage epoch disables prior field reuse")
func _routes(t,cached: bool) -> void:
 var a = _world(cached); var b = _world(cached)
 var va = V.new(a); var vb = V.new(b); var na = N.new(va); var nb = O.new(vb)
 for tick in [0,1,12,2,13]:
  for radius in [8.0,8.0000000001,16.0,24.0,32.0]:
   for target in [Vector2(1152,384),Vector2(1152.0001220703125,384),Vector2(1140,390)]:
    va.begin_navigation_queries(); vb.begin_navigation_queries()
    var actual: Dictionary = na.direction(Vector2(496,194),target,radius,tick)
    var expected: Dictionary = nb.direction(Vector2(496,194),target,radius,tick)
    t.check(actual == expected,"complete waypoints, length, direction and errors equal frozen baseline")
    t.check(va.navigation_query_status() == vb.navigation_query_status() and a.diagnostics() == b.diagnostics(),"public route query effects and counters remain exact")
    var cold = N.new(V.new(_world(cached)))
    t.check(cold.direction(Vector2(496,194),target,radius,tick) == actual,"fresh navigation reconstruction preserves warm route result")
func _fallback(t) -> void:
 for kind in ["stream","view","navigation","scope"]:
  var a = Tracing.new(F.generator(),42) if kind == "stream" else _world(false)
  var b = Tracing.new(F.generator(),42) if kind == "stream" else _world(false)
  if kind == "stream":
   for w in [a,b]: w.prepare(F.neighborhood(),[],F.hydration(F.neighborhood()),["0","0"])
  var va = Opaque.new(a) if kind == "view" else V.new(a)
  var vb = Opaque.new(b) if kind == "view" else V.new(b)
  var na = DerivedScope.new(va) if kind == "scope" else (Derived.new(va) if kind == "navigation" else N.new(va))
  var nb = O.new(vb)
  var ga: Dictionary = na._build_grid(va.localized_chunk("0,0"),8)
  var gb: Dictionary = nb._build_grid(vb.localized_chunk("0,0"),8)
  for tick in [0,1]:
   na._distances(ga,308,Vector2(640,384),8,tick); nb._distances(gb,308,Vector2(640,384),8,tick)
   t.check(ga.distances == gb.distances and va.navigation_query_status() == vb.navigation_query_status(),"derived callback field and errors remain exact")
  _count_check(t,_expansions(na) == 2,"derived "+kind+" never reuses distance field")
  t.check(a.diagnostics() == b.diagnostics(),"derived callback diagnostic side effects preserved")
  if kind == "stream": t.check(a.calls == b.calls,"derived sweep callback order and arguments preserved")
  if kind == "view": t.check(va.sweep_calls == vb.sweep_calls,"derived view callback order and arguments preserved")

func _actual_seed_failure(t) -> void:
 var a = _world(false,[["0","0"]]); var b = _world(false,[["0","0"]])
 var va = V.new(a); var vb = V.new(b); var na = N.new(va); var nb = O.new(vb)
 var ga: Dictionary = na._build_grid(va.localized_chunk("0,0"),8)
 var gb: Dictionary = nb._build_grid(vb.localized_chunk("0,0"),8)
 var target := 12*24+23
 na._distances(ga,target,Vector2(759,384),8,0); nb._distances(gb,target,Vector2(759,384),8,0)
 var old_flags: PackedByteArray = ga.flags.duplicate()
 t.check(not _seeds(ga).is_empty(),"coverage-boundary fixture starts with reachable seed")
 var before := _expansions(na)
 na._distances(ga,target,Vector2(760.0001220703125,384),8,1)
 nb._distances(gb,target,Vector2(760.0001220703125,384),8,1)
 _count_check(t,_expansions(na) == before+1,"real seed-query failure cannot return a cached successful field")
 t.check(_seeds(ga).is_empty() and ga.distances == gb.distances,"failed seed selection rebuilds the original unreachable field")
 t.check(not va.navigation_query_status().ok and va.navigation_query_status() == vb.navigation_query_status(),"actual failed seed query preserves sticky error")
 t.check(a.diagnostics() == b.diagnostics() and ga.flags == old_flags,"seed verification keeps original calls and leaves owned grid flags unchanged")
 t.check(not ga.has("distance_inputs"),"failed seed query retires earlier successful field reuse eligibility")

func _seed_ids(n,grid: Dictionary,target: int,goal: Vector2,radius: float) -> Array:
 var result: Array = []
 if grid.flags[target] and n._visible(n._center(target,grid.local_origin),goal,radius): return [target]
 for id in n._neighbors(target):
  if grid.flags[id] and n._visible(n._center(id,grid.local_origin),goal,radius): result.append(id)
 return result
func _seed_boundaries(t,cached: bool) -> void:
 var a = _world(cached); var b = _world(cached)
 var va = V.new(a); var vb = V.new(b); var na = N.new(va); var nb = O.new(vb)
 var ga: Dictionary = na._build_grid(va.localized_chunk("0,0"),8)
 var gb: Dictionary = nb._build_grid(vb.localized_chunk("0,0"),8)
 var boundary: Dictionary = {}
 for id in 576:
  if not ga.flags[id]: continue
  var center: Vector2 = na._center(id,ga.local_origin)
  for offset in [Vector2(15,0),Vector2(-15,0),Vector2(0,15),Vector2(0,-15)]:
   var goal: Vector2 = center+offset
   if _seed_ids(na,ga,id,goal,0.1) != _seed_ids(na,ga,id,goal,8.0):
    boundary = {"id":id,"center":center,"goal":goal}; break
  if not boundary.is_empty(): break
 t.check(not boundary.is_empty(),"actual geometry contains within-cell radius-sensitive seed boundary")
 if boundary.is_empty(): return
 # Clear the search-only query observations, then use paired original calls.
 va.begin_navigation_queries(); vb.begin_navigation_queries()
 for args in [[boundary.center,8.0],[boundary.goal,8.0],[boundary.goal,0.1],[boundary.goal,8.0]]:
  var previous := _seeds(ga) if ga.has("distances") else []
  var before := _expansions(na)
  na._distances(ga,boundary.id,args[0],args[1],1); nb._distances(gb,boundary.id,args[0],args[1],1)
  t.check(ga.distances == gb.distances and va.navigation_query_status() == vb.navigation_query_status(),"same-cell changed goal/radius uses actual seed visibility")
  if previous != _seeds(ga): _count_check(t,_expansions(na) == before+1,"changed actual seed visibility always rebuilds BFS")
func _epoch_and_ownership(t,cached: bool) -> void:
 var w = _world(cached); var v = V.new(w); var n = N.new(v)
 var start := Vector2(496,194); var goal := Vector2(1152,384)
 n.direction(start,goal,8,0)
 t.check(n._grids.has("0,0:8"),"obstructed public route owns a populated grid")
 if not n._grids.has("0,0:8"): return
 var old: Dictionary = n._grids["0,0:8"]
 var flags: PackedByteArray = old.flags.duplicate()
 # A revision-only public mutation keeps geometry values but must replace the grid.
 t.check(w.apply_props([{"chunk":["0","0"],"props":[]}],1).ok,"public geometry revision advances")
 var fresh_result: Dictionary = n.direction(start,goal,8,1)
 t.check(n._grids.has("0,0:8") and not is_same(old,n._grids["0,0:8"]),"geometry revision replaces grid ownership rather than mutating old flags")
 t.check(old.flags == flags and old.revision != n._grids["0,0:8"].revision,"old immutable-by-ownership flags and geometry revision remain intact")
 var cold = N.new(V.new(w))
 t.check(cold.direction(start,goal,8,1) == fresh_result,"post-mutation cold navigation equals warm reconstruction")
 var grid: Dictionary = n._grids["0,0:8"]
 var target := 12*24+20
 n._distances(grid,target,Vector2(640,384),8,2)
 var before := _expansions(n)
 var expanded: Array = F.neighborhood(); expanded.append(["2","0"])
 t.check(w.prepare(expanded,[],F.hydration(expanded),["0","0"]).ok,"coverage changes without origin movement")
 n._distances(grid,target,Vector2(640,384),8,3)
 _count_check(t,_expansions(n) == before+1,"coverage revision with identical origin invalidates field reuse")
 before = _expansions(n)
 n._world = V.new(w)
 n._distances(grid,target,Vector2(640,384),8,4)
 _count_check(t,_expansions(n) == before+1,"replacement view cannot inherit old field reuse scope")
 before = _expansions(n)
 n._world._world = _world(cached)
 n._distances(grid,target,Vector2(640,384),8,5)
 _count_check(t,_expansions(n) == before+1,"replacement stream cannot inherit old field reuse scope")
