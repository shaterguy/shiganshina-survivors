extends "res://game/world/streamed_world.gd"
# Test-only instrumentation around the real recovered implementation.
var localized_calls := 0
var render_calls := 0
var sweep_calls := 0
var walkable_calls := 0
var sampled_static_peak := 0
func localized_chunk(key: String) -> Dictionary:
	localized_calls += 1
	var result: Dictionary = super.localized_chunk(key)
	sampled_static_peak = maxi(sampled_static_peak,OS.get_static_memory_usage())
	return result
func render_view() -> Dictionary:
	render_calls += 1
	return super.render_view()
func sweep(position: Vector2, delta: Vector2, radius: float) -> Dictionary:
	sweep_calls += 1
	return super.sweep(position,delta,radius)
func walkable(position: Vector2, radius: float) -> bool:
	walkable_calls += 1
	return super.walkable(position,radius)
