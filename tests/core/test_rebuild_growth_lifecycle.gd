extends RefCounted
const Fixture = preload("res://tests/core/core_fixture.gd")
const Growth = preload("res://game/progression/growth_offer_service.gd")
func run(t) -> void:
	var sim = load("res://game/core/run_simulation.gd").new()
	var chapter := Fixture.v2_chapter()
	_fifo(t,sim,chapter)
	_choice_counts(t,sim,chapter)
	_evolution_and_boss(t,sim,chapter)
	var ready := Fixture.evolution_ready_state(sim,chapter,Fixture.run_config(),42)
	t.check(not ready.is_empty() and sim.restore(ready).get("ok",false) and ready.upgrade_offer.options[0].option_id == "evolution:evo_wing_cut","shared app fixture crosses actual constructor, boss killing hit, offer and restore gates")
	var saved_ready: Dictionary=sim.restore(JSON.parse_string(JSON.stringify(ready,"",true,true)))
	t.check(saved_ready.get("ok",false) and saved_ready.get("state")==ready,"evolution-ready source option metadata roundtrips to identical scalar types")
	if saved_ready.get("ok",false):
		var original_choice: Dictionary=sim.choose_upgrade(ready,ready.upgrade_offer.offer_id,"evolution:evo_wing_cut")
		var resumed_choice: Dictionary=sim.choose_upgrade(saved_ready.state,saved_ready.state.upgrade_offer.offer_id,"evolution:evo_wing_cut")
		t.check(original_choice==resumed_choice and ready==saved_ready.state,"JSON-restored evolution choice has identical events and authority")
	_bandage_and_terminal(t,sim,chapter)
	_pause(t,sim,chapter)
	_hostile_offers_and_commands(t,sim,chapter)
	_large_xp_queue(t,sim,chapter)
	_reused_option_id(t,sim,chapter)
	_boss_offer_exhaustion(t,sim,chapter)
	_derived_metadata_precision(t,sim,chapter)
	_ledger_capacity_and_sources(t,sim,chapter)
func _fifo(t,sim,chapter: Dictionary) -> void:
	var state: Dictionary = sim.new_run(chapter,42,Fixture.run_config())
	var combat_rng: String = state.rng_state
	var initial_growth: String = state.progression_rng_state
	var expected: Dictionary = state.duplicate(true)
	expected.player.level = 3
	expected.offer_seq = 2
	var descriptor := {"offer_id":state.run_id+":offer:1","source":"level","level_ordinal":2}
	var first: Dictionary = Growth.new().materialize(expected,descriptor)
	var events := gain(sim,state,56)
	t.check(state.player.level == 3 and state.player.xp == 0,"two actual XP thresholds advance player level")
	t.check(state.offer_seq == 2 and state.upgrade_offer.get("offer_id") == descriptor.offer_id,"first growth uses canonical run-scoped monotonic offer ID")
	t.check(state.pending_offers.size() == 1 and state.pending_offers[0] == {"offer_id":state.run_id+":offer:2","source":"level","level_ordinal":3},"unshown offer stays FIFO descriptor only")
	t.check(state.upgrade_offer == first.offer and state.progression_rng_state == first.next_rng_state and state.progression_rng_state != initial_growth,"only activated offer consumes progression RNG once")
	t.check(state.rng_state == combat_rng and Fixture.types(events,"upgrade_opened").size() == 1,"growth never advances combat RNG or opens second queued modal")
	t.check(sim.restore(JSON.parse_string(JSON.stringify(state))).get("ok",false),"actual active+pending state restores")
	if state.upgrade_offer.get("source") != "level": return
	var before: Dictionary = state.duplicate(true)
	for ids in [["foreign:offer:1","passive:movement"],[descriptor.offer_id,"passive:unknown"]]:
		t.check(not sim.choose_upgrade(state,ids[0],ids[1]).get("ok",false) and state == before,"invalid choice is exact no-op")
	var selected: String = state.upgrade_offer.options[0].option_id
	var result: Dictionary = sim.choose_upgrade(state,descriptor.offer_id,selected)
	t.check(result.get("ok",false) and state.upgrade_offer.get("offer_id") == state.run_id+":offer:2","successful choice promotes only FIFO descriptor")
	t.check(state.pending_offers.is_empty() and state.offer_seq == 2 and state.active_tick == before.active_tick,"choice does not enqueue duplicate or advance clocks")
	t.check(Fixture.types(result.get("events",[]),"upgrade_applied").size() == 1 and Fixture.types(result.get("events",[]),"upgrade_opened").size() == 1,"choice and promotion events are once-only")
	var promoted := state.duplicate(true)
	t.check(not sim.choose_upgrade(state,descriptor.offer_id,selected).get("ok",false) and state == promoted,"old offer with reusable semantic option ID cannot select next offer")
	t.check(sim.restore(state).get("ok",false),"post-promotion actual state restores without reroll")
	var restored: Dictionary = sim.restore(JSON.parse_string(JSON.stringify(state)))
	if restored.get("ok",false):
		var second_id: String = state.upgrade_offer.offer_id
		var second_choice: String = state.upgrade_offer.options[0].option_id
		var a: Dictionary = sim.choose_upgrade(state,second_id,second_choice)
		var b: Dictionary = sim.choose_upgrade(restored.state,second_id,second_choice)
		t.check(a == b and state == restored.state and state.upgrade_offer.is_empty() and not "upgrade" in state.pause_reasons,"save/resume choice preserves exact events and exits growth pause")
