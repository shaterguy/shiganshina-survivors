extends RefCounted
const S = preload("res://tests/armored_actor/armored_support.gd")
func run(t) -> void:
	_identity(t)
	_invulnerable(t)
	_swept_wall(t)
func _identity(t) -> void:
	var f := S.make()
	var events := S.begin(f)
	var a := S.actor(f.state)
	t.check(not a.is_empty(),"A1 actual Core final boundary creates physical armored entity")
	if a.is_empty(): return
	t.check(f.state.active_tick == 108000 and f.state.final_started_tick == 108000 and a.boss_id == "ch01_final_armored" and a.xp == 0,"A1 final actor owns exact thirty-minute identity and zero XP")
	t.check(events.filter(func(e): return e.type == "boss_spawned" and e.payload.get("entity_id") == a.id).size() == 1,"A1 exactly one physical spawn envelope has actor ID")
	var id = a.id
	for index in 300: S.step(f)
	t.check(S.actor(f.state).id == id and f.state.entities.size() == 1,"A1 repeated final planning cannot duplicate final actor")
	t.check(f.state.telegraphs.all(func(h): return h.get("behavior_attack",false) and h.source_id == str(id)),"A1 no second periodic remote-circle attack producer")
func _invulnerable(t) -> void:
	var f := S.make()
	S.begin(f)
	var a := S.actor(f.state)
	t.check(not a.is_empty(),"A1 final invulnerability test requires actual spawned actor")
	if a.is_empty(): return
	var hp: float = a.hp
	var events: Array[Dictionary] = []
	var rewards: Array[Dictionary] = []
	f.core._hit_entity(f.state,a,9999999.0,"blade_slash",events,rewards,"test:hit")
	f.core._remove_dead(f.state)
	t.check(a.hp == hp and f.state.entities.size() == 1 and f.state.stats.damage_dealt == 0 and f.state.stats.kills == 0,"A1 weapon contact cannot damage or kill final armor")
	t.check(rewards.is_empty() and f.state.drops.is_empty() and f.state.stats.minibosses_defeated == 0 and f.state.tactical_seals == 0,"A1 final hit creates no XP/drop/seal/miniboss reward")
func _swept_wall(t) -> void:
	var f := S.make({"bounds":[-2000,-2000,4000,4000],"obstacles":[[80,-300,40,600]]})
	S.begin(f)
	var a := S.actor(f.state)
	t.check(not a.is_empty(),"A1 shoulder sweep test requires actual spawned actor")
	if a.is_empty(): return
	S.arrange_windup(f,Vector2(-30,0),Vector2(200,0))
	var hp: float = f.state.player.hp
	var observed_brake := false
	for index in 140:
		S.step(f)
		t.check(f.state.player.hp == hp,"A1 planned corridor never damages player beyond the earlier wall")
		if a.action_state == "brake": observed_brake = true; break
	t.check(observed_brake and absf(a.position[0]-8.0) < 0.002,"A1 actual charge sweep stops at solid wall and enters brake")
