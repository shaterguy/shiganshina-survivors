extends "res://game/core/run_simulation.gd"
## QA-only inclusive stage timers. Counters never enter simulation authority.
## This derived script may take a different get_script() normalization path.
## Its total is diagnostic only; use the original Core for baseline total cost.
const TIMER_STAGES := ["move_player","move_enemies","move_waiting_roles","admit_role_attacks","auto_attack","auto_signature","execute_player_attacks","advance_projectiles","player_damage"]
var timer_us: Dictionary = {}
var timer_calls: Dictionary = {}

func begin_timer_tick() -> void:
	timer_us.clear()
	timer_calls.clear()
	for stage in TIMER_STAGES:
		timer_us[stage] = 0
		timer_calls[stage] = 0

func _timer_finish(stage: String, started: int) -> void:
	var elapsed := Time.get_ticks_usec()-started
	timer_us[stage] = int(timer_us.get(stage,0))+elapsed
	timer_calls[stage] = int(timer_calls.get(stage,0))+1

func _move_player(state: Dictionary, input: Vector2) -> void:
	var started := Time.get_ticks_usec()
	super._move_player(state,input)
	_timer_finish("move_player",started)

func _move_enemies(state: Dictionary, events: Array[Dictionary]) -> Array[int]:
	var started := Time.get_ticks_usec()
	var result := super._move_enemies(state,events)
	_timer_finish("move_enemies",started)
	return result

func _move_waiting_roles(state: Dictionary, indices: Array[int]) -> void:
	var started := Time.get_ticks_usec()
	super._move_waiting_roles(state,indices)
	_timer_finish("move_waiting_roles",started)

func _admit_role_attacks(state: Dictionary, events: Array[Dictionary]) -> void:
	var started := Time.get_ticks_usec()
	super._admit_role_attacks(state,events)
	_timer_finish("admit_role_attacks",started)

func _auto_attack(state: Dictionary, events: Array[Dictionary], boss_rewards: Array[Dictionary]) -> void:
	var started := Time.get_ticks_usec()
	super._auto_attack(state,events,boss_rewards)
	_timer_finish("auto_attack",started)

func _auto_signature(state: Dictionary, events: Array[Dictionary]) -> void:
	var started := Time.get_ticks_usec()
	super._auto_signature(state,events)
	_timer_finish("auto_signature",started)

func _execute_player_attacks(state: Dictionary, events: Array[Dictionary], boss_rewards: Array[Dictionary]) -> void:
	var started := Time.get_ticks_usec()
	super._execute_player_attacks(state,events,boss_rewards)
	_timer_finish("execute_player_attacks",started)

func _advance_projectiles(state: Dictionary, events: Array[Dictionary], boss_rewards: Array[Dictionary], existing: Dictionary) -> void:
	var started := Time.get_ticks_usec()
	super._advance_projectiles(state,events,boss_rewards,existing)
	_timer_finish("advance_projectiles",started)

func _player_damage(state: Dictionary, events: Array[Dictionary]) -> void:
	var started := Time.get_ticks_usec()
	super._player_damage(state,events)
	_timer_finish("player_damage",started)
