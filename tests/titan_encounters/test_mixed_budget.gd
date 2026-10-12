extends RefCounted
const F = preload("res://tests/core/core_fixture.gd")
const G = preload("res://tests/core/test_live_grabber.gd")
func run(t) -> void:
	var f := G.setup()
	var state: Dictionary = f.state
	var commands := [G.spawn(7,[170.0,0.0]),G.spawn(8,[-150.0,0.0],"quadruped"),G.spawn(9,[0.0,260.0],"stone_thrower")]
	var admitted := {}
	var peak := 0
	var max_work := 0
	var max_wait := 0
	for tick in range(1,181):
		F.step(f.sim,state,Vector2.ZERO,commands if tick == 1 else [])
		var d: Dictionary = f.sim.step_status().get("role_admission",{})
		max_work = maxi(max_work,int(d.get("work_units",0)))
		if d.get("accepted",false): max_wait = maxi(max_wait,int(d.get("wait_ticks",0)))
		var active := 0
		for a in state.enemy_attack_instances:
			admitted[a.role_id] = true
			if a.attack_ends_tick > state.active_tick: active += int(a.profile.threat_cost)
		peak = maxi(peak,active)
		t.check(f.sim.step_status().ok and active <= 2 and int(d.get("evaluations",0)) <= 1 and int(d.get("work_units",0)) <= 8192,"mixed role tick obeys single shared attack/work budget "+str(tick))
	t.check(admitted.has_all(["grabber","quadruped","stone_thrower"]),"all distinct roles eventually enter actual attacks under saturated early budget")
	t.check(peak == 2 and max_wait > 0,"mixed encounter exercises full slots and real queue waiting")
	print("TITAN_MIXED_BUDGET ",JSON.stringify({"admitted":admitted.keys(),"peak_slots":peak,"max_wait_ticks":max_wait,"max_work_units":max_work}))
