extends RefCounted
const F=preload("res://tests/world/fixtures/city_fixture.gd")
const Navigation=preload("res://game/world/city_navigation.gd")
const View=preload("res://game/world/streamed_navigation_view.gd")
func run(t) -> void:
 var world=F.world(F.neighborhood())
 var nav=Navigation.new(View.new(world))
 var start:=Vector2(384,384)
 var points:Array=[]
 for x in range(400,641,16):points.append(Vector2(x,384))
 var before:int=world.diagnostics().query_count
 var actual:Array=nav._smooth(start,points,8)
 var queries:int=world.diagnostics().query_count-before
 t.check(actual==[points[-1]],"clear straight smoothing chooses exact farthest waypoint")
 t.check(queries<=2,"clear smoothing uses one authoritative sweep, not every intermediate point (actual spatial queries=%d)"%queries)
