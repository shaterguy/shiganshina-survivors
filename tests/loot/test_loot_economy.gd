extends RefCounted
# STATIC DRAFT ONLY: not executed. Core/helper integration is still in progress.
# Uses the existing E1 transcript fixture and terminal arrangement. These tests
# establish Service/receipt boundaries, not playable Core, disk/ACK or APK proof.
# Existing tests/run_all.gd discovers this file under the "loot" suite.
const Service = preload("res://game/economy/supply_service.gd")
const Contracts = preload("res://game/contracts/game_save_contracts.gd")
const Fixture = preload("res://tests/fixtures/evolution_supply_fixture.gd")
const ExistingCases = preload("res://tests/economy/test_supply_service.gd")
const Loot = preload("res://game/loot/loot_rules.gd")
const MAX := 2147483647
var _fixture = Fixture.new()
var _existing = ExistingCases.new()

func run(t) -> void:
	print("LOOT ECONOMY DRAFT: existing E1 shape-only fixture; no Core/Store/ACK proof")
	_fixture_cases(t)
	_receipt_cases(t)
	_settlement_cases(t)
	_evidence_cases(t)

func _new_save() -> Dictionary:
	var save: Dictionary = _fixture.game_save("started")
	save.checkpoint.run_config.loot_rules_version = 1
	save.checkpoint.loot = Loot.initial()
	return save

func _terminal(save: Dictionary, phase: String = "dead") -> Dictionary:
	# Reuse the existing ten-minute / 100 kills / one-boss E1 arrangement.
	var state: Dictionary = _existing._terminal(save,phase)
	state.loot = Loot.initial(int(state.run_config.get("loot_rules_version",1)))
	for index in [0,1]:
		state.loot.chests.append(_chest(state,Loot.field_spec(index)))
	state.loot.chests.append(_chest(state,Loot.boss_spec("ch01_b05")))
	return state

func _chest(state: Dictionary, spec: Dictionary) -> Dictionary:
	return {"id":Loot.chest_id(state.run_id,spec.source,spec.source_id),"source":spec.source,"source_id":spec.source_id,"reward":spec.reward,"status":"expired","stage":"finite","position":[0,0],"address":{},"offer_id":"","result":""}

func _claim_gold(state: Dictionary, index: int) -> void:
	var chest: Dictionary = state.loot.chests[index]
	chest.status = "claimed"
	chest.result = "gold"
	if chest.reward == "skill":
		state.offer_seq += 1
		chest.offer_id = state.run_id+":offer:"+str(int(state.offer_seq))
		state.reward_ids_claimed.append("offer:"+chest.offer_id)
	state.loot.gold += 5
	if Loot.potions_enabled(state) and chest.source == "field":
		state.loot.potions.append({"id":chest.id+":potion","chest_id":chest.id,"status":"expired","stage":chest.stage,"position":chest.position.duplicate(),"address":chest.address.duplicate(true),"born_tick":int(chest.source_id),"heal_amount":20.0,"healed_amount":0.0})

func _receipt_cases(t) -> void:
	var contracts = Contracts.new(Callable())
	var save: Dictionary = _fixture.game_save("started")
	save.settled_through_serial = 1
	var legacy := {"request_id":"settle:"+save.checkpoint.run_id,"run_id":save.checkpoint.run_id,"run_serial":1,"breakdown":{"kills":40,"survival":40,"minibosses":75,"clear":30},"total":185,"balance_after":185}
	t.check(contracts._settlement_receipt_valid(legacy,save),"LOOT old four-part receipt remains valid")
	for gold in [0,5,50,5.0]:
		var receipt := legacy.duplicate(true)
		receipt.loot_rules_version = 1
		receipt.breakdown.loot = gold
		receipt.total += gold
		t.check(contracts._settlement_receipt_valid(receipt,save),"LOOT version1 receipt valid amount "+str(gold))
	var good := legacy.duplicate(true)
	good.loot_rules_version = 1
	good.breakdown.loot = 5
	good.total = 190
	for marker in [1,1.0,2,2.0]:
		var accepted := good.duplicate(true)
		accepted.loot_rules_version = marker
		t.check(contracts._settlement_receipt_valid(accepted,save),"LOOT receipt explicitly accepts v1/v2 precise integers: "+str(marker))
	for marker in [0,3,true,"1",null,1.5,NAN,INF]:
		var bad := good.duplicate(true)
		bad.loot_rules_version = marker
		t.check(not contracts._settlement_receipt_valid(bad,save),"LOOT receipt rejects marker "+str(marker))
	for gold in [-5,1,55,4.5,true,"5",null,NAN,INF]:
		var bad := good.duplicate(true)
		bad.breakdown.loot = gold
		t.check(not contracts._settlement_receipt_valid(bad,save),"LOOT receipt rejects amount "+str(gold))
	for mutation in ["missing_marker","missing_loot","extra_part","wrong_total","base_over_cap"]:
		var bad := good.duplicate(true)
		match mutation:
			"missing_marker": bad.erase("loot_rules_version")
			"missing_loot": bad.breakdown.erase("loot")
			"extra_part": bad.breakdown.bonus = 0
			"wrong_total": bad.total += 5
			"base_over_cap":
				bad.breakdown.kills = 41
				bad.total += 1
		t.check(not contracts._settlement_receipt_valid(bad,save),"LOOT receipt rejects "+mutation)

