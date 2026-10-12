extends RefCounted
const F=preload("res://tests/world/fixtures/city_fixture.gd")
const N=preload("res://game/world/city_navigation.gd")
const O=preload("res://tests/smoothing_shortcut/oracle_navigation.gd")
const V=preload("res://game/world/streamed_navigation_view.gd")
const Opaque=preload("res://tests/review_smoothing_query_safety/opaque_view.gd")
func run(t) -> void:
 _opaque(t)
 _preexisting_error(t)
 _safe_implication(t)
 _invalid_arguments(t)
func _opaque(t) -> void:
 var a=Opaque.new(F.world(F.neighborhood()))
 var b=Opaque.new(F.world(F.neighborhood()))
 var points:Array=[Vector2(400,384),Vector2(500,384),Vector2(640,384)]
 var expected:Array=O.new(b)._smooth(Vector2(384,384),points,8.01)
 var actual:Array=N.new(a)._smooth(Vector2(384,384),points,8.01)
 t.check(actual==expected,"opaque derived view preserves exact route")
 t.check(a.sweep_calls==b.sweep_calls,"opaque derived view preserves full authoritative argument order")
 t.check(a.navigation_query_status()==b.navigation_query_status() and not a.navigation_query_status().ok,"opaque derived view retains omitted second-query failure")
func _preexisting_error(t) -> void:
 var a=V.new(F.world(F.neighborhood()))
 var b=V.new(F.world(F.neighborhood()))
 for v in [a,b]:v.sweep(Vector2(384,384),Vector2(100000,0),8)
 var before:Dictionary=a.navigation_query_status()
 t.check(not a.smoothing_queries_safe(Vector2(384,384),[Vector2(640,384)],0,8),"sticky preexisting failure disables shortcut")
 t.check(a.navigation_query_status()==before,"pure guard never resets first error")
 var points:Array=[Vector2(400,384),Vector2(640,384)]
 t.check(N.new(a)._smooth(Vector2(384,384),points,8)==O.new(b)._smooth(Vector2(384,384),points,8),"preexisting failure route remains exact")
 t.check(a.navigation_query_status()==b.navigation_query_status() and a.navigation_query_status()==before,"preexisting failure stays first after later successes")
 a.begin_navigation_queries()
 t.check(a.navigation_query_status().ok,"only explicit batch start clears latch")
func _safe_implication(t) -> void:
 var chunks:Array=[]
 for y in range(-3,1):
  for x in range(-3,1):chunks.append([str(x),str(y)])
 var world=F.world(chunks)
 var view=V.new(world)
 for axis in 2:
  for radius in [0.0,0.00002,8.0,8.01,16.0,24.0,32.0]:
   for epsilon in [-0.000244140625,-0.0001220703125,0.0,0.00006103515625,0.0001220703125,0.000244140625]:
    for far in [-512.0,-1400.0,-2200.0]:
     var start:=Vector2(384,384)
     var boundary:=Vector2(640,640)
     boundary[axis]=768.0-radius+epsilon
     var left:=Vector2(384,384)
     left[axis]=far
     var points:Array=[left,boundary,Vector2(640,384)]
     var before:Dictionary=world.diagnostics()
     var safe:bool=view.smoothing_queries_safe(start,points,0,radius)
     t.check(world.diagnostics()==before and view.navigation_query_status().ok,"matrix guard has no world/latch side effects")
     var exact:=true
     for point in points:
      if not world._valid_query(start,point-start,radius) or not world.covered(world._swept_rect(start,point-start,radius)):exact=false
     t.check(not safe or exact,"approved domain implies every actual sweep argument/coverage guard succeeds axis=%d r=%.8f epsilon=%.9f far=%.2f"%[axis,radius,epsilon,far])
func _invalid_arguments(t) -> void:
 var w=F.world(F.neighborhood())
 var v=V.new(w)
 for start in [Vector2(384,384),Vector2(NAN,0),Vector2(INF,0),Vector2(49153,0)]:
  for radius in [-1.0,0.0,8.01,32.0,33.0,NAN,INF]:
   var target:=Vector2(640,384)
   var before:Dictionary=w.diagnostics()
   var safe:bool=v.smoothing_queries_safe(start,[target],0,radius)
   var valid:bool=w._valid_query(start,target-start,radius)
   t.check(not safe or valid,"invalid source/radius cannot enter reordered path")
   t.check(before==w.diagnostics() and v.navigation_query_status().ok,"invalid source/radius rejection remains pure")
 t.check(not v.smoothing_queries_safe(Vector2(384,384),[],0,8),"empty remaining path is conservatively rejected")
 t.check(not v.smoothing_queries_safe(Vector2(384,384),[Vector2(640,384)],-1,8),"negative first index is rejected")
 t.check(not v.smoothing_queries_safe(Vector2(384,384),[Vector2(640,384)],1,8),"first beyond path is rejected")
 t.check(not v.smoothing_queries_safe(Vector2(384,384),["bad",Vector2(640,384)],0,8),"unknown waypoint type is rejected")
 t.check(v.smoothing_queries_safe(Vector2(384,384),["bad",Vector2(640,384)],1,8),"retired earlier waypoints do not pollute remaining query domain")