func _choice_counts(t,sim,chapter: Dictionary) -> void:
	for count in [0,1,2]:
		var state: Dictionary = sim.new_run(chapter,42,Fixture.run_config())
		state.equipment = {"blade_slash":5,"spin_slash":5,"odm_dash":5,"reentry_combo":5}
		state.passives = {"damage":5,"armor":5,"pickup_radius":5,"attack_range":5}
		_complete_current_evolutions(sim,state)
		if count > 0: state.passives.armor = 4
		if count > 1: state.passives.damage = 4
		state.player.hp = 20.0
		var events := gain(sim,state,24)
		if count == 0:
			t.check(state.upgrade_offer.is_empty() and state.pending_offers.is_empty() and not "upgrade" in state.pause_reasons,"zero legal choices do not open or pad modal")
			t.check(is_equal_approx(state.player.hp,30.0) and Fixture.types(events,"upgrade_opened").is_empty(),"zero-choice resolution heals exactly ten percent maximum once")
			var hp: float = state.player.hp
			Fixture.step(sim,state,Vector2.ZERO)
			t.check(state.player.hp == hp,"empty-offer recovery does not repeat on next tick")
		else:
			t.check(state.upgrade_offer.get("options",[]).size() == count,"one/two legal cards retain actual count without duplicate filler")
		t.check(sim.restore(state).get("ok",false),"scarce growth result passes actual restore")
func _evolution_and_boss(t,sim,chapter: Dictionary) -> void:
	var state: Dictionary = sim.new_run(chapter,42,Fixture.run_config())
	state.equipment = {"blade_slash":5,"odm_dash":1}
	state.player.attack_ready_ticks.odm_dash = 2147483647
	state.passives = {"movement":3}
	state.player.hp = 40.0
	state.active_tick = 17999
	state.survival_tick = 17999
	# This valid arranged pre-boss build is then driven by real spawn/hit/reward paths.
	t.check(sim.restore(state).get("ok",false),"pre-boss build is actual restore-valid")
	var boss := {"command_id":"boss:ch01_b05","kind":"spawn_boss","payload":{"entity_id":"boss1","boss_id":"ch01_b05","enemy_id":"boss_charger","position":[45,0],"scheduled_tick":18000}}
	Fixture.step(sim,state,Vector2.ZERO,[boss])
	state.entities[0].hp = 36.0
	state.player.attack_ready_ticks.blade_slash = int(state.active_tick)
	t.check(sim.restore(state).get("ok",false),"authored boss with arranged low HP is restore-valid before real killing hit")
	var events := Fixture.step(sim,state,Vector2.ZERO)
	# Authored boss identity/timing, arranged low HP; actual Core hit grants reward.
	t.check(state.stats.minibosses_defeated == 1 and state.tactical_seals == 1 and "boss:ch01_b05" in state.reward_ids_claimed,"actual miniboss death grants one seal and one unique reward")
	t.check(state.player.hp == 65.0 and Fixture.types(events,"boss_defeated").size() == 1,"boss heals25 percent once")
	t.check(state.upgrade_offer.get("source") == "boss" and state.upgrade_offer.get("options",[]).size() > 0 and state.upgrade_offer.options[0].option_id == "evolution:evo_wing_cut","ready evolution leads actual boss offer")
	if state.upgrade_offer.get("source") != "boss" or state.tactical_seals != 1: return
	var ready := state.duplicate(true)
	t.check(sim.restore(ready).get("ok",false),"real reward/evolution-ready checkpoint restores")
	var old_cooldown: int = state.player.attack_ready_ticks.blade_slash
	var old_level: int = state.equipment.blade_slash
	var choice: Dictionary = sim.choose_upgrade(state,state.upgrade_offer.offer_id,"evolution:evo_wing_cut")
	t.check(choice.get("ok",false) and state.evolutions == {"blade_slash":"evo_wing_cut"} and state.tactical_seals == 1,"current evolution preserves the earned seal and replaces attack profile")
	t.check(state.equipment.blade_slash == old_level and state.passives.movement == 3 and state.player.attack_ready_ticks.blade_slash == old_cooldown,"evolution preserves base slot, passive and existing cooldown")
	t.check(sim.restore(state).get("ok",false),"chosen evolution passes actual restore")
	Fixture.step(sim,state,Vector2.ZERO,[boss])
	t.check(state.stats.minibosses_defeated == 1 and state.tactical_seals == 1,"duplicate boss command cannot reward twice")
	var mobile: Dictionary = sim.new_run(chapter,42,Fixture.run_config(1,"doctrine_mobile"))
	mobile.equipment = {"blade_slash":5,"spin_slash":5,"odm_dash":5,"reentry_combo":5}
	mobile.passives = {"movement":5,"damage":5,"armor":5,"max_health":4}
	mobile.player.max_hp = 165.0
	mobile.player.hp = 50.0
	_complete_current_evolutions(sim,mobile)
	gain(sim,mobile,24)
	if mobile.upgrade_offer.is_empty(): return
	var applied: Dictionary = sim.choose_upgrade(mobile,mobile.upgrade_offer.offer_id,"passive:max_health")
	t.check(applied.get("ok",false) and mobile.player.max_hp == 185.0 and mobile.player.hp == 70.0,"mobile health upgrade derives from85 and heals20")
