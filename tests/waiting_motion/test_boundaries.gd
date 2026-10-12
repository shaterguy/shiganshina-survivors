extends RefCounted
const F = preload("res://tests/waiting_motion/fixture.gd")
func run(t) -> void:
	_walls(t)
	_reversal(t)
	_overlap(t)
	_outside(t)
func _walls(t) -> void:
	var world := {"bounds":[-500.0,-500.0,1000.0,1000.0],"obstacles":[[124.0,-40.0,30.0,80.0]]}
	var f := F.make(t,[[100.0,0.0],[0.0,150.0],[-130.0,0.0]],world)
	var rows := []
	for i in 119:
		F.step(f)
		t.check(f.sim.step_status().get("ok",false),"waiting wall step commits without bypassing geometry")
		for e in f.state.entities:
			if e.enemy_id not in F.ROLES: continue
			var radius := maxf(float(e.radius),float(f.sim._role_profile(e.enemy_id).width)*.5)
			t.check(F.Core.World.walkable(F.point(e),radius,world),"waiting actor body and attack origin do not penetrate wall")
		rows.append(F.row(f))
	F.write("wall-120.json",rows)
	# A closed corner has no legal desired component. Stopping is correct,
	# but that must neither lose priority nor raise a runtime error.
	world = {"bounds":[-300.0,-300.0,600.0,600.0],"obstacles":[[124.0,-100.0,100.0,200.0],[60.0,24.0,64.0,100.0],[60.0,-124.0,64.0,100.0]]}
	f = F.make(t,[[100.0,0.0],[-150.0,0.0],[-130.0,-100.0]],world)
	var e := F.actor(f.state,"wait:0")
	var before := F.point(e)
	for i in 8: F.step(f)
	t.check(F.point(F.actor(f.state,"wait:0"))==before and F.actor(f.state,"wait:0").role_wait_since==12001,"fully blocked waiter safely stays with its original priority")
func _reversal(t) -> void:
	var f := F.make(t,[[220.0,0.0],[0.0,135.0],[-127.0,0.0]])
	# Move the saved wait epoch back so a smooth lateral reversal lies in this
	# 120-tick window. No helper state or initial orientation cache is supplied.
	for e in f.state.entities:
		if e.enemy_id in F.ROLES: e.role_wait_since = 11881
	F.step(f) # Establish the saved epoch before measuring continuity.
	var rows := [F.row(f)]
	var reversals := [0,0,0]
	var last_sign := [0,0,0]
	var signed_turn := [0.0,0.0,0.0]
	var max_speed_jump := [0.0,0.0,0.0]
	for i in 119:
		var before: Dictionary = f.state.duplicate(true)
		F.step(f)
		for j in F.ROLES.size():
			var a := F.actor(before,"wait:"+str(j)); var b := F.actor(f.state,"wait:"+str(j))
			var angle := F.point(a).angle_to(F.point(b))
			signed_turn[j] += angle
			var direction := int(signf(angle)) if absf(angle)>0.000001 else 0
			if direction != 0:
				if last_sign[j] != 0 and direction != last_sign[j]: reversals[j] += 1
				last_sign[j] = direction
			max_speed_jump[j] = maxf(max_speed_jump[j],Vector2(a.velocity[0],a.velocity[1]).distance_to(Vector2(b.velocity[0],b.velocity[1])))
		rows.append(F.row(f))
	for j in F.ROLES.size():
		t.check(reversals[j]>=1 and reversals[j]<=2,"lateral arc reverses slowly rather than orbiting or per-tick jitter")
		t.check(absf(signed_turn[j])<.6,"waiting arc cannot complete a one-direction circle in 120 ticks")
		t.check(max_speed_jump[j]<2.0,"arc reversal remains smooth at fixed tick boundary")
	F.write("reversal-120.json",{"rows":rows,"reversals":reversals,"signed_turn_radians":signed_turn,"max_velocity_jump":max_speed_jump})
func _overlap(t) -> void:
	var f := F.make(t,[[130.0,0.0],[132.0,0.0],[134.0,0.0]])
	var rows := [F.row(f)]
	for i in 119:
		F.step(f)
		t.check(f.sim.step_status().get("ok",false),"overlapping waiter fixture preserves existing non-solid actor contract")
		rows.append(F.row(f))
	F.write("overlap-120.json",rows)
func _outside(t) -> void:
	var f := F.make(t)
	var e := F.actor(f.state,"wait:0")
	e.position = [400.0,0.0]
	F.step(f)
	e = F.actor(f.state,"wait:0")
	t.check(e.role_wait_since==-1 and e.role_retry_tick==0,"actual loss of range eligibility retains existing wait reset semantics")