func _settlement_cases(t) -> void:
	var service = Service.new(_fixture.make_run)
	var legacy_save: Dictionary = _fixture.game_save("started")
	var old: Dictionary = service.prepare_settlement(legacy_save,_existing._terminal(legacy_save))
	t.check(old.get("ok",false) and old.receipt.total == 55 and old.receipt.breakdown.size() == 4 and not old.receipt.has("loot_rules_version"),"LOOT legacy run retains original 55/four-key settlement")
	for phase in ["dead","won","abandoned"]:
		var save := _new_save()
		var terminal := _terminal(save,phase)
		if phase == "won":
			terminal.survival_tick = 108000
			terminal.active_tick = 112500
			terminal.final_started_tick = 108000
			terminal.evacuation_ready = true
			for index in [2,3,4]: terminal.loot.chests.append(_chest(terminal,Loot.field_spec(index)))
		_claim_gold(terminal,0)
		_claim_gold(terminal,1)
		var before := save.duplicate(true)
		var terminal_before := terminal.duplicate(true)
		var settled: Dictionary = service.prepare_settlement(save,terminal)
		var expected := 105 if phase == "won" else 65
		t.check(settled.get("ok",false),"LOOT earned gold settles in "+phase)
		t.check(_existing._same(save,before) and _existing._same(terminal,terminal_before),"LOOT settlement inputs remain unchanged "+phase)
		if not settled.get("ok",false): continue
		t.check(settled.receipt.total == expected and settled.receipt.breakdown.loot == 10 and settled.receipt.loot_rules_version == 1,"LOOT direct gold and saturation each pay5 "+phase)
		var committed: Dictionary = settled.candidate
		committed.store_revision += 1 # Simulated adoption only; not disk/ACK acceptance.
		var balance: int = committed.profile.supply_credits
		var retry: Dictionary = service.prepare_settlement(committed,terminal)
		t.check(retry.get("already_applied",false) and not retry.has("candidate") and committed.profile.supply_credits == balance,"LOOT duplicate settle cannot pay twice "+phase)
	var max_save := _new_save()
	var max_terminal := _terminal(max_save,"won")
	max_terminal.active_tick = 112500
	max_terminal.survival_tick = 108000
	max_terminal.final_started_tick = 108000
	max_terminal.evacuation_ready = true
	max_terminal.stats.kills = 10000
	max_terminal.stats.minibosses_defeated = 5
	max_terminal.tactical_seals = 5
	max_terminal.reward_ids_claimed.clear()
	max_terminal.loot = Loot.initial()
	for index in range(5): max_terminal.loot.chests.append(_chest(max_terminal,Loot.field_spec(index)))
	for boss in Loot.BOSS_IDS:
		max_terminal.reward_ids_claimed.append("boss:"+boss)
		max_terminal.loot.chests.append(_chest(max_terminal,Loot.boss_spec(boss)))
	for index in range(10): _claim_gold(max_terminal,index)
	max_save.profile.supply_credits = MAX-235
	var maximum: Dictionary = service.prepare_settlement(max_save,max_terminal)
	t.check(maximum.get("ok",false) and maximum.receipt.total == 235 and maximum.receipt.breakdown.loot == 50 and maximum.candidate.profile.supply_credits == MAX,"LOOT base185 plus50 exactly fits MAX boundary")
	max_save.profile.supply_credits += 1
	var max_before := max_save.duplicate(true)
	_existing._failure(t,service.prepare_settlement(max_save,max_terminal),"counter_exhausted","LOOT one-over-MAX rejects without clipping")
	t.check(_existing._same(max_save,max_before),"LOOT overflow preserves source max_save")

