extends RefCounted
# NEW E1 isolation: SHAPE-ONLY R0 run factory, never real Core/Store validity.
const Service = preload("res://game/economy/supply_service.gd")
const Fixture = preload("res://tests/fixtures/evolution_supply_fixture.gd")
const MAX := 2147483647
var _fixture = Fixture.new()
func run(t) -> void:
	print("E1 SERVICE ISOLATION: SHAPE-ONLY R0 factory; no real Core, disk or migration proof")
	_purchase_cases(t)
	_loadout_start_cases(t)
	_settlement_cases(t)
	_claimed_growth_settlement_cases(t)
	_invalid_authority_cases(t)
func _service():
	return Service.new(_fixture.make_run)
func _save(balance: int = 40) -> Dictionary:
	var save: Dictionary = _fixture.game_save()
	save.profile.supply_credits = balance
	return save
func _chapter() -> Dictionary:
	return {"chapter_id":"chapter_01_shiganshina","content_revision":"ch01.3-rebuild.7-grabber-hand","doctrine_ids":["doctrine_standard","doctrine_mobile","doctrine_artillery"],"evolution_ids":["evo_wing_cut","evo_crossfire"]}
func _purchase_id(save: Dictionary, item: String) -> String:
	return "purchase:%s:%d:%s" % [save.career_id,int(save.store_revision),item]
func _start_id(save: Dictionary) -> String:
	return "start:%s:%d" % [save.career_id,int(save.next_run_serial)]
func _failure(t, result: Dictionary, code: String, label: String) -> void:
	t.check(result.get("ok") == false and result.get("error_code") == code,label)
	t.check(not result.has("candidate"),label + " no candidate")
func _same(a: Variant,b: Variant) -> bool:
	if a is float and is_nan(a): return b is float and is_nan(b)
	if a is Dictionary:
		if not b is Dictionary or a.size() != b.size(): return false
		for key in a:
			if not b.has(key) or not _same(a[key],b[key]): return false
		return true
	if a is Array:
		if not b is Array or a.size() != b.size(): return false
		for i in a.size():
			if not _same(a[i],b[i]): return false
		return true
	return a == b
