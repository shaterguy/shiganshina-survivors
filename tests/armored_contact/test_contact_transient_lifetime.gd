extends RefCounted
const S = preload("res://tests/armored_actor/armored_support.gd")
const R = preload("res://tests/armored_actor/test_armored_rebase.gd")
func run(t) -> void:
	_finite_counter(t,false)
	_finite_counter(t,true)
	for reason in ["pause","command_limit","terminal"]:
		var f := S.make()
		S.begin(f); S.arrange_windup(f,Vector2.ZERO,Vector2(300,0))
		for i in 80: S.step(f)
		t.check(not f.core._final_sweeps.is_empty(),"successful prior charge exposes one accepted tick before "+reason)
		var commands: Array[Dictionary] = []
		if reason == "pause": f.state.pause_reasons.append("user")
		elif reason == "terminal": f.state.phase = "abandoned"
		else:
			for i in 1025: commands.append({})
		var before: Dictionary = f.state.duplicate(true)
		var events: Array = f.core.step(f.state,Vector2.ZERO,commands)
		t.check(events.is_empty() and f.state == before and f.core._final_sweeps.is_empty(),"early "+reason+" entry exposes no old accepted witness")
	var city := R.new()._make(t)
	if not city.is_empty():
		t.check(R.new()._until(city,"attack") and not city.core._final_sweeps.is_empty(),"city early coverage rejection begins after successful sweep")
		city.state.player.position = [10000.0,384.0]
		var before: Dictionary = city.state.duplicate(true)
		var events := S.step(city)
		t.check(events.is_empty() and city.state == before and city.core._final_sweeps.is_empty(),"preflight/rebase coverage rejection clears old transient before staging")
func _finite_counter(t, succeed: bool) -> void:
	var f := S.make()
	S.begin(f); S.arrange_windup(f,Vector2.ZERO,Vector2(200,0))
	var next_hit := false
	for i in 140:
		var a := S.actor(f.state)
		if a.action_state == "attack":
			var p: Dictionary = f.state.rules.enemy_catalog.armored_titan.action_profile
			var delta: float = f.core._final_charge_speed(p,int(f.state.active_tick)+1-int(a.action_started_tick))/60.0
			var origin := Vector2(a.position[0]+56,a.position[1])
			var hit := {"shape":"line","origin":[origin.x,origin.y],"direction":[1.0,0.0],"length":delta,"width":32.0}
			if S.Core.Geometry.overlaps(hit,Vector2(200,0),8): next_hit = true; break
		S.step(f)
	t.check(next_hit,"finite counter fixture reaches next actual player contact")
	if not next_hit: return
	f.state.event_seq = S.Core.MAX_COUNTER-1 if succeed else S.Core.MAX_COUNTER
	t.check(f.core.restore(f.state).get("ok",false),"finite high-counter pre-hit snapshot is valid")
	var before: Dictionary = f.state.duplicate(true)
	var events := S.step(f)
	if succeed:
		t.check(not events.is_empty() and f.state.player.hp < before.player.hp and f.state.active_tick == before.active_tick+1 and not f.core._final_sweeps.is_empty(),"successful finite counter transaction keeps same-tick real damage and accepted sweep")
	else:
		t.check(events.is_empty() and f.state == before and f.core._final_sweeps.is_empty(),"rejected finite counter transaction leaks no staged damage or witness")
