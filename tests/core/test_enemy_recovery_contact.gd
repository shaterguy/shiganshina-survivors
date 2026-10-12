extends RefCounted
# Focused, finite test arrangement. Never imports or relabels an old run save.
const Core = preload("res://game/core/run_simulation.gd")
const F = preload("res://tests/core/new_current_regression_fixture.gd")
const B = preload("res://game/combat/enemy_behaviors.gd")
const Current = preload("res://tests/core/current_combat_provider.gd")
const Chapters = preload("res://game/director/chapter_catalog.gd")
const IDS := ["runner","brute","sweeper","grabber","boss_charger","boss_sweeper","boss_leaper","boss_grabber","boss_abnormal"]
class Provider:
	extends RefCounted
	var chapter: Dictionary
	func _init() -> void:
		chapter = Current.new().load_chapter("chapter_01_shiganshina").chapter
		chapter.content_identity_kind = "isolated_enemy_recovery_contact"
		chapter.content_fingerprint = Chapters.new().definition_digest({"chapter":chapter,"core_sha256":FileAccess.get_sha256("res://game/core/run_simulation.gd"),"purpose":"new recovery-contact regression runs only"})
	func load_chapter(id: String) -> Dictionary:
		return {"ok":true,"chapter":chapter.duplicate(true)} if id == chapter.chapter_id else {"ok":false}
func make(id: String) -> Dictionary:
	var provider := Provider.new()
	var sim := Core.new(provider)
	var state := sim.new_run(provider.chapter,44,F.run_config())
	state.equipment.clear()
	state.player.invulnerable_until = 200000
	F.step(sim,state,Vector2.ZERO,[F.actor_command(state,id,[-70.0,0.0])])
	return {"sim":sim,"state":state,"provider":provider}
func until(f: Dictionary, action: String, last_tick := false) -> bool:
	for index in 600:
		var a: Dictionary = f.state.entities[0]
		if a.action_state == action and (not last_tick or int(f.state.active_tick) == int(a.action_ends_tick)-1): return true
		F.step(f.sim,f.state,Vector2.ZERO)
	return false
func hits(events: Array, source := "") -> Array:
	return events.filter(func(e): return e.type == "damage" and e.payload.target_id == "player" and (source.is_empty() or e.payload.source_id == source))
func overlap(state: Dictionary) -> void:
	state.player.position = state.entities[0].position.duplicate()
	state.player.invulnerable_until = 0
func json_copy(value: Dictionary) -> Dictionary:
	return JSON.parse_string(JSON.stringify(value,"",true,true))
func run(t) -> void:
	for id in IDS:
		_recovery_boundaries(t,id)
		_pause_restore(t,id)
		_existing_attack(t,id)
	_other_sources(t)
	_walker_and_iframes(t)
	_airborne(t)
	_fixture_identity(t)
func _recovery_boundaries(t,id: String) -> void:
	var f := make(id)
	t.check(until(f,"attack",true),id+" reaches actual final attack tick")
	var before: Dictionary = f.state.duplicate(true)
	var start: int = int(before.entities[0].action_ends_tick)
	var duration: int = f.sim._role_profile(id).recovery_ticks if id == "grabber" else B.profile(before.entities[0],before.rules.enemy_catalog).recovery_ticks
	for offset in [0,duration/2,duration-1]:
		f.state = before.duplicate(true)
		while int(f.state.active_tick) < start+int(offset)-1: F.step(f.sim,f.state,Vector2.ZERO)
		overlap(f.state)
		var hp: float = f.state.player.hp
		var events: Array = F.step(f.sim,f.state,Vector2.ZERO)
		var a: Dictionary = f.state.entities[0]
		var label := "%s recovery offset %d/%d" % [id,offset,duration]
		t.check(a.action_state == "recover" and int(a.action_started_tick) == start and int(a.action_ends_tick) == start+duration,label+" exact half-open clock")
		t.check(f.state.telegraphs.is_empty(),label+" expired self hazard removed")
		t.check(hits(events,"actor").is_empty() and f.state.player.hp == hp,label+" self contact is harmless")
		t.check(f.state.player.invulnerable_until == 0,label+" does not grant player immunity")
		print("RECOVERY_SAMPLE "+JSON.stringify({"id":id,"offset":offset,"tick":f.state.active_tick,"ends":a.action_ends_tick,"hp_delta":hp-f.state.player.hp,"hits":hits(events)}))
	f.state = before.duplicate(true)
	while int(f.state.active_tick) < start+duration-1: F.step(f.sim,f.state,Vector2.ZERO)
	overlap(f.state)
	var events: Array = F.step(f.sim,f.state,Vector2.ZERO)
	t.check(f.state.entities[0].action_state == "move" and hits(events,"actor").size() == (0 if id == "grabber" else 1),id+" post-recovery body contact follows current role contract")