func _purchase_cases(t) -> void:
	var service = _service()
	var save := _save()
	var before := save.duplicate(true)
	var id := _purchase_id(save,"doctrine_mobile")
	var purchased: Dictionary = service.prepare_purchase(save,"doctrine_mobile",id,0)
	t.check(purchased.get("ok") == true,"E1 40-credit purchase succeeds")
	t.check(_same(save,before),"E1 purchase leaves original authority untouched")
	if not purchased.get("ok",false): return
	var candidate: Dictionary = purchased.candidate
	t.check(candidate.profile.supply_credits == 0,"E1 40 becomes zero exactly")
	t.check(candidate.profile.owned_doctrine_ids == ["doctrine_standard","doctrine_mobile"],"E1 one permanent unlock")
	t.check(candidate.profile.loadout.doctrine_id == "doctrine_standard","E1 buying does not equip")
	t.check(candidate.store_revision == save.store_revision,"E1 only Store may advance revision")
	t.check(purchased.receipt.price == 40 and purchased.receipt.owned_after == 1 and purchased.receipt.balance_after == 0,"E1 honest purchase receipt")
	purchased.receipt.balance_after = 999
	t.check(candidate.purchase_receipts[0].balance_after == 0,"E1 returned receipt does not alias candidate ledger")
	candidate.store_revision += 1 # Simulated commit revision only; NOT disk acceptance.
	var retry: Dictionary = service.prepare_purchase(candidate,"doctrine_mobile",id,0)
	t.check(retry.get("already_applied") == true and not retry.has("candidate"),"E1 same purchase retry is receipt-only")
	retry.receipt.price = 99
	t.check(candidate.purchase_receipts[0].price == 40,"E1 retry receipt is private")
	_failure(t,service.prepare_purchase(candidate,"field_bandage",id,0),"request_conflict","E1 same ID different purchase rejects")
	_failure(t,service.prepare_purchase(_save(39),"doctrine_mobile",id,0),"insufficient_funds","E1 39 cannot buy doctrine")
	_failure(t,service.prepare_purchase(candidate,"doctrine_mobile",_purchase_id(candidate,"doctrine_mobile"),1),"already_owned","E1 permanent ownership cannot rebuy")
	var full := _save(100)
	full.profile.consumables.field_bandage = 9
	_failure(t,service.prepare_purchase(full,"field_bandage",_purchase_id(full,"field_bandage"),0),"inventory_full","E1 full bandage stock rejects")
	_failure(t,service.prepare_purchase(save,"unknown",_purchase_id(save,"unknown"),0),"invalid_item","E1 unknown sale rejects")
	_failure(t,service.prepare_purchase(save,"field_bandage",_purchase_id(save,"field_bandage"),1),"stale_revision","E1 stale purchase revision rejects")
	_failure(t,service.prepare_purchase(save,"field_bandage","invented",0),"request_conflict","E1 arbitrary purchase ID rejects")
	var active: Dictionary = _fixture.game_save("started")
	active.profile.supply_credits = 100
	_failure(t,service.prepare_purchase(active,"field_bandage",_purchase_id(active,"field_bandage"),1),"active_run","E1 active run cannot shop")
	var exhausted := _save()
	exhausted.store_revision = MAX
	_failure(t,service.prepare_purchase(exhausted,"field_bandage",_purchase_id(exhausted,"field_bandage"),MAX),"counter_exhausted","E1 purchase cannot overflow revision")
	var history := _save(1000)
	for revision in range(65):
		history.purchase_receipts.append({"request_id":"purchase:%s:%d:field_bandage" % [history.career_id,revision],"item_id":"field_bandage","expected_revision":revision,"price":15,"balance_after":1000,"owned_after":1})
	history.purchase_receipts.pop_front()
	history.store_revision = 65
	_failure(t,service.prepare_purchase(history,"field_bandage","purchase:%s:0:field_bandage" % history.career_id,0),"stale_revision","E1 pruned purchase ID cannot debit again")
	var purchased_again: Dictionary = service.prepare_purchase(history,"field_bandage",_purchase_id(history,"field_bandage"),65)
	t.check(purchased_again.get("ok") == true and purchased_again.candidate.purchase_receipts.size() == 64,"E1 purchase receipt ledger stays bounded")
	var view_save := _save(39)
	var view_before := view_save.duplicate(true)
	var view: Dictionary = service.shop_view(view_save)
	for row in view.items:
		if row.item_id.begins_with("doctrine_"):
			t.check(row.description.count("기본 체력") == 1,"E1 doctrine benefit is not duplicated on card")
			t.check(not row.can_purchase and row.balance_after == 39,"E1 blocked price leaves actual after balance")
	view.loadout.doctrine_id = "unknown"
	t.check(_same(view_save,view_before),"E1 view cannot mutate its actual input authority")
	t.check(view.loadout_options.doctrines.size() == 3 and view.loadout_options.targets.size() == 2 and view.loadout_options.supplies.size() == 2,"E1 meaningful loadout options supplied")
	for target in view.loadout_options.targets:
		t.check(target.seal_cost == 1 and target.requirements.size() == 2,"E1 shop target uses actual recipe costs")
		for requirement in target.requirements: t.check(not requirement.name.is_empty(),"E1 named target prerequisite")
