extends RefCounted
const F = preload("res://tests/waiting_motion/fixture.gd")
func run(t) -> void:
	var reports := []
	for index in F.ROLES.size():
		var f := F.make(t)
		var id := "wait:"+str(index)
		f.state.entities = f.state.entities.filter(func(e): return str(e.id) in [id,"pressure"])
		var rows := [F.row(f)]
		var attack := {}
		var phases := {}
		var hurt := []
		for i in 119:
			if i == 29:
				# Test-only disappearance of the exact legacy pressure source. No
				# admission/attack method is overridden or forced to succeed.
				f.state.entities = f.state.entities.filter(func(e): return str(e.id)!= "pressure")
				f.state.player.invulnerable_until = 0
			var events := F.step(f)
			t.check(f.sim.step_status().get("ok",false),"pressure release uses actual successful Core ticks")
			var e := F.actor(f.state,id)
			phases[e.action_state] = true
			if not f.state.enemy_attack_instances.is_empty():
				var live: Dictionary = f.state.enemy_attack_instances[0]
				if attack.is_empty():
					attack = live.duplicate(true)
					t.check(attack.locked_origin==e.position and attack.started_tick==f.state.active_tick,"approval locks the moved current origin on this exact tick")
					t.check(e.role_wait_since == -1 and e.role_retry_tick==0,"only real approval ends waiting and clears retry")
					t.check(int(attack.started_tick)>=12031 and int(attack.started_tick)<=12045,"risk disappearance resumes normal retry-window admission")
					t.check(attack.active_from_tick-attack.started_tick==int(f.sim._role_profile(e.enemy_id).warning_ticks),"full authored warning survives waiting movement")
					t.check(f.sim.step_status().role_admission.strong_slot_limit==3 and f.sim.step_status().role_admission.melee_slot_limit==2,"late strong/melee caps are preserved")
					t.check(f.sim.step_status().role_admission.paths_tested>0,"actual safe-path evaluation ran before approval")
				for key in ["locked_origin","locked_direction","locked_target","started_tick","active_from_tick","attack_ends_tick","recover_ends_tick","profile"]:
					t.check(live[key]==attack[key],"approved attack geometry and schedule remain locked: "+key)
				var sampled: Dictionary = F.Model.sample_query(live,int(f.state.active_tick),f.sim._role_query(f.state),float(e.role_hand_reach))
				t.check(sampled.get("ok",false) and e.position==sampled.sample.position,"live approved pose follows existing model exactly")
				if sampled.get("ok",false) and e.action_state=="windup":
					t.check(f.sim._role_samples[id].telegraph_geometry==sampled.sample.telegraph_geometry,"visible warning geometry matches locked current-origin attack")
			for event in events:
				if event.type=="damage" and event.payload.get("source_id")==id:
					t.check(not attack.is_empty() and f.state.active_tick>=attack.active_from_tick,"waiting and warning never inflict role damage")
					t.check(event.payload.amount==float(e.damage),"role hit retains authored damage")
					hurt.append(event)
			rows.append(F.row(f))
			t.check(f.sim.restore(JSON.parse_string(JSON.stringify(f.state,"",true,true))).get("ok",false),"moved waiting/approved state satisfies durable Core validation")
		t.check(not attack.is_empty() and phases.has("windup") and phases.has("attack"),"risk removal resumes actual "+F.ROLES[index]+" warning and attack")
		t.check(hurt.size()==1,"actual "+F.ROLES[index]+" deals one unchanged hit in 120-tick release observation")
		reports.append({"role":F.ROLES[index],"rows":rows,"attack":attack,"phases":phases,"damage":hurt})
	F.write("release-120.json",reports)
