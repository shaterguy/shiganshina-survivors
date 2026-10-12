extends RefCounted
const F = preload("res://tests/staggered_steering/fixture.gd")
func run(t) -> void:
	var rows: Array = []
	for ordinal in 4:
		var f := F.make(t,"walker","corner:"+str(ordinal),ordinal)
		if f.is_empty(): continue
		var reached := false
		var still_ticks := 0
		var max_still := 0
		var accepted := 0
		var first: Vector2 = f.sim._vec(f.state.entities[0].position)
		for i in 1800:
			var before: Vector2 = f.sim._vec(f.state.entities[0].position)
			f.state.player.hp = float(f.state.player.max_hp)
			F.clear(f.sim)
			F.F.step(f.sim,f.state,Vector2.ZERO)
			if not f.sim.step_status().get("ok",false): t.check(false,"corner pursuit tick must not fail"); break
			accepted += 1
			var now: Vector2 = f.sim._vec(f.state.entities[0].position)
			if now.distance_to(before)<0.00001: still_ticks += 1
			else: still_ticks = 0
			max_still = maxi(max_still,still_ticks)
			if not f.sim._streamed.walkable(now,18.0).get("walkable",false): t.check(false,"long corner pursuit never crosses a wall"); break
			if now.distance_to(f.sim._vec(f.state.player.position))<=24.0: reached = true; break
		rows.append({"ordinal":ordinal,"accepted_ticks":accepted,"reached":reached,"max_still_ticks":max_still,"start":[first.x,first.y],"target":f.state.player.position,"end":f.state.entities[0].position})
		t.check(reached,"long real obstacle pursuit reaches player without corner oscillation: "+str(ordinal))
		t.check(max_still<=2,"long real obstacle pursuit has no stationary wall attachment: "+str(ordinal))
	print("STEERING_CORNERS ",JSON.stringify(rows))
