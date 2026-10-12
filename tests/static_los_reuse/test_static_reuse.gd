extends RefCounted
const F = preload("res://tests/world/fixtures/city_fixture.gd")
const N = preload("res://game/world/precise_city_navigation.gd")
const O = preload("res://tests/direction_los_reuse/oracle_precise_navigation.gd")
const V = preload("res://game/world/streamed_navigation_view.gd")
const Cached = preload("res://game/world/cached_streamed_world.gd")
const A := Vector2(496,194)
const B := Vector2(1152,384)
const OPEN_A := Vector2(384,384)
const OPEN_B := Vector2(640,384)
func _world(cached: bool, chunks: Array = F.neighborhood()):
 if not cached: return F.world(chunks)
 var w = Cached.new(F.generator(),42)
 w.prepare(chunks,[],F.hydration(chunks),["0","0"])
 return w
func _q(w) -> int: return w.diagnostics().query_count
func run(t) -> void:
 _derived_cached(t)
 for cached in [false,true]:
  _across_ticks(t,cached)
  _exact_keys(t,cached)
  _invalidation(t,cached)
  _errors(t,cached)
  _cold_and_identity(t,cached)
  _same_geometry_prepare(t,cached)
func _across_ticks(t,cached: bool) -> void:
 var w = _world(cached); var v = V.new(w); var n = N.new(v)
 var o = O.new(V.new(_world(cached)))
 t.check(n.direction(A,B,8,0) == o.direction(A,B,8,0),"first static route is oracle-exact")
 for tick in [1,11,12,13,24,10000]:
  var q := _q(w)
  t.check(n.direction(A,B,8,tick) == o.direction(A,B,8,tick),"static route exact across distance-field refresh and large tick step")
  t.check(_q(w)-q == 2,"unchanged exact geometry reuses LOS across ticks but rechecks both endpoint walkabilities; got "+str(_q(w)-q))
  t.check(n._direction_los.is_empty() and v.navigation_query_status().ok,"public return does not expose an active scope")
 var q := _q(w)
 t.check(n.direction(A,B,8,0) == o.direction(A,B,8,0),"rewind route stays exact")
 t.check(_q(w)-q > 2,"rewind conservatively starts a cold memo")
func _exact_keys(t,cached: bool) -> void:
 var w = _world(cached); var n = N.new(V.new(w))
 n.direction(OPEN_A,OPEN_B,8,0)
 var tick := 0
 for entry in [[OPEN_B,OPEN_A,8.0],[OPEN_A,Vector2(640.00006103515625,384),8.0],[OPEN_A,OPEN_B,8.0000000001]]:
  tick += 1
  var q := _q(w)
  t.check(n.direction(entry[0],entry[1],entry[2],tick).ok,"distinct exact key remains a clear route")
  t.check(_q(w)-q > 2,"reverse/adjacent float32 endpoint/float64 radius have distinct authoritative observations")
  q = _q(w)
  t.check(n.direction(entry[0],entry[1],entry[2],tick+1).ok and _q(w)-q == 2,"each exact key can be reused on its next tick")
  tick += 1
func _invalidation(t,cached: bool) -> void:
 var w = _world(cached); var v = V.new(w); var n = N.new(v)
 n.direction(A,B,8,0)
 n.invalidate(["0,0"])
 t.check(n._tick_los.is_empty(),"explicit invalidate immediately discards the geometry memo")
 var invalidated_expected: Dictionary = O.new(V.new(w)).direction(A,B,8,1)
 var q := _q(w)
 t.check(n.direction(A,B,8,1) == invalidated_expected,"invalidation preserves the complete route")
 t.check(_q(w)-q > 2,"invalidation repeats authoritative sweep")
 var changes: Array = []
 for prop in w.localized_chunk("0,0").props:
  if prop.destructible: changes.append({"slot_id":prop.slot_id,"hp":0,"destroyed":true})
 t.check(w.apply_props([{"chunk":["0","0"],"props":changes}],1).ok,"public terrain publication succeeds")
 var expected: Dictionary = O.new(V.new(w)).direction(A,B,8,2)
 q = _q(w)
 t.check(n.direction(A,B,8,2) == expected and _q(w)-q > 2,"world revision retires former exact LOS")
 n.direction(OPEN_A,OPEN_B,8,2)
 t.check(w.prepare(F.neighborhood(),[],F.hydration(F.neighborhood()),["1","0"]).ok,"public origin rebase succeeds")
 expected = O.new(V.new(w)).direction(OPEN_A,OPEN_B,8,3)
 q = _q(w)
 t.check(n.direction(OPEN_A,OPEN_B,8,3) == expected and _q(w)-q > 2,"origin and coverage revision retire former local-coordinate LOS")
 var covered = _world(cached); var cv = V.new(covered); var cn = N.new(cv)
 cn.direction(OPEN_A,Vector2(1152,384),8,0)
 t.check(covered.prepare([["0","0"]],[],{"0,0":[]},["0","0"]).ok,"coverage can retire chunks without rebasing")
 var missing: Dictionary = cn.direction(OPEN_A,Vector2(1152,384),8,1)
 t.check(not missing.ok and not cv.navigation_query_status().ok,"missing coverage remains authoritative and sticky")
 t.check(cn._tick_los.is_empty(),"endpoint coverage error immediately discards the retained memo")