func _pause_restore(t,id: String) -> void:
	var f := make(id)
	t.check(until(f,"recover"),id+" pause fixture reaches recovery")
	overlap(f.state)
	var end: int = f.state.entities[0].action_ends_tick
	f.sim.set_pause(f.state,"user",true)
	var paused: Dictionary = f.sim.snapshot(f.state)
	for index in 90:
		t.check(F.step(f.sim,f.state,Vector2.RIGHT).is_empty(),id+" paused step emits nothing")
	t.check(f.state == paused,id+" pause freezes HP, recovery clock and whole snapshot")
	var fresh := Core.new(Provider.new())
	var restored: Dictionary = fresh.restore(json_copy(paused))
	t.check(restored.get("ok",false),id+" newly generated paused recovery save restores")
	if not restored.get("ok",false): return
	f.sim.set_pause(f.state,"user",false)
	fresh.set_pause(restored.state,"user",false)
	var live_events: Array = F.step(f.sim,f.state,Vector2.ZERO)
	var restored_events: Array = F.step(fresh,restored.state,Vector2.ZERO)
	t.check(f.state == restored.state and live_events == restored_events,id+" paused restore resumes exactly")
	t.check(f.state.entities[0].action_state == "recover" and f.state.entities[0].action_ends_tick == end and hits(live_events).is_empty(),id+" resume neither shortens recovery nor replays damage")
func _existing_attack(t,id: String) -> void:
	var f := make(id)
	t.check(f.state.entities[0].action_state == "windup",id+" starts warning normally")
	overlap(f.state)
	var hp: float = f.state.player.hp
	var events: Array = F.step(f.sim,f.state,Vector2.ZERO)
	t.check(f.state.player.hp == hp and hits(events).is_empty(),id+" warning body stays harmless")
	f.state.player.invulnerable_until = 200000
	t.check(until(f,"attack"),id+" reaches real attack")
	var active: Dictionary = f.state.duplicate(true)
	# Existing contact is checked independently of its fixed hazard.
	f.state.telegraphs.clear()
	overlap(f.state)
	events = F.step(f.sim,f.state,Vector2.ZERO)
	if id == "grabber":
		t.check(f.state.entities[0].action_state == "attack" and hits(events,"actor").is_empty() and f.state.telegraphs.is_empty(),"ordinary grabber attack has no body or legacy hazard damage")
		return
	t.check(f.state.entities[0].action_state == "attack" and hits(events,"actor").size() == 1,id+" attack body contact remains damaging")
	# Fixed hazard semantics are deliberately unchanged in this narrow patch.
	f.state = active
	var hazard: Dictionary = f.state.telegraphs[0]
	var origin := Vector2(hazard.origin[0],hazard.origin[1])
	var direction := Vector2(hazard.direction[0],hazard.direction[1])
	var point: Vector2 = origin+direction*45.0 if hazard.shape != "circle" else origin
	f.state.player.position = [point.x,point.y]
	f.state.player.invulnerable_until = 0
	events = F.step(f.sim,f.state,Vector2.ZERO)
	t.check(hits(events,"actor").size() == 1,id+" actual active hazard remains damaging")
