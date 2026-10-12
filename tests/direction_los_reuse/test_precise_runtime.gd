extends RefCounted
const F = preload("res://tests/world/fixtures/city_fixture.gd")
const N = preload("res://game/world/precise_city_navigation.gd")
const O = preload("res://tests/direction_los_reuse/oracle_precise_navigation.gd")
const V = preload("res://game/world/streamed_navigation_view.gd")
const Cached = preload("res://game/world/cached_streamed_world.gd")
const Derived = preload("res://tests/direction_los_reuse/derived_precise_navigation.gd")
func run(t) -> void:
 for cached in [false,true]:
  var a = Cached.new(F.generator(),42) if cached else F.world(F.neighborhood())
  var b = Cached.new(F.generator(),42) if cached else F.world(F.neighborhood())
  if cached:
   for w in [a,b]: w.prepare(F.neighborhood(),[],F.hydration(F.neighborhood()),["0","0"])
  var va = V.new(a); var vb = V.new(b); var na = N.new(va); var nb = O.new(vb)
  t.check(not na._direction_reuse_scope().is_empty(),"actual runtime exact PreciseCityNavigation enables reuse")
  t.check(Derived.new(va)._direction_reuse_scope().is_empty(),"unrecognized derived precise navigation remains authoritative")
  for tick in [0,1,12,2]:
   for radius in [8.0,8.01,16.0,24.0,32.0]:
    for target in [Vector2(1152,384),Vector2(1152.0001220703125,384)]:
     va.begin_navigation_queries(); vb.begin_navigation_queries()
     t.check(na.direction(Vector2(496,194),target,radius,tick) == nb.direction(Vector2(496,194),target,radius,tick),"precise goal/radius invalidation route remains exact")
     t.check(va.navigation_query_status() == vb.navigation_query_status(),"precise runtime sticky status remains exact")
     t.check(na._direction_los.is_empty(),"precise runtime return drops memo")
  print("PRECISE_REUSE_QUERIES ",JSON.stringify({"cached":cached,"actual":a.diagnostics().query_count,"baseline":b.diagnostics().query_count}))
  t.check(a.diagnostics().query_count < b.diagnostics().query_count,"actual runtime exact precise class reuses authoritative queries")