func _evidence_cases(t) -> void:
	var service = Service.new(_fixture.make_run)
	var save := _new_save()
	# Selected skill receipts and terminal-discarded queued requests earn zero.
	for status in ["claimed","expired"]:
		var no_gold := _terminal(save)
		var chest: Dictionary = no_gold.loot.chests[1]
		no_gold.offer_seq = 1
		chest.offer_id = no_gold.run_id+":offer:1"
		chest.status = status
		if status == "claimed":
			chest.result = "skill"
			no_gold.reward_ids_claimed.append("offer:"+chest.offer_id)
		var settled: Dictionary = service.prepare_settlement(save,no_gold)
		t.check(settled.get("ok",false) and settled.receipt.breakdown.loot == 0 and settled.receipt.total == 55,"LOOT skill or discarded offer earns no gold "+status)
	var valid := _terminal(save)
	_claim_gold(valid,0)
	_claim_gold(valid,1)
	for mutation in ["mismatched_gold","missing_source","early_field","duplicate_chest","foreign_chest","missing_offer_receipt","replayed_offer","marker_only","loot_only","queued_terminal"]:
		var bad := valid.duplicate(true)
		match mutation:
			"mismatched_gold": bad.loot.gold += 5
			"missing_source": bad.reward_ids_claimed.erase("boss:ch01_b05")
			"early_field": bad.survival_tick = 10799
			"duplicate_chest": bad.loot.chests.append(bad.loot.chests[0].duplicate(true))
			"foreign_chest": bad.loot.chests[0].id = "another:run:chest:field:10800"
			"missing_offer_receipt": bad.reward_ids_claimed.erase("offer:"+bad.loot.chests[1].offer_id)
			"replayed_offer": bad.reward_ids_claimed.append("offer:"+bad.loot.chests[1].offer_id)
			"marker_only": bad.erase("loot")
			"loot_only": bad.run_config.erase("loot_rules_version")
			"queued_terminal":
				bad.loot.chests[1].status = "queued"
				bad.loot.chests[1].result = ""
		var before := bad.duplicate(true)
		_existing._failure(t,service.prepare_settlement(save,bad),"invalid_snapshot","LOOT rejects invalid settlement evidence "+mutation)
		t.check(_existing._same(bad,before),"LOOT rejected terminal remains unchanged "+mutation)

func _fixture_cases(t) -> void:
	var historical: Dictionary = _fixture.run_state()
	var before := historical.duplicate(true)
	var config: Dictionary = historical.run_config.duplicate(true)
	var legacy: Dictionary = _fixture.make_run(_existing._chapter(),42,config)
	t.check(not legacy.has("loot") and not legacy.run_config.has("loot_rules_version"),"LOOT existing fixture remains marker-free when requested")
	config.loot_rules_version = 1
	var fresh: Dictionary = _fixture.make_run(_existing._chapter(),42,config)
	t.check(fresh.get("loot") == Loot.initial() and Loot.validate(fresh),"LOOT shape fixture creates version1 initial state")
	fresh.loot.gold = 5
	t.check(_existing._same(_fixture.run_state(),before),"LOOT fixture extension leaves historical JSON reads unchanged")
	var fresh_again: Dictionary = _fixture.make_run(_existing._chapter(),42,config)
	t.check(fresh_again.loot.gold == 0 and fresh_again.loot.chests.is_empty(),"LOOT shape fixture does not share loot between runs")
	var save: Dictionary = _fixture.game_save()
	var service = Service.new(_fixture.make_run)
	var started: Dictionary = service.prepare_run_start(save,_existing._chapter(),42,_existing._start_id(save),0)
	t.check(started.get("ok",false) and started.candidate.checkpoint.run_config.get("loot_rules_version") == 2 and started.candidate.checkpoint.loot == Loot.initial(2),"LOOT new start emits marker and paired empty loot")

	config.loot_rules_version = 2
	var fresh_v2: Dictionary = _fixture.make_run(_existing._chapter(),42,config)
	t.check(fresh_v2.get("loot") == Loot.initial(2) and Loot.validate(fresh_v2),"LOOT shape fixture explicitly creates version2 with empty potions")