func _loadout_start_cases(t) -> void:
	var service = _service()
	var save := _save()
	save.profile.owned_doctrine_ids.append("doctrine_mobile")
	save.profile.consumables.field_bandage = 1
	var selection := {"doctrine_id":"doctrine_mobile","target_evolution_id":"evo_wing_cut","supply_item_id":"field_bandage"}
	var before := save.duplicate(true)
	var prepared: Dictionary = service.prepare_loadout(save,selection,0)
	t.check(prepared.get("ok") == true,"E1 owned loadout prepares")
	t.check(_same(save,before),"E1 loadout preserves original")
	if not prepared.get("ok",false): return
	t.check(prepared.candidate.profile.consumables.field_bandage == 1 and prepared.candidate.store_revision == 0,"E1 loadout consumes nothing and retains revision")
	selection.doctrine_id = "doctrine_standard"
	t.check(prepared.candidate.profile.loadout.doctrine_id == "doctrine_mobile","E1 selection is copied")
	var extra: Dictionary = prepared.candidate.profile.loadout.duplicate(true)
	extra["grant_credits"] = 500
	_failure(t,service.prepare_loadout(save,extra,0),"invalid_loadout","E1 rejects unrecognized loadout payload fields")
	var unknown := selection.duplicate(true)
	unknown.doctrine_id = "doctrine_artillery"
	_failure(t,service.prepare_loadout(save,unknown,0),"invalid_loadout","E1 unowned doctrine rejects")
	var selected: Dictionary = prepared.candidate
	var start_id := _start_id(selected)
	var selected_before := selected.duplicate(true)
	var started: Dictionary = service.prepare_run_start(selected,_chapter(),42,start_id,0)
	t.check(started.get("ok") == true,"E1 NEW content revision starts")
	t.check(_same(selected,selected_before),"E1 start preserves original")
	if not started.get("ok",false): return
	var candidate: Dictionary = started.candidate
	t.check(candidate.next_run_serial == 2 and candidate.checkpoint.run_serial == 1,"E1 start advances serial once and binds checkpoint")
	t.check(candidate.profile.consumables.field_bandage == 0 and candidate.profile.loadout.supply_item_id == "field_bandage","E1 start consumes exactly one while preserving equipped preference")
	t.check(candidate.checkpoint.run_config.prepared_supply == "field_bandage" and candidate.checkpoint.supply_used == false,"E1 bandage remains unused combat supply")
	t.check(candidate.store_revision == 0,"E1 start candidate retains revision")
	candidate.store_revision = 1
	var retry: Dictionary = service.prepare_run_start(candidate,_chapter(),42,start_id,0)
	t.check(retry.get("already_applied") == true and not retry.has("candidate"),"E1 duplicate start receipt-only after supply consumed")
	_failure(t,service.prepare_run_start(candidate,_chapter(),43,start_id,0),"request_conflict","E1 conflicting start seed rejects")
	var different: Dictionary = _chapter()
	different.content_revision = "ch01.3"
	_failure(t,service.prepare_run_start(candidate,different,42,start_id,0),"request_conflict","E1 conflicting duplicate content rejects")
	_failure(t,service.prepare_run_start(selected,different,42,start_id,0),"content_mismatch","E1 old revision cannot start")
	var absent := _save()
	absent.profile.loadout.supply_item_id = "field_bandage"
	_failure(t,service.prepare_run_start(absent,_chapter(),42,_start_id(absent),0),"invalid_loadout","E1 absent equipped supply prevents new consumption")
	var exhausted := _save()
	exhausted.next_run_serial = MAX
	# An inconsistent null checkpoint cannot be turned into a new career.
	_failure(t,service.prepare_run_start(exhausted,_chapter(),42,_start_id(exhausted),0),"invalid_game_save","E1 missing prior checkpoint never resets high-water")
	for field in ["chapter_id","doctrine_ids","evolution_ids"]:
		var malformed := _chapter()
		malformed[field] = 123
		_failure(t,service.prepare_run_start(_save(),malformed,42,_start_id(_save()),0),"invalid_chapter","E1 malformed chapter field fails safely " + field)
	var bad_factory = Service.new(func(_c,_s,_config): return {"schema_version":2})
	_failure(t,bad_factory.prepare_run_start(_save(),_chapter(),42,_start_id(_save()),0),"invalid_snapshot","E1 malformed factory output rejects without consuming")