func _other_sources(t) -> void:
	for id in IDS:
		var f := make(id)
		t.check(until(f,"recover"),id+" other-source fixture reaches recovery")
		var base: Dictionary = f.state.duplicate(true)
		overlap(f.state)
		var point: Array = f.state.player.position.duplicate()
		var events: Array = F.step(f.sim,f.state,Vector2.ZERO,[F.hazard("other:hazard","circle",{"source_id":"other","origin":point,"damage":11.0,"active_ticks":3})])
		t.check(hits(events,"other").size() == 1 and hits(events,"actor").is_empty(),id+" recovery does not suppress another active hazard")
		f.state = base.duplicate(true)
		overlap(f.state)
		events = F.step(f.sim,f.state,Vector2.ZERO,[F.spawn("other_body",point,"walker")])
		t.check(hits(events,"other_body").size() == 1 and hits(events,"actor").is_empty(),id+" recovery does not suppress another body contact")
	# Two genuine staggered brute cycles overlap: actor recovers while other attacks.
	var f := make("brute")
	while f.state.active_tick < 16: F.step(f.sim,f.state,Vector2.ZERO)
	F.step(f.sim,f.state,Vector2.ZERO,[F.spawn("other_attacker",[-70.0,0.0],"brute")])
	while f.state.active_tick < 78: F.step(f.sim,f.state,Vector2.ZERO)
	overlap(f.state)
	var events: Array = F.step(f.sim,f.state,Vector2.ZERO)
	t.check(f.state.entities[0].action_state == "recover" and f.state.entities[1].action_state == "attack", "staggered real actors occupy recovery and attack in same tick")
	t.check(hits(events,"other_attacker").size() == 1 and hits(events,"actor").is_empty(),"other enemy actual attack hazard survives recovery exclusion")
	f.state.telegraphs.clear()
	f.state.player.invulnerable_until = 0
	events = F.step(f.sim,f.state,Vector2.ZERO)
	t.check(hits(events,"other_attacker").size() == 1 and hits(events,"actor").is_empty(),"other enemy actual attack body survives recovery exclusion")
func _walker_and_iframes(t) -> void:
	var f := make("walker")
	overlap(f.state)
	var first: Array = F.step(f.sim,f.state,Vector2.ZERO)
	var tick: int = f.state.active_tick
	var hp: float = f.state.player.hp
	t.check(hits(first,"actor").size() == 1 and f.state.player.invulnerable_until == tick+30,"walker move contact grants existing thirty-tick immunity")
	for index in 29:
		f.state.player.position = f.state.entities[0].position.duplicate()
		t.check(hits(F.step(f.sim,f.state,Vector2.ZERO)).is_empty(),"player immunity excludes next twenty-nine ticks")
	t.check(f.state.player.hp == hp,"player HP unchanged during thirty-tick half-open immunity")
	f.state.player.position = f.state.entities[0].position.duplicate()
	t.check(hits(F.step(f.sim,f.state,Vector2.ZERO),"actor").size() == 1 and f.state.active_tick == tick+30,"contact damages exactly at immunity end")
func _airborne(t) -> void:
	var f := make("boss_leaper")
	t.check(until(f,"airborne"),"leaper reaches genuine airborne state")
	overlap(f.state)
	var hp: float = f.state.player.hp
	var events: Array = F.step(f.sim,f.state,Vector2.ZERO)
	t.check(f.state.entities[0].action_state == "airborne" and hits(events).is_empty() and f.state.player.hp == hp,"airborne contact stays harmless")
func _fixture_identity(t) -> void:
	var f := make("runner")
	var original_sim := Core.new(Current.new())
	var original: Dictionary = original_sim.new_run(F.chapter(),44,F.run_config())
	var before: Dictionary = original.duplicate(true)
	t.check(f.sim.restore(original).get("error_code") == "content_mismatch" and original == before,"newly generated current finite checkpoint rejected unchanged by isolated provider identity")
	t.check(original_sim.restore(f.state).get("error_code") == "content_mismatch","isolated new runs are not accepted as current finite combat saves")
