extends SceneTree
const Sim = preload("res://game/core/run_simulation.gd")
const Fixture = preload("res://tests/core/core_fixture.gd")
var failures := 0
func _initialize() -> void:
	var sim = Sim.new()
	probe_queued_level(sim)
	probe_early_escape(sim)
	probe_upgrade_pause(sim)
	probe_forbidden_offer(sim)
	probe_recovery_validation(sim)
	print("REVIEW_CORE failures=%d" % failures)
	quit(1 if failures else 0)
func expect(condition: bool, name: String, observed: Variant) -> void:
	print("%s %s observed=%s" % ["PASS" if condition else "FAIL", name, str(observed)])
	if not condition: failures += 1
func roundtrip(state: Dictionary) -> Dictionary:
	return JSON.parse_string(JSON.stringify(state))
func offer_options() -> Array:
	return [
		{"option_id":"recovery:25","item_id":"field_recovery_25","kind":"recovery","level":0,"next_level":1,"amount":25},
		{"option_id":"recovery:40","item_id":"field_recovery_40","kind":"recovery","level":0,"next_level":1,"amount":40},
		{"option_id":"recovery:60","item_id":"field_recovery_60","kind":"recovery","level":0,"next_level":1,"amount":60}
	]
func install_offer(state: Dictionary) -> void:
	state.upgrade_offer = {"offer_id":"levelup:2","options":offer_options(),"selected_option_id":"recovery:25","source":"levelup"}
	state.pause_reasons = ["upgrade"]
func probe_queued_level(sim) -> void:
	for seed in range(1,101):
		var state: Dictionary = sim.new_run(Fixture.chapter(),seed)
		state.active_tick = 17999
		state.survival_tick = 17999
		Fixture.step(sim,state,Vector2.ZERO,[Fixture.boss("ch01_b05",[10,0])])
		for current in state.upgrade_offer.options:
			for pending in state.pending_offers[0].options:
				if current.item_id != pending.item_id: continue
				var chosen: Dictionary = current.duplicate(true)
				var result: Dictionary = sim.choose_upgrade(state,state.upgrade_offer.offer_id,current.option_id)
				for visible in state.upgrade_offer.options:
					if visible.item_id != chosen.item_id: continue
					var equipped: Dictionary = state.equipment if visible.kind == "equipment" else state.passives
					var actual := int(equipped.get(visible.item_id,0))
					var correct_metadata := int(visible.level)==actual and int(visible.next_level)==actual+1
					var advertised: Dictionary = visible.duplicate(true)
					var second: Dictionary = sim.choose_upgrade(state,state.upgrade_offer.offer_id,visible.option_id)
					expect(correct_metadata,"queued_offer_current_next_level",{"seed":seed,"actual_level_before":actual,"visible":advertised,"actual_level_after":int(equipped.get(visible.item_id,0)),"first_choice_ok":result.ok,"second_choice_ok":second.ok})
					return
	expect(false,"queued_offer_probe_found_shared_item",{})
func probe_early_escape(sim) -> void:
	var state: Dictionary = sim.new_run(Fixture.chapter(),1)
	state.active_tick = 108000
	state.survival_tick = 108000
	Fixture.step(sim,state,Vector2.ZERO,[{"command_id":"final","kind":"begin_evacuation","payload":{"boss_id":"ch01_final_armored","escape_zone":[-20,-20,40,40],"evacuation_ticks":4500}}])
	state.evacuation_ready = true
	var restored: Dictionary = sim.restore(roundtrip(state))
	if restored.ok: Fixture.step(sim,restored.state,Vector2.ZERO,[])
	expect(not restored.ok,"restore_reject_premature_ready",{"accepted":restored.ok,"phase_after_step":restored.state.phase if restored.ok else "rejected","elapsed_ticks":1})
func probe_upgrade_pause(sim) -> void:
	var state: Dictionary = sim.new_run(Fixture.chapter(),1)
	install_offer(state)
	state.pause_reasons.clear()
	var restored: Dictionary = sim.restore(roundtrip(state))
	if restored.ok: Fixture.step(sim,restored.state,Vector2.RIGHT,[])
	expect(not restored.ok,"restore_reject_offer_without_pause",{"accepted":restored.ok,"active_tick":restored.state.active_tick if restored.ok else -1,"offer_retained":not restored.state.upgrade_offer.is_empty() if restored.ok else false})
func probe_forbidden_offer(sim) -> void:
	var chapter: Dictionary = Fixture.chapter()
	chapter.allowed_equipment_ids = ["blade_slash"]
	var state: Dictionary = sim.new_run(chapter,1)
	install_offer(state)
	state.upgrade_offer.options[0] = {"option_id":"equipment:wall_cannon:1","item_id":"wall_cannon","kind":"equipment","level":0,"next_level":1}
	state.upgrade_offer.selected_option_id = "equipment:wall_cannon:1"
	var restored: Dictionary = sim.restore(roundtrip(state))
	var choice: Dictionary = {}
	if restored.ok: choice = sim.choose_upgrade(restored.state,"levelup:2","equipment:wall_cannon:1")
	expect(not restored.ok,"restore_reject_disallowed_equipment_offer",{"accepted":restored.ok,"choice":choice,"equipment":restored.state.equipment if restored.ok else {}})
func probe_recovery_validation(sim) -> void:
	var state: Dictionary = sim.new_run(Fixture.chapter(),1)
	install_offer(state)
	state.upgrade_offer.options[0].erase("amount")
	var restored: Dictionary = sim.restore(roundtrip(state))
	expect(not restored.ok,"restore_reject_recovery_missing_amount",{"accepted":restored.ok})
	if restored.ok:
		print("RECOVERY_CONFIRM_RESULT ",sim.choose_upgrade(restored.state,"levelup:2","recovery:25"))
