extends RefCounted
const CoreFixture = preload("res://tests/core/new_current_regression_fixture.gd")
const IDS := ["walker","runner","brute","sweeper","grabber","boss_charger","boss_sweeper","boss_leaper","boss_grabber","boss_abnormal"]
static func chapter() -> Dictionary:
	return CoreFixture.chapter()
static func run_with_enemy(sim, enemy_id: String, position := [-160.0,0.0]) -> Dictionary:
	var state: Dictionary = sim.new_run(chapter(),44,CoreFixture.run_config())
	state.equipment.clear()
	# Long trajectory checks must retain a living player, without inventing HP.
	state.player.invulnerable_until = 200000
	CoreFixture.step(sim,state,Vector2.ZERO,[CoreFixture.actor_command(state,enemy_id,position)])
	return state
static func until_action(sim,state: Dictionary,action: String,limit := 800) -> bool:
	for index in limit:
		if state.entities.is_empty(): return false
		if state.entities[0].get("action_state","") == action: return true
		CoreFixture.step(sim,state,Vector2.ZERO,[])
	return false
static func vec(values: Array) -> Vector2:
	return Vector2(values[0],values[1])
