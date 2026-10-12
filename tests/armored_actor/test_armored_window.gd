extends RefCounted
const S = preload("res://tests/armored_actor/armored_support.gd")
const R = preload("res://tests/armored_actor/test_armored_rebase.gd")
const H = preload("res://game/core/streamed_run_world.gd")
const F = preload("res://tests/core_world/new_streamed_helper_fixture.gd")
func run(t) -> void:
	for direction in [Vector2.RIGHT,Vector2.LEFT,Vector2.UP,Vector2.DOWN,Vector2(1,1).normalized(),Vector2(-1,-1).normalized()]:
		var f := R.new()._make(t)
		if f.is_empty(): return
		f.state.passives.movement = 5
		var a := S.actor(f.state)
		a.position = [346.0,384.0]; a.locked_origin = a.position.duplicate()
		S.step(f)
		a = S.actor(f.state)
		t.check(a.action_state == "windup" and a.locked_origin == [346.0,384.0],"A3 full trigger-range warning begins on verified geometry")
		var start: int = f.state.active_tick
		var maximum := 0.0
		var valid := true
		var finished := false
		for tick in 241:
			var before: int = f.state.active_tick
			S.step(f,direction)
			if f.state.active_tick == before:
				var needed := H.requirements(f.state)
				if not needed.get("ok",false): valid = false; break
				if not f.core.prepare_world(f.state,F.hydration(needed)).get("ok",false): valid = false; break
				S.step(f,direction)
			if f.state.active_tick != before+1: valid = false; break
			a = S.actor(f.state)
			if a.is_empty(): valid = false; break
			var player := Vector2(f.state.player.position[0],f.state.player.position[1])
			var origin := Vector2(a.locked_origin[0],a.locked_origin[1])
			var body := Vector2(a.position[0],a.position[1])
			maximum = maxf(maximum,maxf((player-origin).abs().x,(player-origin).abs().y))
			maximum = maxf(maximum,maxf((player-body).abs().x,(player-body).abs().y))
			if a.action_state == "move": finished = true; break
		t.check(valid and finished and f.state.active_tick-start <= 240 and maximum < 2304,"A3 whole physical attack chain ends before working-set exhaustion at actual225speed "+str(direction)+" max="+str(maximum))
		t.check(f.state.final_started_tick == 108000 and H.requirements(f.state).get("ok",false),"A3 active chain neither resets final timer nor parks unfinished motion")
