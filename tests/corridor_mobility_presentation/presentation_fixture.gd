extends RefCounted
# Share the real Core corridor setup; keep presentation-specific convenience
# helpers out of the production schema and the legacy migration fixture.
const Corridor = preload("res://tests/corridor_mobility/corridor_fixture.gd")
const LegacyFixture = preload("res://tests/terrain_mobility/motion_fixture.gd")
const Core = LegacyFixture.Core
const H = LegacyFixture.H
const HF = LegacyFixture.HF
const F = LegacyFixture.F
const PATH = LegacyFixture.PATH
static func make(t) -> Dictionary: return Corridor.make(t)
static func available(t) -> bool: return LegacyFixture.available(t)
static func step(s: Dictionary,direction := Vector2.UP,commands: Array = []) -> Array[Dictionary]: return Corridor.step(s,direction,commands)
static func reach(s: Dictionary,phase: String) -> bool:
	for tick in 64:
		if s.state.player_mobility.phase == phase: return true
		step(s)
	return false
static func vec(value: Array) -> Vector2: return Vector2(value[0],value[1])
static func same(a: Variant,b: Variant) -> bool: return H._same_json(a,b)