func _bandage_and_terminal(t,sim,chapter: Dictionary) -> void:
	for hp in [30.0,30.01,10.0]:
		var state: Dictionary = sim.new_run(chapter,42,Fixture.run_config(1,"doctrine_standard","evo_wing_cut","field_bandage"))
		state.player.hp = hp
		var events := Fixture.step(sim,state,Vector2.ZERO)
		var should_fire: bool = hp <= 30.0
		t.check(state.supply_used == should_fire and state.player.hp == hp+(25.0 if should_fire else 0.0),"bandage threshold is inclusive30 percent and heals25")
		t.check(Fixture.types(events,"supply_used").size() == (1 if should_fire else 0),"bandage emits exactly one presentation event only when used")
		var restored: Dictionary = sim.restore(JSON.parse_string(JSON.stringify(state)))
		t.check(restored.get("ok",false),"bandage state roundtrips")
		if should_fire and restored.get("ok",false):
			restored.state.player.hp = 1.0
			var replay := Fixture.step(sim,restored.state,Vector2.ZERO)
			t.check(restored.state.player.hp == 1.0 and Fixture.types(replay,"supply_used").is_empty(),"save/resume never reuses spent bandage")
	var lethal: Dictionary = sim.new_run(chapter,42,Fixture.run_config(1,"doctrine_standard","evo_wing_cut","field_bandage"))
	lethal.player.hp = 1.0
	lethal.passives = {"recovery":5}
	add_xp(lethal,24)
	var events := Fixture.step(sim,lethal,Vector2.ZERO,[Fixture.hazard("lethal")])
	t.check(lethal.phase == "dead" and lethal.player.hp == 0 and not lethal.supply_used,"lethal damage wins before bandage and regeneration")
	t.check(lethal.upgrade_offer.is_empty() and lethal.pending_offers.is_empty() and Fixture.types(events,"upgrade_opened").is_empty(),"death in levelup tick prevents growth modal")
	t.check(sim.restore(lethal).get("ok",false),"death with suppressed growth restores")
	var abandoned: Dictionary = sim.new_run(chapter,42,Fixture.run_config())
	gain(sim,abandoned,56)
	var ended: Array = sim.abandon_run(abandoned)
	t.check(abandoned.phase == "abandoned" and abandoned.player.hp > 0 and abandoned.upgrade_offer.is_empty() and abandoned.pending_offers.is_empty(),"abandon is distinct terminal preserving living HP and closing growth")
	t.check(Fixture.types(ended,"run_ended").size() == 1 and ended[0].payload.result == "abandoned","abandon emits exactly one distinct terminal result")
	var frozen := abandoned.duplicate(true)
	t.check(Fixture.step(sim,abandoned,Vector2.RIGHT).is_empty() and sim.abandon_run(abandoned).is_empty() and abandoned == frozen,"terminal step and repeated abandon do not mutate")
	t.check(sim.restore(abandoned).get("ok",false),"abandoned actual state restores")