func _terminal(save: Dictionary, phase: String = "dead") -> Dictionary:
	var state: Dictionary = save.checkpoint.duplicate(true)
	state.phase = phase
	state.active_tick = 36000
	state.survival_tick = 36000
	state.stats.kills = 100
	state.stats.minibosses_defeated = 1
	state.reward_ids_claimed = ["boss:ch01_b05"]
	state.tactical_seals = 1
	state.player.hp = 0 if phase == "dead" else 50
	return state
func _settlement_cases(t) -> void:
	var service = _service()
	var save: Dictionary = _fixture.game_save("started")
	var terminal := _terminal(save)
	var before := save.duplicate(true)
	var terminal_before := terminal.duplicate(true)
	var settled: Dictionary = service.prepare_settlement(save,terminal)
	t.check(settled.get("ok") == true,"E1 terminal 10-minute run prepares settlement")
	t.check(_same(save,before) and _same(terminal,terminal_before),"E1 settlement preserves both inputs")
	if not settled.get("ok",false): return
	t.check(settled.receipt.breakdown == {"kills":10,"survival":30,"minibosses":15,"clear":0} and settled.receipt.total == 55,"E1 independent 100-kill ten-minute one-boss reward =55")
	t.check(settled.candidate.profile.supply_credits == 55 and settled.candidate.settled_through_serial == 1 and settled.candidate.store_revision == save.store_revision,"E1 settlement candidate atomically holds rewards/checkpoint/high-water")
	var committed: Dictionary = settled.candidate
	committed.store_revision += 1
	var retry: Dictionary = service.prepare_settlement(committed,terminal)
	t.check(retry.get("already_applied") == true and not retry.has("candidate"),"E1 repeat terminal never prepares second commit")
	for field in ["run_config","seed","chapter_id","content_revision","fingerprint"]:
		var wrong := terminal.duplicate(true)
		match field:
			"run_config": wrong.run_config.doctrine_id = "doctrine_artillery"
			"seed": wrong.seed += 1
			"chapter_id": wrong.chapter_id = "chapter_other"
			"content_revision": wrong.content_revision = "future"
			"fingerprint": wrong.rules.content_fingerprint = "different"
		_failure(t,service.prepare_settlement(save,wrong),"invalid_snapshot","E1 settlement binds immutable " + field)
	for phase in ["survival","evacuation","invented"]:
		var wrong := terminal.duplicate(true)
		wrong.phase = phase
		_failure(t,service.prepare_settlement(save,wrong),"invalid_snapshot","E1 nonterminal cannot settle " + phase)
	for mutation in ["duplicate_boss","armored_reward","fraction_kills","overclock","bad_seals","unknown_reward"]:
		var wrong := terminal.duplicate(true)
		match mutation:
			"duplicate_boss": wrong.reward_ids_claimed.append("boss:ch01_b05")
			"armored_reward": wrong.reward_ids_claimed = ["boss:ch01_armored"]
			"fraction_kills": wrong.stats.kills = 0.5
			"overclock": wrong.survival_tick = wrong.active_tick+1
			"bad_seals": wrong.tactical_seals = 0
			"unknown_reward": wrong.reward_ids_claimed.append("forged_reward")
		_failure(t,service.prepare_settlement(save,wrong),"invalid_snapshot","E1 rejects forged settlement evidence " + mutation)
	var max_run := _terminal(save,"won")
	max_run.stats.kills = 10000
	max_run.stats.minibosses_defeated = 5
	max_run.reward_ids_claimed = ["boss:ch01_b05","boss:ch01_b10","boss:ch01_b15","boss:ch01_b20","boss:ch01_b25"]
	max_run.tactical_seals = 5
	max_run.survival_tick = 108000
	max_run.active_tick = 112500
	max_run.final_started_tick = 108000
	max_run.evacuation_ready = true
	max_run.player.position = [0,350]
	var maximum: Dictionary = service.prepare_settlement(save,max_run)
	t.check(maximum.get("ok") == true and maximum.receipt.total == 185,"E1 hand-computed economic maximum185 (Core physical validity deferred)")
	var early := max_run.duplicate(true)
	early.active_tick -= 1
	_failure(t,service.prepare_settlement(save,early),"invalid_snapshot","E1 won before 75 active seconds rejects")
	var abandoned: Dictionary = service.prepare_settlement(save,_terminal(save,"abandoned"))
	t.check(abandoned.get("ok") == true and abandoned.receipt.total == 55 and abandoned.receipt.breakdown.clear == 0,"E1 abandonment awards only earned performance")
	for tick in [10799,10800,17999,18000,35999,36000,71999,72000]:
		var sample := _terminal(save)
		sample.active_tick = tick
		sample.survival_tick = tick
		var expected := 0
		for milestone in [10800,18000,36000,72000]:
			if tick >= milestone: expected += 10
		t.check(service.settlement_breakdown(sample).survival == expected,"E1 exact survival threshold " + str(tick))
	var almost := _terminal(save)
	almost.stats.kills = 109
	t.check(service.settlement_breakdown(almost).kills == 10,"E1 kills floor before cap")
	var rich := save.duplicate(true)
	rich.profile.supply_credits = MAX-54
	_failure(t,service.prepare_settlement(rich,terminal),"counter_exhausted","E1 reward overflow fails instead of clamping/loss")
	var next: Dictionary = service.prepare_run_start(committed,_chapter(),42,_start_id(committed),int(committed.store_revision))
	t.check(next.get("ok") == true,"E1 same seed new serial can start")
	if next.get("ok",false):
		var again: Dictionary = service.prepare_settlement(next.candidate,_terminal(next.candidate))
		t.check(again.get("ok") == true and again.candidate.profile.supply_credits == 110,"E1 new serial earns once even at same seed")
	var chain: Dictionary = _fixture.game_save()
	var oldest_terminal: Dictionary = {}
	for serial in range(1,23):
		var run: Dictionary = service.prepare_run_start(chain,_chapter(),42,_start_id(chain),int(chain.store_revision))
		t.check(run.get("ok") == true,"E1 retention chain starts serial " + str(serial))
		if not run.get("ok",false): break
		chain = run.candidate
		chain.store_revision += 1 # Simulated whole-save adoption, not disk acceptance.
		var ended := _terminal(chain)
		if serial == 1: oldest_terminal = ended.duplicate(true)
		var result: Dictionary = service.prepare_settlement(chain,ended)
		t.check(result.get("ok") == true,"E1 retention chain settles serial " + str(serial))
		if not result.get("ok",false): break
		chain = result.candidate
		chain.store_revision += 1
	t.check(chain.settled_through_serial == 22 and chain.next_run_serial == 23 and chain.profile.supply_credits == 22*55,"E1 serial and credits survive real service receipt pruning")
	t.check(chain.settlement_receipts.size() == 20 and chain.settlement_receipts[0].run_serial == 3,"E1 only oldest details pruned")
	var old_retry: Dictionary = service.prepare_settlement(chain,oldest_terminal)
	t.check(old_retry.get("already_applied") == true and not old_retry.has("candidate") and old_retry.receipt.get("details_unavailable") == true,"E1 real pruned retry cannot pay again")
	var aged := committed.duplicate(true)
	aged.next_run_serial = 22
	aged.settled_through_serial = 21
	aged.checkpoint.run_serial = 21
	aged.checkpoint.run_id = str(aged.career_id)+":21"
	aged.checkpoint.run_config.run_serial = 21
	aged.checkpoint.run_config.run_id = aged.checkpoint.run_id
	aged.settlement_receipts.clear()
	for serial in range(2,22):
		var receipt: Dictionary = settled.receipt.duplicate(true)
		receipt.run_serial = serial
		receipt.run_id = "%s:%d" % [aged.career_id,serial]
		receipt.request_id = "settle:" + receipt.run_id
		aged.settlement_receipts.append(receipt)
	var pruned: Dictionary = service.prepare_settlement(aged,terminal)
	t.check(pruned.get("already_applied") == true and pruned.receipt.get("details_unavailable") == true and not pruned.has("candidate"),"E1 pruned settlement remains protected by high-water")