func _errors(t,cached: bool) -> void:
 var w = _world(cached,[["0","0"]]); var v = V.new(w); var n = N.new(v)
 n.direction(OPEN_A,OPEN_B,8,0)
 var failed: Dictionary = n.direction(OPEN_A,Vector2(760.0001220703125,384),8,1)
 t.check(not failed.ok and not v.navigation_query_status().ok,"half-open float coverage failure is not skipped")
 t.check(n._tick_los.is_empty(),"authoritative failure at endpoint retires all successful observations")
 var failure: Dictionary = v.navigation_query_status()
 n.direction(OPEN_A,OPEN_B,8,2)
 t.check(v.navigation_query_status() == failure and n._tick_los.is_empty(),"later success never hides first query failure")
 t.check(w.prepare([["0","0"]],[],{"0,0":[]},["0","0"]).ok,"healthy prepare resets world error without changing geometry")
 v.begin_navigation_queries()
 var q := _q(w)
 n.direction(OPEN_A,OPEN_B,8,3)
 t.check(_q(w)-q > 2,"recovery after observed error starts authoritatively")
 # A failed actual sweep clears the same shared scope, including earlier hits.
 n._direction_los = n._tick_los
 t.check(not n._visible(OPEN_A,Vector2(INF,0),8),"nonfinite exact sweep is never reused")
 t.check(n._tick_los.is_empty() and n._direction_los.is_empty(),"failed sweep clears shared retained scope")
func _cold_and_identity(t,cached: bool) -> void:
 var w = _world(cached); var v = V.new(w); var n = N.new(v)
 n.direction(OPEN_A,OPEN_B,8,0)
 var second = _world(cached)
 v._world = second
 var q := _q(second)
 n.direction(OPEN_A,OPEN_B,8,1)
 t.check(_q(second)-q > 2,"same-revision source replacement does not reuse old object observations")
 n._world = V.new(second)
 q = _q(second)
 n.direction(OPEN_A,OPEN_B,8,2)
 t.check(_q(second)-q > 2,"new view identity conservatively retires memo")
 var cold = N.new(V.new(second))
 t.check(cold._tick_los.is_empty(),"new restored navigation starts without serialized memo")
 q = _q(second)
 var actual: Dictionary = cold.direction(A,B,8,100)
 t.check(_q(second)-q > 2 and actual == O.new(V.new(second)).direction(A,B,8,100),"cold restore route remains oracle-exact and authoritative")

class ChangingCachedWorld:
 extends "res://game/world/cached_streamed_world.gd"
 var calls: Array = []
 var refuse := false
 func sweep(position: Vector2, delta: Vector2, radius: float) -> Dictionary:
  calls.append([position,delta,radius])
  if refuse: return {"ok":false,"error_code":"derived_tick_failure","position":position,"fraction":0.0,"hit_prop_id":""}
  return super.sweep(position,delta,radius)
func _derived_cached(t) -> void:
 var a = ChangingCachedWorld.new(F.generator(),42); var b = ChangingCachedWorld.new(F.generator(),42)
 for w in [a,b]: w.prepare(F.neighborhood(),[],F.hydration(F.neighborhood()),["0","0"])
 var va = V.new(a); var vb = V.new(b); var n = N.new(va); var o = O.new(vb)
 for tick in [0,1,2]:
  a.refuse = tick == 1; b.refuse = tick == 1
  t.check(n.direction(A,B,8,tick) == o.direction(A,B,8,tick),"derived cached world can change results at the next tick")
  t.check(n._tick_los.is_empty(),"derived cached world is never epoch-cache eligible")
  t.check(a.calls == b.calls and va.navigation_query_status() == vb.navigation_query_status(),"derived cached sweep arguments, call order and sticky error stay exact")
func _same_geometry_prepare(t,cached: bool) -> void:
 var w = _world(cached); var n = N.new(V.new(w))
 var before: Dictionary = n.direction(A,B,8,0)
 var revision: int = w._coverage_revision
 t.check(w.prepare(F.neighborhood(),[],F.hydration(F.neighborhood()),["0","0"]).ok and w._coverage_revision == revision,"unchanged prepare rebuilds records without changing geometry epoch")
 var q := _q(w)
 t.check(n.direction(A,B,8,1) == before and _q(w)-q == 2,"same-epoch record rebuilding preserves exact cached geometry results")
