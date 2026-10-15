extends RefCounted
const N = preload("res://game/world/city_navigation.gd")
const P = preload("res://game/world/precise_city_navigation.gd")
const O = preload("res://tests/navigation_grid_raster/oracle_navigation.gd")
const F = preload("res://tests/world/fixtures/city_fixture.gd")
const V = preload("res://game/world/streamed_navigation_view.gd")
func _check(t, chunk: Dictionary, clearance: int) -> void:
 var before := var_to_bytes(chunk)
 var actual = N.new(null)
 var precise = P.new(null)
 var oracle = O.new(null)
 var expected: Dictionary = oracle._build_grid(chunk,clearance)
 t.check(actual._build_grid(chunk,clearance) == expected,"all 576 flags and grid metadata equal cell-first oracle")
 t.check(precise._build_grid(chunk,clearance) == expected,"precise derived navigation inherits exact raster")
 t.check(actual._grid_builds == 1 and precise._grid_builds == 1 and actual._route_builds == 0,"logical build diagnostics unchanged")
 t.check(var_to_bytes(chunk) == before,"input chunk and props remain unchanged")
func _chunk(origin: Vector2, props: Array) -> Dictionary:
 return {"chunk_id":"arbitrary,key","geometry_revision":17,"local_origin":origin,"props":props}
func _prop(box: Rect2, mask: int = 3) -> Dictionary:
 return {"collision_mask":mask,"ground_footprint":box}
func run(t) -> void:
 for clearance in N.CLASSES:
  for origin in [Vector2.ZERO,Vector2(-768,1536),Vector2(-49152,49152),Vector2(0.125,-0.25),Vector2(16777216,-16777216)]:
   _check(t,_chunk(origin,[]),clearance)
   _check(t,_chunk(origin,[_prop(Rect2(origin-Vector2(64,64),Vector2(896,896)))]),clearance)
   var props: Array = []
   for i in 24:
    var center: Vector2 = N._center(i*24+i,origin)
    # Expanded left/top or right/bottom lies exactly on a cell center;
    # near-boundary cases retain the original Vector2 rounding.
    for epsilon in [-0.0001220703125,0.0,0.0001220703125,0.5]:
     props.append(_prop(Rect2(center+Vector2(clearance+epsilon,clearance+epsilon),Vector2(32.25,47.75)),1<<(i%5)))
     props.append(_prop(Rect2(center-Vector2(clearance+32.25+epsilon,clearance+47.75+epsilon),Vector2(32.25,47.75)),3))
   props.append(_prop(Rect2(origin,Vector2(768,768)),0))
   props.append(_prop(Rect2(origin+Vector2(400,400),Vector2(-32,-64)),3))
   props.append(_prop(Rect2(origin+Vector2(16,16),Vector2.ZERO),8))
   _check(t,_chunk(origin,props),clearance)
   props.reverse()
   _check(t,_chunk(origin,props),clearance)
 # Nonfinite rectangle coordinates retain IEEE comparison behavior.
 for box in [Rect2(Vector2(NAN,16),Vector2(32,32)),Rect2(Vector2(INF,16),Vector2(32,32)),Rect2(Vector2(-INF,16),Vector2(INF,32)),Rect2(Vector2(16,16),Vector2(NAN,32))]:
  _check(t,_chunk(Vector2.ZERO,[_prop(box)]),8)
 # Deterministic overlapping/random geometry uses its own RNG; gameplay RNG untouched.
 var rng := RandomNumberGenerator.new()
 rng.seed = 824601
 for sample in 24:
  var origin := Vector2((sample-12)*768,(12-sample)*768)
  var props: Array = []
  for i in 40:
   var point := origin+Vector2(rng.randf_range(-100,900),rng.randf_range(-100,900))
   var size := Vector2(rng.randf_range(0,220),rng.randf_range(0,220))
   props.append(_prop(Rect2(point,size),i%6))
  for clearance in N.CLASSES: _check(t,_chunk(origin,props),clearance)
 # Actual generated, localized, and damaged stream geometry.
 var world = F.world(F.neighborhood())
 var view = V.new(world)
 for key in view.chunk_keys():
  for clearance in N.CLASSES: _check(t,view.localized_chunk(key),clearance)
 var changes: Array = []
 for prop in world.localized_chunk("0,0").props:
  if prop.destructible: changes.append({"slot_id":prop.slot_id,"hp":0,"destroyed":true})
 t.check(world.apply_props([{"chunk":["0","0"],"props":changes}],1).ok,"dirty geometry application")
 for clearance in N.CLASSES: _check(t,view.localized_chunk("0,0"),clearance)
 t.check(world.prepare(F.neighborhood(),[],F.hydration(F.neighborhood()),["1","0"]).ok,"ordinary origin localization")
 for key in view.chunk_keys():
  for clearance in N.CLASSES: _check(t,view.localized_chunk(key),clearance)
