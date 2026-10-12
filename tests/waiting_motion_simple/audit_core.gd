extends "res://game/core/run_simulation.gd"
const HashCheck = preload("res://game/combat/spatial_hash.gd")
var audit := {"calls":0,"world_moves":0,"attempt_histogram":{},"hash_failures":[],"rows":[],"axis_clipped":0}
var in_wait := false
var moves := []
func _move_world(state: Dictionary, point: Vector2, delta: Vector2, radius: float, swept: bool = false) -> Vector2:
	var result := super._move_world(state,point,delta,radius,swept)
	if in_wait:
		audit.world_moves += 1
		moves.append({"requested":_array(point+delta),"actual":_array(result),"delta":_array(delta),"radius":radius})
		if result.distance_to(point+delta)>.0001: audit.axis_clipped += 1
	return result
func _move_waiting_role(state: Dictionary, entity: Dictionary, profile: Dictionary) -> void:
	var before := _vec(entity.position)
	in_wait=true; moves=[]
	super._move_waiting_role(state,entity,profile)
	in_wait=false
	var after := _vec(entity.position)
	audit.calls += 1
	audit.attempt_histogram[str(moves.size())] = int(audit.attempt_histogram.get(str(moves.size()),0))+1
	var pairs := []
	for other_index in state.entities.size():
		if str(state.entities[other_index].id)==str(entity.id): continue
		var other: Dictionary = state.entities[other_index]
		if other.hp<=0: continue
		var sum_radius := float(entity.radius)+float(other.radius)
		var center := _vec(other.position)
		pairs.append({"id":str(other.id),"before":maxf(0.0,sum_radius-before.distance_to(center)),"after":maxf(0.0,sum_radius-after.distance_to(center))})
	audit.rows.append({"tick":state.active_tick,"id":str(entity.id),"before":_array(before),"after":_array(after),"moves":moves.duplicate(true),"pairs":pairs})
func _move_waiting_roles(state: Dictionary, indices: Array[int]) -> void:
	super._move_waiting_roles(state,indices)
	var expected = HashCheck.new(); expected.rebuild(state.entities)
	var actual: Dictionary = _spatial.cells.duplicate(true)
	for key in actual: actual[key].sort()
	if actual!=expected.cells: audit.hash_failures.append(state.active_tick)
