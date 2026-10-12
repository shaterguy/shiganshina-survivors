extends "res://game/world/precise_city_navigation.gd"
# A derived navigation can override a virtual eligibility callback. Field reuse
# must independently reject the unknown implementation before invoking it.
func _direction_reuse_scope() -> Dictionary:
 var source = _world._world
 return {"view":_world,"source":source,"coverage":source._coverage_revision,"revision":source._world_revision,"origin":source._origin.duplicate(),"queries":{}}
