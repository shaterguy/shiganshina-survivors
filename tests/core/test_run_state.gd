extends RefCounted
const Fixture = preload("res://tests/core/core_fixture.gd")
const Contracts = preload("res://game/contracts/game_contracts.gd")
func run(t) -> void:
	var sim = Fixture.simulation(t)
	if sim == null: return
	test_snapshot_restore_replay(t,sim)
	test_pause_freezes_all_clocks(t,sim)
	test_command_idempotency(t,sim)
	test_death_before_exit(t,sim)
	test_abandon_requires_request(t,sim)
	test_restore_corrupt_records(t,sim)
	test_reject_premature_final_commands(t,sim)
	test_invalid_hazard_dto(t,sim)
func test_snapshot_restore_replay(t,sim) -> void:
	var state: Dictionary = sim.new_run(Fixture.chapter(), 1234)
	t.check(Contracts.new().validate_snapshot(state).is_empty(), "new run satisfies complete RunState schema")
	var saved: Dictionary = sim.snapshot(state)
	saved.player.position[0] = 9000
	t.check(state.player.position[0] == 0.0, "snapshot deep copy does not alias source")
	saved = JSON.parse_string(JSON.stringify(sim.snapshot(state)))
	var restored: Dictionary = sim.restore(saved)
	t.check(restored.ok and restored.state == state, "JSON restore preserves full run state")
	restored.state.player.position[0] = 1
	t.check(saved.player.position[0] == 0.0, "restore does not mutate or alias input")
	saved.phase = "invalid"
	t.check(not sim.restore(saved).ok, "invalid restore rejected")
	for missing in ["attack_ready_ticks","facing"]:
		saved = sim.snapshot(state)
		saved.player.erase(missing)
		t.check(not sim.restore(saved).ok, "missing core player field rejected: " + missing)
	var replay: Dictionary = sim.new_run(Fixture.chapter(),1234)
	for tick in 300:
		var commands: Array = [Fixture.spawn("replay:%d"%tick,[state.player.position[0]+12.0,state.player.position[1]])] if tick % 60 == 0 else []
		var move := Vector2.RIGHT if tick < 150 else Vector2.DOWN
		Fixture.step(sim,state,move,commands)
		Fixture.step(sim,replay,move,commands)
		if not state.upgrade_offer.is_empty():
			sim.choose_upgrade(state,state.upgrade_offer.offer_id,state.upgrade_offer.options[0].option_id)
			sim.choose_upgrade(replay,replay.upgrade_offer.offer_id,replay.upgrade_offer.options[0].option_id)
	t.check(state == replay, "same seed and input sequence produce identical state")
	var mid: Dictionary = sim.restore(JSON.parse_string(JSON.stringify(sim.snapshot(state)))).state
	for tick in 100:
		Fixture.step(sim,state,Vector2.LEFT,[])
		Fixture.step(sim,mid,Vector2.LEFT,[])
	t.check(state == mid, "restored RNG cooldowns and clocks replay identically")
func test_pause_freezes_all_clocks(t,sim) -> void:
	for reason in ["user","upgrade","rotation","background","controller_lost","slow_frame"]:
		var state: Dictionary = sim.new_run(Fixture.chapter(),7)
		Fixture.step(sim,state,Vector2.RIGHT,[Fixture.spawn("clock",[10.0,0.0])])
		sim.set_pause(state,reason,true)
		var before: Dictionary = sim.snapshot(state)
		for tick in 5: t.check(Fixture.step(sim,state,Vector2.ONE,[Fixture.spawn("blocked",[0,0])]).is_empty(), "pause emits no events")
		t.check(state == before, "test_pause_freezes_all_clocks " + reason)
	var state: Dictionary = sim.new_run(Fixture.chapter(),7)
	sim.set_pause(state,"user",true)
	sim.set_pause(state,"background",true)
	sim.set_pause(state,"user",false)
	t.check(state.pause_reasons == ["background"], "pause reasons released independently")
	var before: Dictionary = sim.snapshot(state)
	sim.set_pause(state,"unknown",true)
	t.check(state == before, "unknown pause reason ignored")
func test_command_idempotency(t,sim) -> void:
	var state: Dictionary = sim.new_run(Fixture.chapter(),7)
	state.equipment.clear()
	var command: Dictionary = Fixture.spawn("once",[100,0])
	Fixture.step(sim,state,Vector2.ZERO,[command,command])
	Fixture.step(sim,state,Vector2.ZERO,[command])
	t.check(state.entities.size() == 1 and state.command_ids_applied == ["spawn:once"], "duplicate command applied only once")
	var boss: Dictionary = Fixture.boss("ch01_b05",[100,0])
	var events: Array = Fixture.step(sim,state,Vector2.ZERO,[boss,boss])
	t.check(state.boss_ids_fired == ["ch01_b05"] and Fixture.types(events,"boss_spawned").size() == 1, "boss spawn event and stable ID once")
func evacuation_state(sim) -> Dictionary:
	var state: Dictionary = sim.new_run(Fixture.chapter(),99)
	state.active_tick = 108000
	state.survival_tick = 108000
	state.entities = [{"id":"prior","position":[0,0],"hp":1.0}]
	state.drops = [{"id":"prior_drop","position":[0,0],"xp":999}]
	Fixture.step(sim,state,Vector2.ZERO,[{"command_id":"final","kind":"begin_evacuation","payload":{"boss_id":"ch01_final_armored","escape_zone":[-20,-20,40,40],"evacuation_ticks":4500}}])
	return state
