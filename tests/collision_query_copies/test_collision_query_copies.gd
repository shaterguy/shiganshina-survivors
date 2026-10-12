extends RefCounted
const F = preload("res://tests/world/fixtures/city_fixture.gd")
const Exact = preload("res://game/world/streamed_world.gd")
const Cached = preload("res://game/world/cached_streamed_world.gd")
class QueryOverride:
	extends "res://game/world/streamed_world.gd"
	var query_calls := 0
	func query_props(aabb: Rect2) -> Array:
		query_calls += 1
		var result := super.query_props(aabb)
		for prop in result: prop.collision_mask = 0; prop.cover_mask = 0
		return result
class CachedQueryOverride:
	extends "res://game/world/cached_streamed_world.gd"
	var query_calls := 0
	func query_props(aabb: Rect2) -> Array:
		query_calls += 1
		var result := super.query_props(aabb)
		for prop in result: prop.collision_mask = 0; prop.cover_mask = 0
		return result
class BoxOverride:
	extends "res://game/world/streamed_world.gd"
	var box_calls := 0
	func _collision_box(prop: Dictionary, radius: float) -> Rect2:
		box_calls += 1
		prop.hp = -123
		return super._collision_box(prop,radius)
class CachedBoxOverride:
	extends "res://game/world/cached_streamed_world.gd"
	var box_calls := 0
	func _collision_box(prop: Dictionary, radius: float) -> Rect2:
		box_calls += 1
		prop.hp = -123
		return super._collision_box(prop,radius)
class WalkableOverride:
	extends "res://game/world/cached_streamed_world.gd"
	var walkable_calls := 0
	func walkable(_position: Vector2, _radius: float) -> bool:
		walkable_calls += 1
		return false
class CoveredOverride:
	extends "res://game/world/cached_streamed_world.gd"
	var coverage_calls := 0
	func covered(aabb: Rect2) -> bool:
		coverage_calls += 1
		if coverage_calls > 1:
			_last_error = "world_not_ready"
			return false
		return super.covered(aabb)
func _world(script):
	var world = script.new(F.generator(),42)
	var chunks := F.neighborhood()
	world.prepare(chunks,[],F.hydration(chunks),["0","0"])
	return world
func run(t) -> void:
	for script in [Exact,Cached]:
		_public_ownership(t,script)
		_borrowed_ownership(t,script)
	for script in [QueryOverride,CachedQueryOverride]:
		var world = _world(script)
		var before: Dictionary = world._props.duplicate(true)
		t.check(world.walkable(Vector2(144,224),8),"derived public query override controls walkable")
		var hit: Dictionary = world.sweep(Vector2(16,200),Vector2(200,0),8)
		t.check(hit.fraction == 1 and hit.hit_prop_id.is_empty(),"derived public query override controls sweep")
		t.check(world.cover_sweep(Vector2(16,200),Vector2(200,0),8,31).fraction == 1,"derived public query override controls cover sweep")
		t.check(world.query_calls == 4 and world.diagnostics().query_count == 4,"virtual query count and diagnostics remain identical")
		t.check(world._props == before,"derived mutation of owned public query cannot change resident geometry")
		if world.has_method("_collision_query_props"):
			var props: Array = world._collision_query_props(Rect2(0,0,768,768))
			t.check(not props.is_empty() and not is_same(props[0],world._props[props[0].prop_id]),"opaque derived internal query still owns its results")
	for script in [BoxOverride,CachedBoxOverride]:
		var world = _world(script)
		var before: Dictionary = world._props.duplicate(true)
		world.sweep(Vector2(16,200),Vector2(200,0),8)
		t.check(world.box_calls > 0 and world._props == before,"derived collision-box callback receives owned dictionaries")
	var walk_override = _world(WalkableOverride)
	var start := Vector2(384,384)
	var walk_result: Dictionary = walk_override.sweep(start,Vector2(8,0),8)
	t.check(walk_result.ok and walk_result.position == start and walk_override.walkable_calls == 2,"sweep preserves both virtual endpoint walkability calls")
	var coverage_override = _world(CoveredOverride)
	var coverage_result: Dictionary = coverage_override.sweep(start,Vector2(8,0),8)
	t.check(coverage_result.ok and coverage_result.position == start and coverage_override.coverage_calls == 3 and coverage_override.diagnostics().last_error == "world_not_ready","sweep preserves endpoint coverage refusal and diagnostics")
func _public_ownership(t,script) -> void:
	var world = _world(script)
	var rect := Rect2(0,0,768,768)
	var first: Array = world.query_props(rect)
	t.check(not first.is_empty(),"ownership fixture selects actual generated props")
	if first.is_empty(): return
	var id: String = first[0].prop_id
	world._props[id]._ownership_fixture = {"items":[{"value":1}]}
	var before: Dictionary = world._props.duplicate(true)
	var props: Array = world.query_props(rect)
	var ids := []
	for prop in props: ids.append(prop.prop_id)
	var sorted: Array = ids.duplicate(); sorted.sort()
	t.check(ids == sorted,"public query preserves deterministic ID sorting")
	props[0]._ownership_fixture.items[0].value = 2
	props[0].hp = -7
	props.clear()
	t.check(world._props == before and world.diagnostics().query_count == 2,"public nested data and result array are caller-owned with exact query count")
func _borrowed_ownership(t,script) -> void:
	var world = _world(script)
	t.check(world.has_method("_collision_query_props"),"exact synchronous collision reads expose the private non-copy path")
	if not world.has_method("_collision_query_props"): return
	var rect := Rect2(0,0,768,768)
	var borrowed: Array = world._collision_query_props(rect)
	t.check(not borrowed.is_empty() and is_same(borrowed[0],world._props[borrowed[0].prop_id]),"exact collision query borrows resident prop dictionaries")
	if borrowed.is_empty(): return
	borrowed[0]._ownership_fixture = {"items":[{"value":1}]}
	var public: Array = world.query_props(rect)
	borrowed[0]._ownership_fixture.items[0].value = 2
	t.check(public[0]._ownership_fixture.items[0].value == 1,"private borrowed mutation cannot affect an already returned public snapshot")
	public[0]._ownership_fixture.items[0].value = 3
	t.check(borrowed[0]._ownership_fixture.items[0].value == 2,"public snapshot mutation never leaks into the borrowed resident path")
	var before: Dictionary = world._props.duplicate(true)
	world.walkable(Vector2(144,224),8)
	world.sweep(Vector2(16,200),Vector2(200,0),8)
	world.cover_sweep(Vector2(16,200),Vector2(200,0),8,31)
	t.check(world._props == before,"synchronous collision readers do not mutate resident dictionaries")
