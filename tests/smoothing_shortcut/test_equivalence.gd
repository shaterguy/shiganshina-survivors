extends RefCounted
const F=preload("res://tests/world/fixtures/city_fixture.gd")
const N=preload("res://game/world/city_navigation.gd")
const O=preload("res://tests/smoothing_shortcut/oracle_navigation.gd")
const V=preload("res://game/world/streamed_navigation_view.gd")
const Cached=preload("res://game/world/cached_streamed_world.gd")
const Failing=preload("res://tests/smoothing_shortcut/failing_stream.gd")
func run(t) -> void:
 _safe_domain_is_pure(t)
 _coverage_edges(t)
 _conservative_envelope(t)
 _errors(t)
 _unknown_world(t)
 _routes(t)
func _safe_domain_is_pure(t):
 for cached in [false,true]:
  var w=Cached.new(F.generator(),42) if cached else F.world(F.neighborhood())
  if cached:w.prepare(F.neighborhood(),[],F.hydration(F.neighborhood()),["0","0"])
  var v=V.new(w)
  for pair in [[Vector2(384,384),[Vector2(640,384)],8.0,true],[Vector2(384,384),[Vector2(100000,384)],8.0,false],[Vector2(384,384),[Vector2(640,384)],33.0,false],[Vector2(384,384),[Vector2(3000,384)],8.0,false],[Vector2(384,384),[Vector2(640,384)],8.01,true]]:
   var before:Dictionary=w.diagnostics().duplicate(true)
   var query_before:Dictionary=v.navigation_query_status()
   var cache_before:Dictionary=w.coverage_cache_stats() if cached else {}
   t.check(v.smoothing_queries_safe(pair[0],pair[1],0,pair[2])==pair[3],"exact-domain safe/unsafe check")
   t.check(w.diagnostics()==before and v.navigation_query_status()==query_before,"domain precheck preserves all world diagnostics and error latch")
   t.check(not cached or w.coverage_cache_stats()==cache_before,"domain precheck does not mutate coverage-cache counters")
func _compare_smooth(t,points:Array,radius:float,label:String,chunks:Array=[["0","0"]]):
 var a=F.world(chunks);var b=F.world(chunks)
 var va=V.new(a);var vb=V.new(b)
 var actual:Array=N.new(va)._smooth(Vector2(384,384),points,radius)
 var expected:Array=O.new(vb)._smooth(Vector2(384,384),points,radius)
 t.check(actual==expected,label+": exact waypoints")
 t.check(va.navigation_query_status()==vb.navigation_query_status(),label+": first real query failure unchanged")
 t.check(a.diagnostics().last_error==b.diagnostics().last_error,label+": last_error unchanged")
 if not va.navigation_query_status().get("ok",false):t.check(a.diagnostics().query_count==b.diagnostics().query_count,label+": unsafe queries use exact original sweep sequence")
func _errors(t):
 _compare_smooth(t,[Vector2(1152,384),Vector2(640,384)],8,"missing coverage before later visible success")
 _compare_smooth(t,[Vector2(100000,384),Vector2(640,384)],8,"invalid delta before later visible success")
 _compare_smooth(t,[Vector2(1152,384),Vector2(100000,384),Vector2(640,384)],8,"coverage failure precedes invalid query")
 _compare_smooth(t,[Vector2(100000,384),Vector2(1152,384),Vector2(640,384)],8,"invalid query precedes coverage failure")
 _compare_smooth(t,[Vector2(640,384)],33,"unsupported exact radius")
 _compare_smooth(t,[Vector2(640,384)],8.01,"nonclass exact radius remains physical")
 _compare_smooth(t,[],8,"empty path")
 _compare_smooth(t,[Vector2(384,384),Vector2(384,384)],0,"zero-radius point and duplicate endpoint")
func _unknown_world(t):
 var a=Failing.new(F.generator(),42);var b=Failing.new(F.generator(),42)
 for w in [a,b]:w.prepare(F.neighborhood(),[],F.hydration(F.neighborhood()),["0","0"])
 var va=V.new(a);var vb=V.new(b)
 var points:Array=[Vector2(400,384),Vector2(480,384),Vector2(640,384)]
 t.check(not va.smoothing_queries_safe(Vector2(384,384),points,0,8),"custom sweep implementations stay on original forward path")
 t.check(N.new(va)._smooth(Vector2(384,384),points,8)==O.new(vb)._smooth(Vector2(384,384),points,8),"custom failure preserves exact selected path")
 t.check(va.navigation_query_status()==vb.navigation_query_status() and va.navigation_query_status().error_code=="future_injected_sweep_failure","opaque future sweep error remains visible even after later success")
 t.check(a.sweep_calls==b.sweep_calls,"opaque world gets exact original authoritative query count")
