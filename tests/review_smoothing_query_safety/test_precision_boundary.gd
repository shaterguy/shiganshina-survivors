extends RefCounted
const F = preload("res://tests/world/fixtures/city_fixture.gd")
const N = preload("res://game/world/city_navigation.gd")
const O = preload("res://tests/smoothing_shortcut/oracle_navigation.gd")
const V = preload("res://game/world/streamed_navigation_view.gd")
const Cached = preload("res://game/world/cached_streamed_world.gd")
func run(t) -> void:
 var chunks: Array = [["-2","0"],["-1","0"],["0","0"]]
 for cached in [false,true]:
  var a = Cached.new(F.generator(),42) if cached else F.world(chunks)
  var b = Cached.new(F.generator(),42) if cached else F.world(chunks)
  if cached:
   t.check(a.prepare(chunks,[],F.hydration(chunks),["0","0"]).ok,"prepare candidate cache")
   t.check(b.prepare(chunks,[],F.hydration(chunks),["0","0"]).ok,"prepare oracle cache")
  var va = V.new(a)
  var vb = V.new(b)
  var start := Vector2(384,384)
  var points: Array = [Vector2(-1400,384),Vector2(760.0001220703125,384),Vector2(640,384)]
  var before: Dictionary = a.diagnostics().duplicate(true)
  var safe: bool = va.smoothing_queries_safe(start,points,0,8.0)
  t.check(a.diagnostics()==before,"guard remains diagnostic pure")
  var envelope := Rect2(start,Vector2.ZERO)
  var bounds: Array = []
  for p in points:
   var box: Rect2 = a._swept_rect(start,p-start,8.0)
   bounds.append({"x":box.position.x,"w":box.size.x,"end":box.end.x,"covered":a.covered(box)})
   envelope = envelope.merge(box)
  print("PRECISION_DETAILS "+JSON.stringify({"cached":cached,"safe":safe,"bounds":bounds,"envelope":{"x":envelope.position.x,"w":envelope.size.x,"end":envelope.end.x}}))
  t.check(not safe,"inward Rect2 merge must not approve a segment extending into absent x=1 chunk")
  # Reconstruct to avoid the diagnostic effects of introspecting actual covered().
  a = Cached.new(F.generator(),42) if cached else F.world(chunks)
  if cached:a.prepare(chunks,[],F.hydration(chunks),["0","0"])
  va = V.new(a)
  var actual: Array = N.new(va)._smooth(start,points,8.0)
  var expected: Array = O.new(vb)._smooth(start,points,8.0)
  print("PRECISION_RESULTS "+JSON.stringify({"cached":cached,"actual":str(actual),"expected":str(expected),"actual_query_status":va.navigation_query_status(),"expected_query_status":vb.navigation_query_status(),"actual_last_error":a.diagnostics().last_error,"expected_last_error":b.diagnostics().last_error}))
  t.check(actual==expected,"precision boundary keeps route")
  t.check(va.navigation_query_status()==vb.navigation_query_status(),"precision boundary keeps sticky real query failure")
  t.check(a.diagnostics().last_error==b.diagnostics().last_error,"precision boundary keeps last_error")