func _pause(t,sim,chapter: Dictionary) -> void:
	var state := preload("res://tests/core/test_rebuild_attack_events.gd").evolved_state(sim,chapter,"evo_crossfire")
	Fixture.step(sim,state,Vector2.ZERO,[{"command_id":"target","kind":"spawn_enemy","payload":{"entity_id":"target","enemy_id":"brute","position":[60,0]}}])
	for reason in ["user","rotation","background","controller_lost","slow_frame"]:
		sim.set_pause(state,reason,true)
		var frozen := state.duplicate(true)
		for index in 3: t.check(Fixture.step(sim,state,Vector2.RIGHT).is_empty() and state == frozen,"pause freezes clocks, all RNG and saved reservations: "+reason)
		sim.set_pause(state,reason,false)
static func add_xp(state: Dictionary, amount: int) -> void:
	state.drops.append({"id":state.next_entity_id,"position":state.player.position.duplicate(),"xp":amount})
	state.next_entity_id += 1
static func gain(sim,state: Dictionary,amount: int) -> Array[Dictionary]:
	add_xp(state,amount)
	return Fixture.step(sim,state,Vector2.ZERO)
func _hostile_offers_and_commands(t,sim,chapter: Dictionary) -> void:
	var state: Dictionary = sim.new_run(chapter,42,Fixture.run_config())
	gain(sim,state,56)
	for patch in [{"source":"levelup"},{"level_ordinal":1},{"offer_id":"foreign:offer:1"},{"selected_option_id":"equipment:missing"},{"extra":1}]:
		var invalid := state.duplicate(true)
		invalid.upgrade_offer.merge(patch,true)
		t.check(not sim.restore(invalid).get("ok",false),"malformed active offer rejected: "+str(patch))
	var invalid := state.duplicate(true)
	invalid.pending_offers[0].options = []
	t.check(not sim.restore(invalid).get("ok",false),"pending cannot smuggle prematerialized options/RNG")
	invalid = state.duplicate(true)
	invalid.pending_offers[0].offer_id = invalid.upgrade_offer.offer_id
	t.check(not sim.restore(invalid).get("ok",false),"queue IDs cannot alias active offer")
	invalid = state.duplicate(true)
	invalid.upgrade_offer.options[0].next_level += 1
	var before := invalid.duplicate(true)
	t.check(not sim.choose_upgrade(invalid,invalid.upgrade_offer.offer_id,invalid.upgrade_offer.options[0].option_id).get("ok",false) and invalid == before,"stale next-level choice refuses atomically without repairing source")
	for patch in [{"enemy_id":"walker"},{"scheduled_tick":17999},{"scheduled_tick":18000.5},{"boss_id":"ch01_final_armored"}]:
		var run: Dictionary = sim.new_run(chapter,42,Fixture.run_config())
		run.active_tick = 17999
		run.survival_tick = 17999
		var command := {"command_id":"forgedboss","kind":"spawn_boss","payload":{"entity_id":"forged","boss_id":"ch01_b05","enemy_id":"boss_charger","position":[45,0],"scheduled_tick":18000}}
		command.payload.merge(patch,true)
		Fixture.step(sim,run,Vector2.ZERO,[command])
		t.check(run.entities.is_empty() and run.boss_ids_fired.is_empty() and run.command_ids_applied.is_empty(),"forged boss definition/schedule is refused before side effects: "+str(patch))
	var early: Dictionary = sim.new_run(chapter,42,Fixture.run_config())
	Fixture.step(sim,early,Vector2.ZERO,[{"command_id":"early","kind":"spawn_boss","payload":{"entity_id":"earlyboss","boss_id":"ch01_b05","enemy_id":"boss_charger","position":[45,0],"scheduled_tick":18000}}])
	t.check(early.entities.is_empty() and early.boss_ids_fired.is_empty(),"real boss cannot spawn before authored survival threshold")