func _routes(t):
 var a=F.world(F.neighborhood());var b=F.world(F.neighborhood())
 var va=V.new(a);var vb=V.new(b);var na=N.new(va);var nb=O.new(vb)
 for radius in [8.0,8.01,16.0,18.0,20.0,24.0,28.0,30.0,32.0]:
  for pair in [[Vector2(432,194),Vector2(1152,384)],[Vector2(384,384),Vector2(640,384)],[Vector2(100,100),Vector2(384,384)],[Vector2(672,762),Vector2(384,384)]]:
   for tick in [0,1,12,2]:
    va.begin_navigation_queries();vb.begin_navigation_queries()
    var actual:Dictionary=na.direction(pair[0],pair[1],radius,tick)
    var expected:Dictionary=nb.direction(pair[0],pair[1],radius,tick)
    if pair[0]==Vector2(432,194):
     t.check(actual.ok and expected.ok and not actual.waypoints.is_empty(),"obstructed smoothing fixture executes successful nonempty routing")
    t.check(actual==expected,"clear/obstructed/blocked routes exact across radius and cache age")
    t.check(va.navigation_query_status()==vb.navigation_query_status(),"route error state exact")
 var changes:Array=[]
 for prop in a.localized_chunk("0,0").props:
  if prop.destructible:changes.append({"slot_id":prop.slot_id,"hp":0,"destroyed":true})
 for w in [a,b]:t.check(w.apply_props([{"chunk":["0","0"],"props":changes}],1).ok,"real geometry destruction applies")
 for radius in [8.0,24.0,32.0]:t.check(na.direction(Vector2(432,194),Vector2(1152,384),radius,20)==nb.direction(Vector2(432,194),Vector2(1152,384),radius,20),"geometry change invalidates route identically")
 var rebased:Array=[]
 for y in range(-1,2):
  for x in range(0,3):rebased.append([str(x),str(y)])
 for w in [a,b]:t.check(w.prepare(rebased,[],F.hydration(rebased),["1","0"]).ok,"real coverage and origin rebase")
 for radius in [8.0,24.0,32.0]:
  t.check(na.direction(Vector2(432,194)-Vector2(768,0),Vector2(384,384),radius,21)==nb.direction(Vector2(432,194)-Vector2(768,0),Vector2(384,384),radius,21),"rebased physical route remains exact")
  t.check(na.direction(Vector2(432,194),Vector2(1152,384),radius,22)==nb.direction(Vector2(432,194),Vector2(1152,384),radius,22),"same local coordinates after rebase use current world")

func _coverage_edges(t):
 var w=F.world(F.neighborhood())
 var v=V.new(w)
 var sources:Array=[Vector2(0,0),Vector2(384,384),Vector2(-768,384),Vector2(768,384),Vector2(767.9999,384),Vector2(768.0001,384)]
 var targets:Array=[Vector2(-768,384),Vector2(1536,384),Vector2(1535.9999,384),Vector2(1536.0001,384),Vector2(384,1536),Vector2(384,-768),Vector2(384,384)]
 for source in sources:
  for target in targets:
   for radius in [0.0,8.0,24.0,32.0]:
    var before:Dictionary=w.diagnostics().duplicate(true)
    var actual:bool=v.smoothing_queries_safe(source,[target],0,radius)
    t.check(w.diagnostics()==before,"edge precheck is diagnostic-pure")
    var expected:bool=w._valid_query(source,target-source,radius) and w.covered(w._swept_rect(source,target-source,radius))
    t.check(actual==expected,"edge/point/half-open coverage equals actual sweep guard")
 var large_chunks:Array=[]
 var origin:Array=["9007199254740993","-9007199254740993"]
 var Address=preload("res://game/world/world_address.gd")
 for y in range(-1,2):
  for x in range(-1,2):large_chunks.append(Address.normalize(origin,Vector2(x*768,y*768)).chunk)
 var big=F.world(large_chunks,origin)
 var big_view=V.new(big)
 var before_big:Dictionary=big.diagnostics().duplicate(true)
 t.check(big_view.smoothing_queries_safe(Vector2(384,384),[Vector2(640,384)],0,8),"pure existing view preserves exact int64 world addresses")
 t.check(big.diagnostics()==before_big,"large-address precheck remains pure")

func _conservative_envelope(t):
 var chunks:Array=[["0","0"],["1","0"],["0","1"]]
 var world=F.world(chunks)
 var view=V.new(world)
 var before:Dictionary=world.diagnostics().duplicate(true)
 var points:Array=[Vector2(1152,384),Vector2(384,1152)]
 t.check(not view.smoothing_queries_safe(Vector2(384,384),points,0,8),"missing unused envelope corner conservatively keeps forward path")
 t.check(world.diagnostics()==before and view.navigation_query_status().ok,"conservative envelope rejection introduces no fake geometry failure")
 _compare_smooth(t,points,8,"L-shaped coverage fallback retains same real geometry observations",chunks)
