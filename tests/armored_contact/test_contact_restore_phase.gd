extends RefCounted
const S = preload("res://tests/armored_actor/armored_support.gd")
func run(t) -> void:
	# A gap75 warning is deliberately inadmissible under preparation97.
	# Preserve the old exact first-step damage contract as a direct physical sweep.
	var endpoint := S.make({"bounds":[-2000,-2000,4000,4000],"obstacles":[[75,-60,50,120]]},[500,500])
	var probe: Dictionary = endpoint.core._final_contact_sweep(endpoint.state,Vector2.ZERO,Vector2(3,0),Vector2.RIGHT,endpoint.state.rules.enemy_catalog.armored_titan.action_profile,null)
	t.check(probe.stopped and probe.position == Vector2(3,0) and probe.contact.fraction == 1.0,"unchanged exact-endpoint first3 physical contact still stops at full travel")
	for wall_x in [150,98]:
		var f := S.make({"bounds":[-2000,-2000,4000,4000],"obstacles":[[wall_x,-60,50,120]]},[500,500])
		S.begin(f); S.arrange_windup(f,Vector2.ZERO,Vector2(300,0))
		var before: Dictionary = {}
		for i in 160:
			before = f.state.duplicate(true)
			S.step(f)
			if S.actor(f.state).action_state == "brake": break
		t.check(S.actor(f.state).action_state == "brake" and f.core.restore(f.state).get("ok",false),"natural shoulder stop cold restores as brake "+str(wall_x))
		var forged: Dictionary = f.state.duplicate(true)
		var prior := S.actor(before)
		var entity := S.actor(forged)
		for key in ["action_state","action_started_tick","action_ends_tick","locked_origin"]: entity[key] = prior[key]
		if prior.action_state == "windup":
			entity.action_state = "attack"
			entity.action_started_tick = f.state.active_tick
			entity.action_ends_tick = int(f.state.active_tick)+60
		var p: Dictionary = forged.rules.enemy_catalog.armored_titan.action_profile
		var speed: float = f.core._final_charge_speed(p,int(forged.active_tick)-int(entity.action_started_tick))
		entity.velocity = [speed,0.0]
		forged.telegraphs = before.telegraphs.duplicate(true)
		t.check(not f.core.restore(forged).get("ok",false),"forged stopped attack is rejected because actual step already braked "+str(wall_x))
	var open := S.make()
	S.begin(open); S.arrange_windup(open,Vector2.ZERO,Vector2(370,0))
	var last := false
	for i in 150:
		S.step(open)
		var a := S.actor(open.state)
		if a.action_state == "attack" and int(a.action_ends_tick)-int(open.state.active_tick) == 1:
			last = true
			t.check(open.core.restore(open.state).get("ok",false),"natural last unobstructed attack tick remains valid before expiration")
			break
	t.check(last,"open fixture observes final60th damaging update")
	S.step(open)
	t.check(S.actor(open.state).action_state == "brake" and open.core.restore(open.state).get("ok",false),"normal expired charge becomes valid non-damaging brake")
