extends RefCounted
const F = preload("res://tests/world/fixtures/city_fixture.gd")
const N = preload("res://game/world/city_navigation.gd")
const O = preload("res://tests/direction_los_reuse/oracle_navigation.gd")
const V = preload("res://game/world/streamed_navigation_view.gd")
const Cached = preload("res://game/world/cached_streamed_world.gd")
func run(t) -> void:
 for cached in [false,true]:
  var a = Cached.new(F.generator(),42) if cached else F.world(F.neighborhood())
  var b = Cached.new(F.generator(),42) if cached else F.world(F.neighborhood())
  if cached:
   a.prepare(F.neighborhood(),[],F.hydration(F.neighborhood()),["0","0"])
   b.prepare(F.neighborhood(),[],F.hydration(F.neighborhood()),["0","0"])
  var va = V.new(a); var vb = V.new(b)
  var na = N.new(va); var nb = O.new(vb)
  var actual: Dictionary = na.direction(Vector2(496,194),Vector2(1152,384),8,0)
  var expected: Dictionary = nb.direction(Vector2(496,194),Vector2(1152,384),8,0)
  t.check(actual == expected,"real obstructed direction preserves complete route")
  t.check(va.navigation_query_status() == vb.navigation_query_status(),"real direction preserves sticky status")
  print("DIRECTION_REUSE_QUERIES ",JSON.stringify({"cached":cached,"actual":a.diagnostics().query_count,"baseline":b.diagnostics().query_count,"route":str(actual)}))
  t.check(a.diagnostics().query_count < b.diagnostics().query_count,"exact direction reuses duplicate successful LOS in one call")
  for start in [Vector2(384,384),Vector2(INF,0),Vector2(NAN,0),Vector2(49153,0)]:
   for radius in [-1.0,0.0,8.01,32.0,33.0,NAN,INF]:
    va.begin_navigation_queries(); vb.begin_navigation_queries()
    var actual_invalid: Dictionary = na.direction(start,Vector2(640,384),radius,1)
    var expected_invalid: Dictionary = nb.direction(start,Vector2(640,384),radius,1)
    t.check(JSON.stringify(actual_invalid) == JSON.stringify(expected_invalid),"invalid/valid direction matrix preserves complete return")
    t.check(JSON.stringify(va.navigation_query_status()) == JSON.stringify(vb.navigation_query_status()),"invalid/valid direction matrix preserves first failure")
    t.check(a.diagnostics().last_error == b.diagnostics().last_error,"invalid/valid direction matrix preserves world error")
