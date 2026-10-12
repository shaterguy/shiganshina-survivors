extends "res://game/core/run_simulation.gd"
var batches: Array = []
var inside_batch := false
var current_batch := {}
func _move_waiting_roles(state: Dictionary, indices: Array[int]) -> void:
	inside_batch=true
	current_batch={"calls":{},"profiles":{},"uses":{},"mutated":false,"waiters":indices.size()}
	super._move_waiting_roles(state,indices)
	inside_batch=false
	batches.append(current_batch)
func _role_profile(enemy_id: String) -> Dictionary:
	var profile := super._role_profile(enemy_id)
	if inside_batch:
		current_batch.calls[enemy_id]=int(current_batch.calls.get(enemy_id,0))+1
		current_batch.profiles[enemy_id]=profile
	return profile
func _move_waiting_role(state: Dictionary, entity: Dictionary, profile: Dictionary) -> void:
	var before: Dictionary = profile.duplicate(true)
	if not current_batch.uses.has(entity.enemy_id): current_batch.uses[entity.enemy_id]=[]
	current_batch.uses[entity.enemy_id].append(profile)
	super._move_waiting_role(state,entity,profile)
	current_batch.mutated = current_batch.mutated or profile!=before
