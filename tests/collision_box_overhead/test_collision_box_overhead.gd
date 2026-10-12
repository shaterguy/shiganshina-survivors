extends RefCounted
const F = preload("res://tests/world/fixtures/city_fixture.gd")
const Exact = preload("res://game/world/streamed_world.gd")
const Cached = preload("res://game/world/cached_streamed_world.gd")
class GeometryOverride:
	extends "res://game/world/streamed_world.gd"
	var box_calls := 0
	func _collision_box(prop: Dictionary,radius: float) -> Rect2:
		box_calls += 1
		prop.ground_footprint = prop.ground_footprint.grow(float(box_calls%3))
		return super._collision_box(prop,radius)
class LegacyBox:
	static func box(world,prop: Dictionary,radius: float) -> Rect2:
		# Frozen baseline _collision_box body; test oracle only.
		if not radius in [8.0,16.0,18.0,20.0,24.0,28.0,30.0,32.0]: return prop.ground_footprint.grow(radius)
		var key: String = "%s:%d" % [prop.chunk_id,int(radius)]
		if not world._clearance_cache.has(key): world._clearance_cache[key] = {"chunk_id":prop.chunk_id,"revision":prop.geometry_revision,"origin":world._origin.duplicate(),"boxes":{}}
		var boxes: Dictionary = world._clearance_cache[key].boxes
		if not boxes.has(prop.prop_id): boxes[prop.prop_id] = prop.ground_footprint.grow(radius)
		return boxes[prop.prop_id]
class LegacyExact:
	extends "res://game/world/streamed_world.gd"
	func _collision_box(prop: Dictionary,radius: float) -> Rect2:
		return LegacyBox.box(self,prop,radius)
class LegacyCached:
	extends "res://game/world/cached_streamed_world.gd"
	func _collision_box(prop: Dictionary,radius: float) -> Rect2:
		return LegacyBox.box(self,prop,radius)
class LegacyGeometryOverride:
	extends "res://game/world/streamed_world.gd"
	var box_calls := 0
	func _collision_box(prop: Dictionary,radius: float) -> Rect2:
		box_calls += 1
		prop.ground_footprint = prop.ground_footprint.grow(float(box_calls%3))
		return LegacyBox.box(self,prop,radius)
class CachedGeometryOverride:
	extends "res://game/world/cached_streamed_world.gd"
	var box_calls := 0
	func _collision_box(prop: Dictionary,radius: float) -> Rect2:
		box_calls += 1
		prop.ground_footprint = prop.ground_footprint.grow(float(box_calls%3))
		return super._collision_box(prop,radius)
class LegacyCachedGeometryOverride:
	extends "res://game/world/cached_streamed_world.gd"
	var box_calls := 0
	func _collision_box(prop: Dictionary,radius: float) -> Rect2:
		box_calls += 1
		prop.ground_footprint = prop.ground_footprint.grow(float(box_calls%3))
		return LegacyBox.box(self,prop,radius)
func _world(script):
	var world = script.new(F.generator(),42)
	var chunks := F.neighborhood()
	world.prepare(chunks,[],F.hydration(chunks),["0","0"])
	return world
func run(t) -> void:
	for script in [Exact,Cached]:
		var world = _world(script)
		var oracle = _world(LegacyExact if script==Exact else LegacyCached)
		var before: Dictionary = world._props.duplicate(true)
		for radius in [0.0,7.999999,8.0,8.000001,15.999999,16.0,16.000001,18.0,20.0,22.0,24.0,28.0,30.0,31.999999,32.0]:
			for prop in world._props.values():
				t.check(world._collision_box(prop,radius)==prop.ground_footprint.grow(radius),"exact collision box equals direct float growth")
			for position in [Vector2(16,200),Vector2(144-radius,224),Vector2(144-radius-0.0001,224),Vector2(144-radius+0.0001,224)]:
				t.check(world.sweep(position,Vector2(200,0),radius)==oracle.sweep(position,Vector2(200,0),radius),"exact float contact/endpoints match frozen cache oracle")
				t.check(world.cover_sweep(position,Vector2(200,0),radius,31)==oracle.cover_sweep(position,Vector2(200,0),radius,31),"exact float cover/mask results match frozen cache oracle")
			t.check(world.diagnostics().clearance_cache_entries==0,"exact worlds retain no expanded collision boxes")
		t.check(world._props==before,"direct exact growth never mutates resident dictionaries")
	for pair in [[GeometryOverride,LegacyGeometryOverride],[CachedGeometryOverride,LegacyCachedGeometryOverride]]:
		var derived = _world(pair[0])
		var legacy = _world(pair[1])
		for index in 12:
			var a: Dictionary = derived.sweep(Vector2(16,200),Vector2(200,0),8)
			var b: Dictionary = legacy.sweep(Vector2(16,200),Vector2(200,0),8)
			t.check(a==b and derived.box_calls==legacy.box_calls,"derived geometry callback retains legacy repeated-ID memoization")
		t.check(derived.diagnostics()==legacy.diagnostics(),"derived callback preserves all legacy diagnostics")
