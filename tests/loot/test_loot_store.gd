extends RefCounted
# STATIC DRAFT ONLY; no execution result. Uses the actual GameSaveStore disk/CAS/
# fault-injection paths and existing E1 shape-only checkpoint validator/factory.
# Does not establish real Core reachability, Android durability or live UI ACK.
# tests/run_all.gd discovers the "loot" suite without runner changes.
const Store = preload("res://game/persistence/game_save_store.gd")
const Service = preload("res://game/economy/supply_service.gd")
const Fixture = preload("res://tests/fixtures/evolution_supply_fixture.gd")
const Existing = preload("res://tests/economy/test_supply_service.gd")
const StoreCases = preload("res://tests/persistence/test_game_save_store.gd")
const LootCases = preload("res://tests/loot/test_loot_economy.gd")
var _fixture = Fixture.new()
var _existing = Existing.new()
var _disk = StoreCases.new()
var _loot = LootCases.new()
var _version := 1

func run(t) -> void:
	print("LOOT STORE DRAFT: real disk/CAS/fault paths, SHAPE checkpoint validator; not executed at authoring")
	for version in [1,2]:
		_version = version
		_commit_and_race_cases(t)
		_fault_cases(t)
	_legacy_receipt_case(t)

func _prepare(t, label: String) -> Dictionary:
	var directory: String = _disk._directory("loot_v"+str(_version)+"_"+label)
	var store = Store.new(directory,_fixture.validate_checkpoint)
	var loaded: Dictionary = store.load_game()
	t.check(loaded.get("ok",false),"LOOT Store initialized "+label)
	if not loaded.get("ok",false): return {}
	var service = Service.new(_fixture.make_run)
	var source: Dictionary = loaded.game_save
	var start: Dictionary = service.prepare_run_start(source,_existing._chapter(),42,_existing._start_id(source),source.store_revision)
	t.check(start.get("ok",false),"LOOT Store new run prepared "+label)
	if not start.get("ok",false): return {}
	if _version == 1:
		# Explicit historical-v1 initial checkpoint arrangement for the same Store
		# fault/CAS matrix. Production new-start still always selects v2.
		start.candidate.checkpoint.run_config.loot_rules_version = 1
		start.candidate.checkpoint.loot = load("res://game/loot/loot_rules.gd").initial(1)
	var started: Dictionary = store.commit_game(start.candidate,source.store_revision)
	t.check(started.get("ok",false),"LOOT Store new run committed "+label)
	if not started.get("ok",false): return {}
	var save: Dictionary = started.game_save
	var terminal: Dictionary = _loot._terminal(save)
	_loot._claim_gold(terminal,0)
	_loot._claim_gold(terminal,1)
	var settled: Dictionary = service.prepare_settlement(save,terminal)
	t.check(settled.get("ok",false) and settled.receipt.total == 65,"LOOT Store 55 base plus10 prepared "+label)
	if not settled.get("ok",false): return {}
	return {"directory":directory,"save":save,"terminal":terminal,"candidate":settled.candidate}

func _check_paid(t, save: Dictionary, revision: int, label: String) -> void:
	t.check(save.store_revision == revision and save.profile.supply_credits == 65 and save.settled_through_serial == 1,"LOOT Store atomic revision/wallet/highwater "+label)
	t.check(save.settlement_receipts.size() == 1,"LOOT Store one settlement receipt "+label)
	if save.settlement_receipts.size() != 1: return
	var receipt: Dictionary = save.settlement_receipts[0]
	t.check(receipt.request_id == "settle:"+save.checkpoint.run_id and receipt.loot_rules_version == int(save.checkpoint.run_config.loot_rules_version) and receipt.breakdown.size() == 5 and receipt.breakdown.loot == 10 and receipt.total == 65,"LOOT Store exact versioned receipt "+label)

