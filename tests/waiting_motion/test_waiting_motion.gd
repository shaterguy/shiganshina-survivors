extends RefCounted
const F = preload("res://tests/waiting_motion/fixture.gd")
func run(t) -> void:
	var f := F.make(t)
	var start: Dictionary = f.state.duplicate(true)
	var rows := [F.row(f)]
	var travel := [0.0,0.0,0.0]
	var moved := [0,0,0]
	for i in 119:
		var prior: Dictionary = f.state.duplicate(true)
		F.step(f)
		t.check(f.sim.step_status().get("ok",false),"waiting movement fixed tick commits")
		var d: Dictionary = f.sim.step_status().get("role_admission",{})
		t.check(int(d.get("evaluations",0))<=1 and int(d.get("work_units",0))<=8192,"waiting movement preserves one evaluation and 8192 work cap")
		for j in F.ROLES.size():
			var e := F.actor(f.state,"wait:"+str(j))
			var before := F.actor(prior,str(e.id))
			var distance := F.point(e).distance_to(F.point(before))
			travel[j] += distance
			if distance > .0001: moved[j] += 1
			t.check(e.role_wait_since==12001 and e.action_state=="move","actual moving waiter retains oldest priority and unapproved phase")
			t.check(e.role_retry_tick==before.role_retry_tick or (d.get("source_id")==str(e.id) and e.role_retry_tick==int(f.state.active_tick)+15),"movement never resets or advances retry clock")
			t.check(F.point(e).length()<=float(f.sim._role_profile(e.enemy_id).trigger_range),"waiting reposition stays in authored trigger range")
		rows.append(F.row(f))
	for j in F.ROLES.size():
		var e := F.actor(f.state,"wait:"+str(j))
		t.check(travel[j]>8.0 and moved[j]>90,"waiting "+F.ROLES[j]+" physically repositions during denied attack")
	var thrower := F.actor(f.state,"wait:0")
	var grabber := F.actor(f.state,"wait:1")
	var quad := F.actor(f.state,"wait:2")
	t.check(F.point(thrower).length()>F.point(F.actor(start,"wait:0")).length()+5.0,"close thrower retreats rather than pursuing the player")
	t.check(F.point(grabber).length()<179.0 and F.point(grabber).length()>100.0,"grabber approaches usable distance without closing to body contact")
	t.check(F.point(quad).length()>100.0 and absf(F.point(quad).y)>3.0,"quadruped keeps charge gap and changes approach line")
	t.check(f.state.enemy_attack_instances.is_empty() and f.state.attack_seq==0,"continuous body pressure never bypassed by motion")
	F.write("blocked-120.json",{"rows":rows,"travel":travel,"moving_ticks":moved,"initial_state":start,"final_state":f.state})
	print("WAITING_MOTION ",JSON.stringify({"travel":travel,"moving_ticks":moved,"ticks":120}))
