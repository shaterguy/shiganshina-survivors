extends SceneTree
const Sim = preload("res://game/core/run_simulation.gd")
const Fixture = preload("res://tests/core/core_fixture.gd")
const Regression = preload("res://tests/core/test_review_regressions.gd")
var checks := 0
var failures := 0
func check(ok: bool, name: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL ",name)
func _initialize() -> void:
	var sim = Sim.new()
	Regression.new().run(self)
	probe_valid_multiqueue(sim)
	probe_duplicate_pending_family(sim)
	probe_duplicate_pending_id(sim)
	print("REVIEW_CORE_EXTENDED checks=%d failures=%d"%[checks,failures])
	quit(1 if failures else 0)
func roundtrip(state: Dictionary) -> Dictionary:
	return JSON.parse_string(JSON.stringify(state))
func probe_valid_multiqueue(sim) -> void:
	var completed := 0
	for seed in range(1,41):
		var state: Dictionary = sim.new_run(Fixture.chapter(),seed)
		state.drops = [{"id":"review_xp","position":[0,0],"xp":500}]
		Fixture.step(sim,state,Vector2.ZERO,[])
		check(state.pending_offers.size()>2,"multiple reward queue generated")
		while not state.upgrade_offer.is_empty():
			var restored: Dictionary = sim.restore(roundtrip(state))
			check(restored.ok,"valid multiqueue roundtrip accepted")
			if not restored.ok: break
			check(restored.state == state,"valid multiqueue roundtrip unchanged")
			var ids: Array = []
			for option in state.upgrade_offer.options:
				check(not option.option_id in ids,"visible option IDs unique")
				ids.append(option.option_id)
				if option.kind == "recovery": continue
				var equipped: Dictionary = state.equipment if option.kind == "equipment" else state.passives
				check(option.level == int(equipped.get(option.item_id,0)) and option.next_level == option.level+1,"visible levels match actual ownership")
			var chosen: Dictionary = state.upgrade_offer.options[0]
			for option in state.upgrade_offer.options:
				if option.item_id == "blade_slash": chosen = option
			var result: Dictionary = sim.choose_upgrade(state,state.upgrade_offer.offer_id,chosen.option_id)
			check(result.ok,"visible choice accepted")
			if not result.ok: break
			if chosen.kind != "recovery":
				var equipped: Dictionary = state.equipment if chosen.kind == "equipment" else state.passives
				check(equipped[chosen.item_id] == chosen.next_level,"applied level matches advertised")
			completed += 1
		check(state.equipment.size()<=4,"equipment cap retained")
	print("VALID_MULTIQUEUE chosen_offers=%d seeds=40"%completed)
func offer(id: String, choices: Array) -> Dictionary:
	return {"offer_id":id,"options":choices,"selected_option_id":choices[0].option_id,"source":"levelup"}
func item_option(level: int) -> Dictionary:
	return {"option_id":"equipment:blade_slash:%d"%(level+1),"item_id":"blade_slash","kind":"equipment","level":level,"next_level":level+1}
func probe_duplicate_pending_family(sim) -> void:
	var state: Dictionary = sim.new_run(Fixture.chapter(),1)
	var regress = Regression.new()
	regress.install_offer(state)
	state.pending_offers = [offer("levelup:3",[item_option(0),item_option(1),regress.recovery_options()[0]])]
	var restored: Dictionary = sim.restore(roundtrip(state))
	check(not restored.ok,"duplicate pending family rejected")
	if restored.ok:
		var first: Dictionary = sim.choose_upgrade(restored.state,"levelup:2","recovery:25")
		var promoted: Dictionary = restored.state.upgrade_offer
		var second: Dictionary = sim.choose_upgrade(restored.state,promoted.offer_id,promoted.options[0].option_id)
		print("DUP_PENDING_FAMILY accepted=true first=",first," promoted=",promoted," second=",second)
func probe_duplicate_pending_id(sim) -> void:
	var state: Dictionary = sim.new_run(Fixture.chapter(),1)
	var regress = Regression.new()
	regress.install_offer(state)
	state.pending_offers = [offer("levelup:2",regress.recovery_options())]
	state.player.hp = 1.0
	var restored: Dictionary = sim.restore(roundtrip(state))
	check(not restored.ok,"duplicate pending offer ID rejected")
	if restored.ok:
		var first: Dictionary = sim.choose_upgrade(restored.state,"levelup:2","recovery:25")
		var second: Dictionary = sim.choose_upgrade(restored.state,"levelup:2","recovery:25")
		print("DUP_PENDING_ID accepted=true first=",first," second=",second," hp=",restored.state.player.hp)
