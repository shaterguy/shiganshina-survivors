extends RefCounted
# Interface-only DTO fixtures; these do not prove Core or Director integration.
const F = preload("res://tests/core/new_current_regression_fixture.gd")
static func snapshot(t) -> Dictionary:
	var sim = F.simulation(t)
	var value: Dictionary = sim.new_run(F.chapter(),42,F.run_config())
	value.active_tick = 60
	value.entities = [{"id":7,"enemy_id":"grabber","position":[0.0,0.0],"velocity":[0.0,0.0],"facing":[1.0,0.0],"hp":58.0,"action_state":"windup"}]
	return value
static func line(start: float, end: float) -> Dictionary:
	return {"shape":"line","origin":[start,0.0],"direction":[1.0,0.0],"length":end-start,"width":44.0}
static func packet(snapshot_value: Dictionary, phase := "windup") -> Dictionary:
	var world: Dictionary = snapshot_value.get("world",{})
	var hand := {"rest":[40.0,0.0],"previous":[40.0,0.0],"current":[40.0,0.0],"warning_start":[40.0,0.0],"warning_end":[210.0,0.0]}
	if phase == "attack": hand.current = [50.625,0.0]
	if phase == "recover": hand.previous = [210.0,0.0]; hand.current = [207.976190476,0.0]
	return {"ok":true,"run_id":snapshot_value.run_id,"tick":snapshot_value.active_tick,"scene_id":world.get("scene_id","finite"),"origin_revision":world.get("origin_revision",0),"world_revision":world.get("world_revision",0),"attacks":[{"attack_id":snapshot_value.run_id+":enemy:7:1","source_id":"7","role_id":"grabber","phase":phase,"position":[0.0,0.0],"telegraph_geometry":[line(40.0,210.0)] if phase == "windup" else [],"damage_geometry":[line(40.0,50.625)] if phase == "attack" else [],"hand_pose":hand}]}
static func city(snapshot_value: Dictionary) -> Dictionary:
	var value := snapshot_value.duplicate(true)
	value.world = {"mode":"streamed_city","stage":"city","scene_id":"city","origin_chunk":["0","0"],"origin_revision":2,"world_revision":3}
	return value
static func terrain(snapshot_value: Dictionary) -> Dictionary:
	var value: Dictionary = snapshot_value.world.duplicate(true)
	value.ok = true
	value.chunks = []
	return value