func _invalid_authority_cases(t) -> void:
	var service = _service()
	for mutation in ["future_schema","schema_string","profile_schema_string","checkpoint_schema_string","checkpoint_revision_number","checkpoint_id_number","fraction_revision","nan_balance","bad_career","bad_profile","missing_checkpoint","null_started","foreign_run","wrong_serial","wrong_content","unknown_phase"]:
		var save := _save()
		match mutation:
			"future_schema": save.schema_version = 99
			"schema_string": save.schema_version = "2"
			"profile_schema_string": save.profile.schema_version = "2"
			"fraction_revision": save.store_revision = 0.5
			"nan_balance": save.profile.supply_credits = NAN
			"bad_career": save.career_id = "x"
			"bad_profile": save.profile.loadout.doctrine_id = "unknown"
			"missing_checkpoint": save.erase("checkpoint")
			"null_started": save.next_run_serial = 2
			_:
				save = _fixture.game_save("started")
				match mutation:
					"checkpoint_schema_string": save.checkpoint.schema_version = "2"
					"checkpoint_revision_number": save.checkpoint.content_revision = 3
					"checkpoint_id_number": save.checkpoint.run_id = 123
					"foreign_run": save.checkpoint.run_id = "foreign:1"
					"wrong_serial": save.checkpoint.run_serial = 9
					"wrong_content": save.checkpoint.content_revision = "ch01.3"
					"unknown_phase": save.checkpoint.phase = "invented"
		var before := save.duplicate(true)
		var result: Dictionary = service.prepare_purchase(save,"field_bandage",_purchase_id(save,"field_bandage"),int(save.store_revision))
		t.check(result.get("ok") == false,"E1 invalid authority cannot transact " + mutation)
		t.check(_same(save,before),"E1 invalid authority preserved " + mutation)
		var view: Dictionary = service.shop_view(save)
		t.check(view.get("can_shop") == false and view.get("can_start") == false,"E1 invalid authority view holds all actions " + mutation)