func _commit_and_race_cases(t) -> void:
	var packet := _prepare(t,"cas")
	if packet.is_empty(): return
	var service = Service.new(_fixture.make_run)
	var path: String = packet.directory.path_join("game_save.json")
	var before: String = _disk._read(path)
	var source_before: Dictionary = packet.save.duplicate(true)
	var candidate_before: Dictionary = packet.candidate.duplicate(true)
	# Reject an inconsistent forged payout before touching live authority.
	var forged: Dictionary = packet.candidate.duplicate(true)
	forged.profile.supply_credits += 5
	var forged_before := forged.duplicate(true)
	var denied: Dictionary = Store.new(packet.directory,_fixture.validate_checkpoint).commit_game(forged,packet.save.store_revision)
	t.check(denied.get("ok") == false and _disk._read(path) == before,"LOOT Store rejects forged candidate without disk mutation")
	t.check(_existing._same(packet.save,source_before) and _existing._same(packet.candidate,candidate_before),"LOOT Store rejection preserves live source and original candidate")
	t.check(_existing._same(forged,forged_before),"LOOT Store rejection leaves rejected candidate unchanged")
	# A second writer commits settings first; the older settlement CAS must lose.
	var concurrent: Dictionary = packet.save.duplicate(true)
	concurrent.profile.settings.audio_master = 0.7
	var other: Dictionary = Store.new(packet.directory,_fixture.validate_checkpoint).commit_game(concurrent,packet.save.store_revision)
	t.check(other.get("ok",false),"LOOT Store competing settings writer commits")
	if not other.get("ok",false): return
	var other_bytes: String = _disk._read(path)
	var stale: Dictionary = Store.new(packet.directory,_fixture.validate_checkpoint).commit_game(packet.candidate,packet.save.store_revision)
	t.check(stale.get("error_code") == "stale_revision" and _disk._read(path) == other_bytes,"LOOT Store stale settlement cannot overwrite newer authority")
	var refreshed: Dictionary = service.prepare_settlement(other.game_save,packet.terminal)
	t.check(refreshed.get("ok",false),"LOOT Store settlement reprepares from current authority")
	if not refreshed.get("ok",false): return
	var committed: Dictionary = Store.new(packet.directory,_fixture.validate_checkpoint).commit_game(refreshed.candidate,other.game_save.store_revision)
	t.check(committed.get("ok",false),"LOOT Store settlement commit ACK succeeds")
	if not committed.get("ok",false): return
	var reread: Dictionary = Store.new(packet.directory,_fixture.validate_checkpoint).load_game()
	t.check(reread.get("ok",false),"LOOT Store fresh instance readback succeeds")
	if not reread.get("ok",false): return
	_check_paid(t,reread.game_save,int(other.game_save.store_revision)+1,"cas")
	t.check(reread.game_save.profile.settings.audio_master == 0.7,"LOOT Store reprepare preserves concurrent settings")
	var paid_bytes: String = _disk._read(path)
	var retry: Dictionary = service.prepare_settlement(reread.game_save,packet.terminal)
	t.check(retry.get("already_applied",false) and not retry.has("candidate") and _disk._read(path) == paid_bytes,"LOOT Store same-settle readback retry is receipt-only")
	var duplicate: Dictionary = Store.new(packet.directory,_fixture.validate_checkpoint).commit_game(refreshed.candidate,other.game_save.store_revision)
	t.check(duplicate.get("error_code") == "stale_revision" and _disk._read(path) == paid_bytes,"LOOT Store resubmitting old settlement candidate cannot pay twice")
	# Starting the next serial must not remove the first serial's replay fence.
	var current: Dictionary = reread.game_save
	var start: Dictionary = service.prepare_run_start(current,_existing._chapter(),42,_existing._start_id(current),current.store_revision)
	t.check(start.get("ok",false),"LOOT Store next serial prepares after settlement")
	if not start.get("ok",false): return
	var next: Dictionary = Store.new(packet.directory,_fixture.validate_checkpoint).commit_game(start.candidate,current.store_revision)
	t.check(next.get("ok",false),"LOOT Store next serial commits")
	if not next.get("ok",false): return
	var old_retry: Dictionary = service.prepare_settlement(next.game_save,packet.terminal)
	t.check(old_retry.get("already_applied",false) and not old_retry.has("candidate") and next.game_save.profile.supply_credits == 65,"LOOT Store next-run race cannot replay prior payout")