func test_death_before_exit(t,sim) -> void:
	var state: Dictionary = evacuation_state(sim)
	t.check(state.phase == "evacuation" and state.survival_tick == 108000 and state.active_tick == 108001, "evacuation survival clock freezes active clock continues")
	t.check(state.entities.is_empty() and state.drops.is_empty() and state.player.level == 1 and state.stats.kills == 0, "evacuation cleanup awards nothing")
	state.active_tick = state.final_started_tick + 4498
	Fixture.step(sim,state,Vector2.ZERO,[])
	t.check(not state.evacuation_ready and state.phase == "evacuation", "4499 ticks cannot escape")
	var events: Array = Fixture.step(sim,state,Vector2.ZERO,[Fixture.hazard("lethal_exit")])
	t.check(state.phase == "dead" and Fixture.types(events,"run_ended").size() == 1 and events[-1].payload.result == "dead", "test_death_before_exit failure wins same tick")
	state = evacuation_state(sim)
	state.active_tick = state.final_started_tick + 4499
	events = Fixture.step(sim,state,Vector2.ZERO,[])
	t.check(state.phase == "won" and state.evacuation_ready and Fixture.types(events,"run_ended").size() == 1, "4500 ticks then escape zone wins once")
	var frozen: Dictionary = sim.snapshot(state)
	t.check(Fixture.step(sim,state,Vector2.ZERO,[]).is_empty() and state == frozen, "won run frozen")
func test_abandon_requires_request(t,sim) -> void:
	var state: Dictionary = sim.new_run(Fixture.chapter(),5)
	sim.set_pause(state,"user",true)
	t.check(state.phase == "survival" and state.reward_ids_claimed.is_empty(), "pause alone does not abandon")
	var events: Array = sim.abandon_run(state)
	t.check(state.phase == "dead" and events.size() == 1 and events[0].type == "run_ended" and events[0].payload.reason == "abandoned" and events[0].payload.result == "dead", "test_abandon_requires_request explicit API ends run")
	t.check(state.reward_ids_claimed.is_empty() and events[0].payload.clear_reward == 0, "abandon grants zero clear reward")
	var before: Dictionary = sim.snapshot(state)
	t.check(sim.abandon_run(state).is_empty() and state == before, "abandon result idempotent")

func test_restore_corrupt_records(t,sim) -> void:
	var good: Dictionary = sim.new_run(Fixture.chapter(),33)
	good.equipment.clear()
	Fixture.step(sim,good,Vector2.ZERO,[Fixture.spawn("valid",[100,0])])
	for corruption in ["hp","velocity","radius","xp","spawned_tick"]:
		var broken: Dictionary = sim.snapshot(good)
		broken.entities[0].erase(corruption)
		t.check(not sim.restore(broken).ok,"corrupt enemy rejected: "+corruption)
	for corruption in ["seed","active_tick","event_seq"]:
		var broken: Dictionary = sim.snapshot(good)
		broken[corruption] = 1.5
		t.check(not sim.restore(broken).ok,"fractional schema integer rejected: "+corruption)
	var broken: Dictionary = sim.snapshot(good)
	broken.player.attack_ready_ticks.blade_slash = "bad"
	t.check(not sim.restore(broken).ok,"invalid attack clock rejected")
	broken = sim.snapshot(good)
	broken.telegraphs = [{"id":4,"shape":"circle","origin":[0,0]}]
	t.check(not sim.restore(broken).ok,"corrupt hazard rejected")
	broken = sim.snapshot(good)
	broken.drops = [{"id":5,"position":[0,0],"xp":-4}]
	t.check(not sim.restore(broken).ok,"negative drop XP rejected")
	broken = sim.snapshot(good)
	broken.command_ids_applied = ["duplicate","duplicate"]
	t.check(not sim.restore(broken).ok,"duplicate id set rejected")
func test_reject_premature_final_commands(t,sim) -> void:
	var state: Dictionary = sim.new_run(Fixture.chapter(),6)
	Fixture.step(sim,state,Vector2.ZERO,[{"command_id":"early_final","kind":"begin_evacuation","payload":{"boss_id":"ch01_final_armored","escape_zone":[-20,-20,40,40],"evacuation_ticks":4500}}])
	t.check(state.phase == "survival" and not "early_final" in state.command_ids_applied,"final cannot begin before 30 minutes")
	state.phase = "evacuation"
	state.final_started_tick = state.active_tick
	state.survival_tick = 108000
	Fixture.step(sim,state,Vector2.ZERO,[{"command_id":"early_ready","kind":"evacuation_ready","payload":{}}])
	t.check(not state.evacuation_ready and state.phase == "evacuation","ready command cannot bypass 75 second timer")

func test_invalid_hazard_dto(t,sim) -> void:
	for invalid_key in ["source_id","radius","warning_ticks","damage"]:
		var state: Dictionary = sim.new_run(Fixture.chapter(),1)
		var command: Dictionary = Fixture.hazard("invalid_hazard:"+invalid_key)
		if invalid_key == "source_id": command.payload.erase(invalid_key)
		elif invalid_key == "warning_ticks": command.payload[invalid_key] = 0.5
		else: command.payload[invalid_key] = "broken"
		Fixture.step(sim,state,Vector2.ZERO,[command])
		t.check(state.telegraphs.is_empty() and state.player.hp == 100.0,"invalid hazard DTO rejected: "+invalid_key)
