extends RefCounted
const F = preload("res://tests/world/fixtures/city_fixture.gd")
const N = preload("res://game/world/precise_city_navigation.gd")
const O = preload("res://tests/direction_los_reuse/oracle_precise_navigation.gd")
const V = preload("res://game/world/streamed_navigation_view.gd")
const Cached = preload("res://game/world/cached_streamed_world.gd")
const A := Vector2(496,194)
const B := Vector2(1152,384)
func _world():
 var w = Cached.new(F.generator(),42)
 w.prepare(F.neighborhood(),[],F.hydration(F.neighborhood()),["0","0"])
 return w
func run(t) -> void:
 var w = _world(); var v = V.new(w); var n = N.new(v)
 var oracle = O.new(V.new(_world()))
 var expected: Dictionary = oracle.direction(A,B,8,0)
 t.check(expected.ok,"obstructed cross-chunk fixture has route")
 for i in 2: t.check(n.direction(A,B,8,0) == expected,"warm exact route before counter check")
 var before: int = w.diagnostics().query_count
 t.check(n.direction(A,B,8,0) == expected,"same-tick repeat preserves every waypoint/direction/length")
 var repeated: int = w.diagnostics().query_count-before
 t.check(repeated == 2,"same-tick route reuses successful LOS and still validates both endpoint walkabilities; got "+str(repeated))
 before = w.diagnostics().query_count
 t.check(n.direction(A,B,8,1) == oracle.direction(A,B,8,1),"new tick remains exact")
 t.check(w.diagnostics().query_count-before == 2,"new tick reuses static LOS and rechecks endpoint walkability")
 before = w.diagnostics().query_count
 t.check(n.direction(A,B,8,0) == oracle.direction(A,B,8,0),"rewound tick remains exact")
 t.check(w.diagnostics().query_count-before > 2,"tick rewind discards prior memo")
 # Reuse must never cross real geometry or coordinate-space publication.
 var changes: Array = []
 for prop in w.localized_chunk("0,0").props:
  if prop.destructible: changes.append({"slot_id":prop.slot_id,"hp":0,"destroyed":true})
 t.check(w.apply_props([{"chunk":["0","0"],"props":changes}],1).ok,"terrain mutation publishes")
 t.check(n.direction(A,B,8,0) == O.new(V.new(w)).direction(A,B,8,0),"same-tick terrain change retires memo")
 t.check(w.prepare(F.neighborhood(),[],F.hydration(F.neighborhood()),["1","0"]).ok,"same-tick rebase publishes")
 t.check(n.direction(A,B,8,0) == O.new(V.new(w)).direction(A,B,8,0),"same-tick origin/coverage change retires memo")
 var restored = _world()
 v._world = restored
 t.check(n.direction(A,B,8,0) == O.new(V.new(restored)).direction(A,B,8,0),"replacement world cannot reuse old same-revision geometry")
 _bounded_memo(t)
func _bounded_memo(t) -> void:
 var w = _world(); var n = N.new(V.new(w))
 var success := true
 # Distinct exactly representable endpoints in one unobstructed street.
 for i in 4100:
  var a := Vector2(384.0+float(i)/128.0,384)
  var result: Dictionary = n.direction(a,Vector2(640,384),8,10)
  success = success and result.ok and result.direction == Vector2.RIGHT and result.waypoints == [Vector2(640,384)]
 t.check(success,"cache capacity never defers or changes actual routing")
 t.check(n._tick_los.queries.size() == n.MAX_TICK_LOS,"same-tick LOS memory is bounded")
 var before: int = w.diagnostics().query_count
 n.direction(Vector2(384,384),Vector2(640,384),8,10)
 t.check(w.diagnostics().query_count-before == 2,"bounded memo retains earlier exact success")
 before = w.diagnostics().query_count
 n.direction(Vector2(384.0+4099.0/128.0,384),Vector2(640,384),8,10)
 t.check(w.diagnostics().query_count-before > 2,"capacity falls back to authoritative collision, never unchecked motion")
 n.direction(Vector2(384,384),Vector2(640,384),8,11)
 t.check(n._tick_los.queries.size() == 1,"a full memo rolls over at the next tick to preserve fresh same-tick reuse")
 var fresh := Vector2(416.0625,384)
 before = w.diagnostics().query_count
 n.direction(fresh,Vector2(640,384),8,11)
 t.check(w.diagnostics().query_count-before > 2,"new observation remains authoritative after rollover")
 before = w.diagnostics().query_count
 n.direction(fresh,Vector2(640,384),8,11)
 t.check(w.diagnostics().query_count-before == 2,"new observations can still seed useful same-tick reuse after rollover")