func _fault_cases(t) -> void:
	for stage in ["write","flush","verify","backup","replace","after_replace_before_return","readback_after_replace"]:
		var packet := _prepare(t,stage)
		if packet.is_empty(): return
		var path: String = packet.directory.path_join("game_save.json")
		var old_bytes: String = _disk._read(path)
		var source_before: Dictionary = packet.save.duplicate(true)
		var candidate_before: Dictionary = packet.candidate.duplicate(true)
		var fault = func(at): return ERR_UNAVAILABLE if at == stage else OK
		var failed: Dictionary = Store.new(packet.directory,_fixture.validate_checkpoint,fault).commit_game(packet.candidate,packet.save.store_revision)
		t.check(failed.get("ok") == false,"LOOT Store injected settlement failure "+stage)
		t.check(_existing._same(packet.save,source_before) and _existing._same(packet.candidate,candidate_before),"LOOT Store fault preserves live source/candidate "+stage)
		var reread: Dictionary = Store.new(packet.directory,_fixture.validate_checkpoint).load_game()
		t.check(reread.get("ok",false),"LOOT Store coherent cold read after fault "+stage)
		if not reread.get("ok",false): continue
		var uncertain: bool = stage in ["after_replace_before_return","readback_after_replace"]
		if uncertain:
			t.check(failed.get("error_code") == "commit_outcome_unknown","LOOT Store post-replace reports uncertainty "+stage)
			_check_paid(t,reread.game_save,int(packet.save.store_revision)+1,stage)
		else:
			t.check(_disk._read(path) == old_bytes and _existing._same(reread.game_save,packet.save),"LOOT Store pre-replace retains exact unpaid authority "+stage)
		var service = Service.new(_fixture.make_run)
		var retry: Dictionary = service.prepare_settlement(reread.game_save,packet.terminal)
		if uncertain:
			t.check(retry.get("already_applied",false) and not retry.has("candidate"),"LOOT Store unknown ACK reconciles without second payment "+stage)
		else:
			t.check(retry.get("ok",false) and not retry.get("already_applied",false),"LOOT Store pre-replace failure remains retryable "+stage)
			if not retry.get("ok",false): continue
			var recovered: Dictionary = Store.new(packet.directory,_fixture.validate_checkpoint).commit_game(retry.candidate,reread.game_save.store_revision)
			t.check(recovered.get("ok",false),"LOOT Store safe retry commits "+stage)
			if recovered.get("ok",false): _check_paid(t,recovered.game_save,int(packet.save.store_revision)+1,stage)

func _legacy_receipt_case(t) -> void:
	# Existing marker-free persisted fixture, copied into a unique test directory.
	# This is fixture seeding, not an attempt to start a new legacy-rules run.
	var directory: String = _disk._directory("loot_legacy")
	var source: Dictionary = _fixture.game_save("started")
	_disk._write(directory.path_join("game_save.json"),JSON.stringify(source))
	var store = Store.new(directory,_fixture.validate_checkpoint)
	var loaded: Dictionary = store.load_game()
	t.check(loaded.get("ok",false),"LOOT Store historical authority loads")
	if not loaded.get("ok",false): return
	var service = Service.new(_fixture.make_run)
	var terminal: Dictionary = _existing._terminal(loaded.game_save)
	var settled: Dictionary = service.prepare_settlement(loaded.game_save,terminal)
	t.check(settled.get("ok",false),"LOOT Store historical settlement prepares")
	if not settled.get("ok",false): return
	var committed: Dictionary = store.commit_game(settled.candidate,loaded.game_save.store_revision)
	t.check(committed.get("ok",false),"LOOT Store historical settlement commits")
	if not committed.get("ok",false): return
	var reread: Dictionary = Store.new(directory,_fixture.validate_checkpoint).load_game()
	t.check(reread.get("ok",false),"LOOT Store historical settlement cold readback")
	if not reread.get("ok",false): return
	var receipt: Dictionary = reread.game_save.settlement_receipts[0]
	t.check(receipt.breakdown.size() == 4 and not receipt.has("loot_rules_version") and receipt.total == 55 and reread.game_save.profile.supply_credits == 55,"LOOT Store preserves historical four-key receipt and payout")