func _large_xp_queue(t,sim,chapter: Dictionary) -> void:
	var state: Dictionary=sim.new_run(chapter,42,Fixture.run_config())
	state.equipment={"blade_slash":5}
	state.passives={"movement":3}
	state.active_tick=17999
	state.survival_tick=17999
	state.player.attack_ready_ticks.blade_slash=18001
	Fixture.step(sim,state,Vector2.ZERO,[{"command_id":"cap_boss","kind":"spawn_boss","payload":{"entity_id":"cap_boss","boss_id":"ch01_b05","enemy_id":"boss_charger","position":[45,0],"scheduled_tick":18000}}])
	state.entities[0].hp=36.0
	t.check(sim.restore(state).get("ok",false),"large XP/boss arrangement passes restore before driving real hit")
	add_xp(state,1000000)
	Fixture.step(sim,state,Vector2.ZERO)
	t.check(state.player.level==256 and state.offer_seq==256 and state.pending_offers.size()==255,"level processing reserves one of256 descriptor slots for same-tick boss reward")
	var bosses:=0
	for descriptor in state.pending_offers:
		if descriptor.source=="boss": bosses+=1
	t.check(bosses==1 and state.tactical_seals==1,"large level burst cannot drop earned boss growth descriptor")
	var earned:=255*24+8*(254*255/2)
	t.check(state.player.xp==1000000-earned,"bounded processing preserves exact unprocessed XP")
	t.check(sim.restore(state).get("ok",false),"full FIFO batch with remaining XP restores")
	var saturated: Dictionary=sim.new_run(chapter,42,Fixture.run_config())
	saturated.equipment={"blade_slash":5,"spin_slash":5,"odm_dash":5,"reentry_combo":5}
	saturated.passives={"damage":5,"armor":5,"pickup_radius":5,"attack_range":5}
	_complete_current_evolutions(sim,saturated)
	gain(sim,saturated,1000000)
	t.check(saturated.player.level==257 and saturated.offer_seq==256 and saturated.upgrade_offer.is_empty(),"zero-choice burst resolves only bounded256 thresholds in one tick")
	var remaining: int=saturated.player.xp
	Fixture.step(sim,saturated,Vector2.ZERO)
	t.check(saturated.player.level>257 and saturated.player.xp<remaining and sim.restore(saturated).get("ok",false),"leftover XP resumes on next unpaused tick without a new drop")
func _reused_option_id(t,sim,chapter: Dictionary) -> void:
	var state: Dictionary=sim.new_run(chapter,42,Fixture.run_config())
	state.equipment={"blade_slash":1,"spin_slash":5,"odm_dash":5,"reentry_combo":5}
	state.passives={"damage":5,"armor":5,"pickup_radius":5,"attack_range":5}
	_complete_current_evolutions(sim,state)
	gain(sim,state,56)
	var old_offer: String=state.upgrade_offer.offer_id
	var semantic: String=state.upgrade_offer.options[0].option_id
	t.check(sim.choose_upgrade(state,old_offer,semantic).get("ok",false),"single-card first choice succeeds")
	t.check(state.upgrade_offer.options.size()==1 and state.upgrade_offer.options[0].option_id==semantic and state.upgrade_offer.options[0].level==2,"next offer deliberately reuses same semantic option ID at newer level")
	var before:=state.duplicate(true)
	t.check(not sim.choose_upgrade(state,old_offer,semantic).get("ok",false) and state==before,"old same-named option is bound to old offer and cannot touch promoted state")
func _boss_offer_exhaustion(t,sim,chapter: Dictionary) -> void:
	var state: Dictionary=sim.new_run(chapter,42,Fixture.run_config())
	state.equipment={"blade_slash":5}
	state.active_tick=35999
	state.survival_tick=35999
	state.player.attack_ready_ticks.blade_slash=36001
	state.player.level=2147483647
	state.boss_ids_fired=["ch01_b05"]
	state.reward_ids_claimed=["boss:ch01_b05"]
	state.stats.minibosses_defeated=1
	state.stats.kills=1
	state.tactical_seals=1
	Fixture.step(sim,state,Vector2.ZERO,[{"command_id":"exhaust_boss","kind":"spawn_boss","payload":{"entity_id":"exhaust_boss","boss_id":"ch01_b10","enemy_id":"boss_sweeper","position":[45,0],"scheduled_tick":36000}}])
	state.entities[0].hp=36.0
	state.offer_seq=2147483647
	t.check(sim.restore(state).get("ok",false),"offer sequence endpoint is valid before a new boss reward")
	var before:=state.duplicate(true)
	var events:=Fixture.step(sim,state,Vector2.ZERO)
	t.check(events.is_empty() and state==before,"no sequence space for earned boss offer rolls back hit/reward/tick instead of dropping growth")
