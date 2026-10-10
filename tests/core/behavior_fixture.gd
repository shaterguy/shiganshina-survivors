extends RefCounted
const CoreFixture = preload("res://tests/core/core_fixture.gd")
const IDS := ["walker","runner","brute","sweeper","grabber","boss_charger","boss_sweeper","boss_leaper","boss_grabber","boss_abnormal"]
static func chapter() -> Dictionary:
	var value: Dictionary = CoreFixture.chapter()
	value.initial_equipment = {}
	value.enemy_catalog = {}
	var speeds := [23.0,43.0,17.0,24.0,30.0,22.0,20.0,24.0,24.0,28.0]
	var radii := [18.0,16.0,24.0,20.0,20.0,28.0,30.0,28.0,30.0,32.0]
	var behaviors := ["chase","runner","brute","sweep","grab","charge","sweep","leap","grab","combo"]
	for index in IDS.size():
		value.enemy_catalog[IDS[index]] = {"hp":10000.0,"speed":speeds[index],"radius":radii[index],"damage":10.0,"xp":0,"behavior":behaviors[index]}
	return value
static func run_with_enemy(sim, enemy_id: String, position := [-160.0,0.0]) -> Dictionary:
	var state: Dictionary = sim.new_run(chapter(),44)
	state.player.hp = 10000.0
	state.player.max_hp = 10000.0
	CoreFixture.step(sim,state,Vector2.ZERO,[CoreFixture.spawn("actor",position,enemy_id)])
	return state
static func until_action(sim,state: Dictionary,action: String,limit := 800) -> bool:
	for index in limit:
		if state.entities[0].get("action_state","") == action: return true
		CoreFixture.step(sim,state,Vector2.ZERO,[])
	return false
static func vec(values: Array) -> Vector2:
	return Vector2(values[0],values[1])
