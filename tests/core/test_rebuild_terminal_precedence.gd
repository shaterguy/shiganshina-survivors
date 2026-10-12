extends RefCounted
const F=preload("res://tests/core/core_fixture.gd")
const L=preload("res://tests/core/test_rebuild_growth_lifecycle.gd")
func run(t) -> void:
	var sim=load("res://game/core/run_simulation.gd").new()
	var chapter:=F.v2_chapter()
	var state: Dictionary=sim.new_run(chapter,42,F.run_config())
	state.active_tick=107999
	state.survival_tick=107999
	var begin:= {"command_id":"final_begin","kind":"begin_evacuation","payload":{"boss_id":"ch01_final_armored","escape_zone":chapter.escape_zone.duplicate(),"evacuation_ticks":4500}}
	var events:=F.step(sim,state,Vector2.ZERO,[begin])
	t.check(state.phase=="evacuation" and state.final_started_tick==108000 and state.survival_tick==108000,"authored final command enters evacuation at active108000 exactly once")
	t.check(F.types(events,"boss_spawned").size()==1 and state.tactical_seals==0 and state.stats.minibosses_defeated==0,"final threat has no miniboss/seal reward")
	t.check(sim.restore(state).get("ok",false),"actual phase-transition checkpoint restores")
	var again:=F.step(sim,state,Vector2.ZERO,[begin])
	t.check(F.types(again,"boss_spawned").is_empty() and state.final_started_tick==108000 and state.survival_tick==108000,"duplicate final command cannot reset evacuation start or survival")
	F.arrange_final_clock(state,112498)
	state.player.position=[0.0,350.0]
	t.check(sim.restore(state).get("ok",false),"arranged near-complete evacuation is restore-valid")
	F.step(sim,state,Vector2.ZERO)
	t.check(state.phase=="evacuation" and not state.evacuation_ready,"physical dock presence at4499 elapsed ticks is insufficient")
	var checkpoint: Dictionary=sim.restore(JSON.parse_string(JSON.stringify(state,"",true,true)))
	L.add_xp(state,24)
	if checkpoint.get("ok",false): L.add_xp(checkpoint.state,24)
	var win:=F.step(sim,state,Vector2.ZERO)
	t.check(state.phase=="won" and state.evacuation_ready and F.types(win,"run_ended").size()==1,"alive physical presence wins at exactly4500 subsequent active ticks")
	t.check(state.upgrade_offer.is_empty() and state.pending_offers.is_empty() and F.types(win,"upgrade_opened").is_empty(),"win takes precedence over same-tick growth")
	if checkpoint.get("ok",false):
		var replay:=F.step(sim,checkpoint.state,Vector2.ZERO)
		t.check(replay==win and checkpoint.state==state,"same terminal tick replays with identical event identities and state")
	t.check(sim.restore(state).get("ok",false),"won snapshot restores")
	var outside:=state.duplicate(true)
	outside.player.position=[0.0,0.0]
	t.check(not sim.restore(outside).get("ok",false),"won authority must still prove physical escape position")
	var dead: Dictionary=sim.new_run(chapter,42,F.run_config(1,"doctrine_standard","evo_wing_cut","field_bandage"))
	dead.active_tick=107999
	dead.survival_tick=107999
	F.step(sim,dead,Vector2.ZERO,[begin])
	F.arrange_final_clock(dead,112499)
	dead.player.position=[0.0,350.0]
	dead.player.hp=1.0
	dead.passives={"recovery":5}
	L.add_xp(dead,24)
	var death:=F.step(sim,dead,Vector2.ZERO,[F.hazard("dock_lethal","circle",{"origin":[0,350]})])
	t.check(dead.phase=="dead" and not dead.supply_used and dead.player.hp==0,"lethal damage dominates eligible escape, bandage and regeneration")
	t.check(F.types(death,"upgrade_opened").is_empty() and F.types(death,"supply_used").is_empty() and F.types(death,"run_ended")[0].payload.result=="dead","terminal event reports death only")
	t.check(sim.restore(dead).get("ok",false),"lethal same-tick growth/escape state restores")
	_commands(t,sim,chapter,begin)
func _commands(t,sim,chapter: Dictionary,begin: Dictionary) -> void:
	for patch in [{"escape_zone":[0,0,100,100]},{"evacuation_ticks":4500.5},{"evacuation_ticks":{}},{"boss_id":{} }]:
		var state: Dictionary=sim.new_run(chapter,42,F.run_config())
		state.active_tick=107999
		state.survival_tick=107999
		var command:=begin.duplicate(true)
		command.payload.merge(patch,true)
		F.step(sim,state,Vector2.ZERO,[command])
		t.check(state.phase=="survival" and state.final_started_tick==-1 and state.command_ids_applied.is_empty(),"forged final transition payload rejected without partial effects")
	var state: Dictionary=sim.new_run(chapter,42,F.run_config())
	var unsafe:=F.hazard("unsafe")
	unsafe.payload.extra=RefCounted.new()
	F.step(sim,state,Vector2.ZERO,[unsafe])
	t.check(state.telegraphs.is_empty() and not "unsafe" in state.command_ids_applied,"Object metadata never enters live state through command")
	t.check(load("res://game/contracts/game_contracts.gd").new()._json_safe(state),"command refusal preserves serializable authority")