func _derived_metadata_precision(t,sim,chapter: Dictionary) -> void:
	var state: Dictionary=sim.new_run(chapter,42,Fixture.run_config())
	state.equipment={"blade_slash":4,"spin_slash":5,"odm_dash":5,"reentry_combo":5}
	state.passives={"damage":5,"armor":4,"pickup_radius":5,"attack_range":5}
	_complete_current_evolutions(sim,state)
	gain(sim,state,56)
	t.check(sim.choose_upgrade(state,state.upgrade_offer.offer_id,"passive:armor").get("ok",false),"actual first scarce choice promotes the blade4-to5 range-modified card")
	var restored: Dictionary=sim.restore(JSON.parse_string(JSON.stringify(state,"",true,true)))
	t.check(restored.get("ok",false) and restored.get("state")==state,"derived range124.80000000000001 survives Godot JSON1ULP parsing and canonical decoration reconstruction")
	if restored.get("ok",false):
		var direct: Dictionary=sim.choose_upgrade(state,state.upgrade_offer.offer_id,"equipment:blade_slash")
		var resumed: Dictionary=sim.choose_upgrade(restored.state,restored.state.upgrade_offer.offer_id,"equipment:blade_slash")
		t.check(direct==resumed and state==restored.state,"roundtripped range-modified growth choice remains deterministic")
func _ledger_capacity_and_sources(t,sim,chapter: Dictionary) -> void:
	var state: Dictionary=sim.new_run(chapter,42,Fixture.run_config())
	state.equipment={"blade_slash":5,"spin_slash":5,"odm_dash":5,"reentry_combo":5}
	state.passives={"damage":5,"armor":5,"pickup_radius":5,"attack_range":5}
	_complete_current_evolutions(sim,state)
	add_xp(state,100000000)
	for tick in 17:
		var before:=state.duplicate(true)
		var events:=Fixture.step(sim,state,Vector2.ZERO)
		t.check(sim.restore(state).get("ok",false),"zero-choice burst remains restore-valid at receipt capacity tick"+str(tick))
		if tick==16: t.check(events.is_empty() and state==before and state.reward_ids_claimed.size()==4096,"full ledger refuses overflowing tick atomically without pruning receipts")
	for level in [1,2]:
		var forged: Dictionary=sim.new_run(chapter,42,Fixture.run_config())
		forged.player.level=level
		forged.offer_seq=1
		var proposal: Dictionary=Growth.new().materialize(forged,{"offer_id":forged.run_id+":offer:1","source":"boss","level_ordinal":level})
		t.check(proposal.get("ok",false),"pure materializer remains structural, not a boss reward authority")
		forged.upgrade_offer=proposal.offer
		forged.progression_rng_state=proposal.next_rng_state
		forged.pause_reasons=["upgrade"]
		var before:=forged.duplicate(true)
		t.check(not sim.restore(forged).get("ok",false) and not sim.choose_upgrade(forged,forged.upgrade_offer.offer_id,forged.upgrade_offer.options[0].option_id).get("ok",false) and forged==before,"boss-source growth cannot exist without an actual earned boss reward")
	var duplicate: Dictionary=sim.new_run(chapter,42,Fixture.run_config())
	gain(sim,duplicate,56)
	duplicate.pending_offers[0].level_ordinal=2
	t.check(not sim.restore(duplicate).get("ok",false),"one level ordinal cannot mint two simultaneous level growth descriptors")
	var inflation: Dictionary=sim.new_run(chapter,42,Fixture.run_config())
	inflation.offer_seq=1
	t.check(not sim.restore(inflation).get("ok",false),"offer high-water cannot exceed earned level-ups plus actual bosses")

# Scarce/zero-choice fixtures must exhaust the final stage as well as base five.
# Only current zero-cost recipes are applied; preserved legacy definitions keep
# their original arranged-state behavior and independent seal ledger tests.
func _complete_current_evolutions(sim,state: Dictionary) -> void:
	if sim._catalog.evolutions.final_stage_level() != 6: return
	for id in sim._catalog.evolutions.ids():
		var recipe: Dictionary = sim._catalog.evolutions.definition(id)
		if state.equipment.get(recipe.base_item_id,0) != 5: continue
		var ready := true
		for required in recipe.required_equipment:
			ready = ready and int(state.equipment.get(required.equipment_id,0)) >= int(required.level)
		for required in recipe.required_passives:
			ready = ready and int(state.passives.get(required.passive_id,0)) >= int(required.level)
		if ready: state.evolutions[recipe.base_item_id] = id