func _claimed_growth_settlement_cases(t) -> void:
	var service = _service()
	var save: Dictionary = _fixture.game_save("started")
	var terminal := _terminal(save)
	terminal.offer_seq = 2
	var prefix: String = "offer:"+terminal.run_id+":offer:"
	terminal.reward_ids_claimed.append(prefix+"1")
	terminal.reward_ids_claimed.append(prefix+"2")
	var result: Dictionary = service.prepare_settlement(save,terminal)
	t.check(result.get("ok") == true and result.receipt.total == 55 and result.receipt.breakdown.minibosses == 15,"E2 R1 claimed growth rewards coexist with boss evidence without extra credit")
	for invalid in [prefix+"0",prefix+"3",prefix+"01",prefix+"+1",prefix+"1.0",prefix+"-1",prefix+"999999999999999999999999999","offer:another-run:offer:1","offer:forged"]:
		var bad := terminal.duplicate(true)
		bad.reward_ids_claimed[1] = invalid
		_failure(t,service.prepare_settlement(save,bad),"invalid_snapshot","E2 R1 malformed claimed growth identity "+invalid)
	var duplicate := terminal.duplicate(true)
	duplicate.reward_ids_claimed.append(prefix+"1")
	_failure(t,service.prepare_settlement(save,duplicate),"invalid_snapshot","E2 R1 duplicate claimed growth evidence rejected")
	for wrong in [null,true,{},[],"2",-1,0.5]:
		var bad := terminal.duplicate(true)
		bad.offer_seq = wrong
		_failure(t,service.prepare_settlement(save,bad),"invalid_snapshot","E2 R1 growth high-water typed before reward comparison")
