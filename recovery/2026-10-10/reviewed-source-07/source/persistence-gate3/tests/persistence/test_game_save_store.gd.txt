extends RefCounted
const Store = preload("res://game/persistence/game_save_store.gd")
const Service = preload("res://game/economy/supply_service.gd")
const Fixture = preload("res://tests/fixtures/evolution_supply_fixture.gd")
const Cases = preload("res://tests/economy/test_supply_service.gd")
const Core = preload("res://game/core/run_simulation.gd")
const Chapter = preload("res://game/director/chapter_catalog.gd")
var _fixture = Fixture.new()
var _cases = Cases.new()
var _serial := 0
func _directory(label: String) -> String:
	_serial += 1
	return "user://e2_store_%s_%d_%d_%d" % [label,OS.get_process_id(),Time.get_ticks_usec(),_serial]
func _write(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path,FileAccess.WRITE)
	file.store_string(text)
	file.close()
func _read(path: String) -> String:
	return FileAccess.get_file_as_string(path)
func _funded(t, directory: String) -> Dictionary:
	var store = Store.new(directory,_fixture.validate_checkpoint)
	var loaded: Dictionary = store.load_game()
	t.check(loaded.get("ok") == true,"E2 first install creates verified initial authority")
	if not loaded.get("ok",false): return {}
	var service = Service.new(_fixture.make_run)
	var save: Dictionary = loaded.game_save
	var start: Dictionary = service.prepare_run_start(save,_cases._chapter(),42,_cases._start_id(save),save.store_revision)
	var started: Dictionary = store.commit_game(start.candidate,save.store_revision)
	t.check(started.get("ok") == true,"E2 SHAPE run start commits whole authority")
	if not started.get("ok",false): return {}
	var terminal: Dictionary = _cases._terminal(started.game_save)
	var settlement: Dictionary = service.prepare_settlement(started.game_save,terminal)
	var settled: Dictionary = store.commit_game(settlement.candidate,started.game_save.store_revision)
	t.check(settled.get("ok") == true and settled.game_save.profile.supply_credits == 55,"E2 SHAPE settlement commits performance once")
	return settled.get("game_save",{})
func run(t) -> void:
	print("E2 FILE TRANSACTIONS: SHAPE validator/factory for terminal atomicity, separately labelled real initial Core case")
	var service = Service.new(_fixture.make_run)
	var fresh := _directory("no_external_genesis")
	var invented: Dictionary = _cases._save(1000)
	var fabricated: Dictionary = Store.new(fresh,_fixture.validate_checkpoint).commit_game(invented,0)
	t.check(fabricated.get("ok") == false and not FileAccess.file_exists(fresh.path_join("game_save.json")),"E2 caller cannot mint an arbitrary initial authority")
	for stage in ["write","flush","verify","backup","replace","after_replace_before_return","readback_after_replace"]:
		var directory := _directory(stage)
		var save := _funded(t,directory)
		if save.is_empty(): return
		var path := directory.path_join("game_save.json")
		var old_bytes := _read(path)
		var input_before := JSON.stringify(save)
		var request_id := _cases._purchase_id(save,"field_bandage")
		var purchase: Dictionary = service.prepare_purchase(save,"field_bandage",request_id,save.store_revision)
		var candidate_before := JSON.stringify(purchase.candidate)
		var fault = func(at): return ERR_UNAVAILABLE if at == stage else OK
		var store = Store.new(directory,_fixture.validate_checkpoint,fault)
		var result: Dictionary = store.commit_game(purchase.candidate,save.store_revision)
		t.check(result.get("ok") == false,"E2 injected "+stage+" reports failure")
		t.check(JSON.stringify(save) == input_before and JSON.stringify(purchase.candidate) == candidate_before,"E2 failed commit preserves caller authority/candidate "+stage)
		var reread: Dictionary = Store.new(directory,_fixture.validate_checkpoint).load_game()
		t.check(reread.get("ok") == true,"E2 coherent authority remains readable after "+stage)
		if not reread.get("ok",false): continue
		var uncertain: bool = stage in ["after_replace_before_return","readback_after_replace"]
		t.check(reread.game_save.store_revision == save.store_revision+(1 if uncertain else 0),"E2 exactly old/new revision at "+stage)
		t.check(reread.game_save.profile.supply_credits == (40 if uncertain else 55) and reread.game_save.profile.consumables.field_bandage == (1 if uncertain else 0),"E2 no mixed economic authority at "+stage)
		if uncertain:
			t.check(result.get("error_code") == "commit_outcome_unknown","E2 post-replace cannot claim not applied "+stage)
			var retry: Dictionary = service.prepare_purchase(reread.game_save,"field_bandage",request_id,save.store_revision)
			t.check(retry.get("already_applied") == true and not retry.has("candidate"),"E2 same-ID uncertainty reconciles from persisted receipt "+stage)
		else: t.check(_read(path) == old_bytes,"E2 before-replace failure keeps exact authority bytes "+stage)
	var cas_dir := _directory("cas")
	var authoritative := _funded(t,cas_dir)
	if authoritative.is_empty(): return
	var store = Store.new(cas_dir,_fixture.validate_checkpoint)
	var bought: Dictionary = service.prepare_purchase(authoritative,"field_bandage",_cases._purchase_id(authoritative,"field_bandage"),authoritative.store_revision)
	var committed: Dictionary = store.commit_game(bought.candidate,authoritative.store_revision)
	t.check(committed.get("ok") == true,"E2 successful purchase readback")
	var current_bytes := _read(cas_dir.path_join("game_save.json"))
	var stale: Dictionary = Store.new(cas_dir,_fixture.validate_checkpoint).commit_game(bought.candidate,authoritative.store_revision)
	t.check(stale.get("error_code") == "stale_revision" and _read(cas_dir.path_join("game_save.json")) == current_bytes,"E2 stale CAS never overwrites newer bytes")
	for wrong in [0.9,"4",null,true,{},[]]:
		var rejected = store.callv("commit_game",[committed.game_save,wrong])
		t.check(rejected is Dictionary and rejected.get("ok") == false,"E2 commit expected revision must not coerce")
	var forged: Dictionary = committed.game_save.duplicate(true)
	forged.profile.supply_credits += 1
	t.check(store.commit_game(forged,forged.store_revision).get("ok") == false,"E2 arbitrary credit mint rejected by transition guard")
	forged = committed.game_save.duplicate(true)
	forged.profile.consumables.field_bandage += 1
	t.check(store.commit_game(forged,forged.store_revision).get("ok") == false,"E2 arbitrary inventory refund rejected")
	var transient = Store.new(cas_dir,_fixture.validate_checkpoint,func(at):return ERR_UNAVAILABLE if at == "read_primary" else OK)
	var unavailable: Dictionary = transient.load_game()
	t.check(unavailable.get("error_code") == "read_failed" and _read(cas_dir.path_join("game_save.json")) == current_bytes,"E2 transient primary read never rolls back or resets")
	var corrupt_dir := _directory("corrupt")
	var recoverable := _funded(t,corrupt_dir)
	if recoverable.is_empty(): return
	_write(corrupt_dir.path_join("game_save.json"),"{partial")
	var recovered: Dictionary = Store.new(corrupt_dir,_fixture.validate_checkpoint).load_game()
	t.check(recovered.get("ok") == true and recovered.get("recovered") == true,"E2 current-format corrupt primary can recover valid whole backup")
	var future := recoverable.duplicate(true)
	future.schema_version = 99
	_write(corrupt_dir.path_join("game_save.json"),JSON.stringify(future))
	var blocked: Dictionary = Store.new(corrupt_dir,_fixture.validate_checkpoint).load_game()
	t.check(blocked.get("error_code") == "unsupported_schema" and blocked.get("scope") == "authority","E2 unsupported whole authority never falls back")
	future = recoverable.duplicate(true)
	future.checkpoint.content_revision = "future-revision"
	_write(corrupt_dir.path_join("game_save.json"),JSON.stringify(future))
	blocked = Store.new(corrupt_dir,_fixture.validate_checkpoint).load_game()
	t.check(blocked.get("error_code") == "content_mismatch" and blocked.get("scope") == "checkpoint","E2 checkpoint incompatibility distinct from whole authority")
	_write(corrupt_dir.path_join("game_save.json"),"{broken")
	_write(corrupt_dir.path_join("game_save.json.bak"),"{broken backup")
	blocked = Store.new(corrupt_dir,_fixture.validate_checkpoint).load_game()
	t.check(blocked.get("ok") == false and _read(corrupt_dir.path_join("game_save.json")) == "{broken","E2 damaged existing authority never fresh account")
	_legacy_and_real_initial(t)
	_review_regressions(t)
	_budget_regressions(t)
	_source_race_regressions(t)
	_backup_oversize_races(t)
	_world_hash_fallback(t)
	_unbounded_version_markers(t)
func _legacy_and_real_initial(t) -> void:
	var directory := _directory("legacy_future")
	var profile := {"schema_version":1,"settings":{"deadzone":0.25,"audio_master":0.6,"screen_shake":0.1,"reduce_effects":true},"cleared_chapter_ids":["chapter_01_shiganshina"],"unlocked_character_ids":["garrison_01"],"best_runs":{"chapter_01_shiganshina":{"survival_tick":36000,"kills":100,"won":false}}}
	_write(directory.path_join("profile.json.bak"),JSON.stringify(profile))
	var future := profile.duplicate(true)
	future.schema_version = 99
	var source := JSON.stringify(future)
	_write(directory.path_join("profile.json"),source)
	var denied: Dictionary = Store.new(directory,_fixture.validate_checkpoint).load_game()
	t.check(denied.get("ok") == false and _read(directory.path_join("profile.json")) == source and not FileAccess.file_exists(directory.path_join("game_save.json")),"E2 future legacy primary cannot silently use old backup")
	var legacy_dir := _directory("legacy_preserved")
	var originals := {"profile.json":JSON.stringify(profile,"  "),"profile.json.bak":JSON.stringify(profile),"checkpoint.json":"{unplayable legacy bytes", "checkpoint.json.bak":"{also unplayable backup"}
	for name in originals: _write(legacy_dir.path_join(name),originals[name])
	var migrated: Dictionary = Store.new(legacy_dir,_fixture.validate_checkpoint).load_game()
	t.check(migrated.get("ok") == true and migrated.get("migrated") == true,"E2 valid dev1 profile migrates independently of unplayable run")
	if migrated.get("ok",false):
		t.check(migrated.game_save.profile.supply_credits == 0 and migrated.game_save.legacy_checkpoint_present == true and migrated.game_save.checkpoint == null,"E2 dev1 migration preserves checkpoint presence without backpay")
		t.check(_cases._same(migrated.game_save.profile.settings,profile.settings) and _cases._same(migrated.game_save.profile.best_runs,profile.best_runs),"E2 dev1 settings/history preserved on actual disk migration")
		var twice: Dictionary = Store.new(legacy_dir,_fixture.validate_checkpoint).load_game()
		t.check(twice.get("ok") == true and twice.game_save.career_id == migrated.game_save.career_id and twice.game_save.store_revision == migrated.game_save.store_revision,"E2 migration is idempotent after verified authority exists")
	for name in originals: t.check(_read(legacy_dir.path_join(name)) == originals[name],"E2 exact legacy source bytes untouched "+name)
	var actual_dir := _directory("real_initial")
	var validation = Core.new()
	var factory = Core.new()
	var real_store = Store.new(actual_dir,validation.restore)
	var loaded: Dictionary = real_store.load_game()
	t.check(loaded.get("ok") == true,"E2 REAL Core empty install readback")
	if not loaded.get("ok",false): return
	var chapter_load: Dictionary = Chapter.new().load_chapter("chapter_01_shiganshina")
	t.check(chapter_load.get("ok") == true,"E2 real Store fixture includes complete chapter definitions")
	if chapter_load.get("ok") != true: return
	var chapter: Dictionary = chapter_load.chapter
	var real_service = Service.new(factory.new_run)
	var start: Dictionary = real_service.prepare_run_start(loaded.game_save,chapter,42,_cases._start_id(loaded.game_save),loaded.game_save.store_revision)
	var started: Dictionary = real_store.commit_game(start.candidate,loaded.game_save.store_revision)
	t.check(started.get("ok") == true,"E2 REAL nonstreamed initial checkpoint atomic readback")
	if not started.get("ok",false): return
	var fresh_validator = Core.new()
	var restart: Dictionary = Store.new(actual_dir,fresh_validator.restore).load_game()
	t.check(restart.get("ok") == true and restart.game_save.checkpoint.run_id == started.game_save.checkpoint.run_id,"E2 REAL initial checkpoint survives fresh validator/store")

func _review_regressions(t) -> void:
	for kind in ["profile_future","whole_future_deep","checkpoint_future_deep"]:
		var directory := _directory(kind)
		var save := _funded(t,directory)
		if save.is_empty(): return
		var future := save.duplicate(true)
		if kind == "profile_future": future.profile.schema_version = 99
		elif kind == "whole_future_deep": future.schema_version = 99
		else: future.checkpoint.schema_version = 99
		if kind.ends_with("deep"):
			var cursor: Dictionary = future
			for _i in range(66):
				cursor.extension = {}
				cursor = cursor.extension
		var bytes := JSON.stringify(future,"",true,true)
		var path := directory.path_join("game_save.json")
		_write(path,bytes)
		var result: Dictionary = Store.new(directory,_fixture.validate_checkpoint).load_game()
		t.check(result.get("ok") == false and result.get("error_code") == "unsupported_schema","E2 review unknown schema blocks fallback before deep-content validation "+kind)
		t.check(_read(path) == bytes,"E2 review unknown schema bytes preserved "+kind)
	var directory := _directory("second_primary_read")
	var save := _funded(t,directory)
	if save.is_empty(): return
	var path := directory.path_join("game_save.json")
	var before := _read(path)
	var backup_before := _read(path+".bak")
	var candidate := save.duplicate(true)
	candidate.profile.settings.audio_master = 0.7
	var reads := [0]
	var fail_second = func(at):
		if at == "read_primary":
			reads[0] += 1
			if reads[0] == 2: return ERR_UNAVAILABLE
		return OK
	var result: Dictionary = Store.new(directory,_fixture.validate_checkpoint,fail_second).commit_game(candidate,save.store_revision)
	t.check(result.get("ok") == false and result.get("error_code") == "read_failed","E2 review transient writer reread is not corrupt evidence")
	t.check(_read(path) == before and _read(path+".bak") == backup_before,"E2 review failed writer reread preserves primary and backup bytes")

func _budget_regressions(t) -> void:
	var directory := _directory("bounded_authority")
	var save := _funded(t,directory)
	if save.is_empty(): return
	var candidate := save.duplicate(true)
	var wide := []
	wide.resize(300000)
	candidate.profile.extension = wide
	var contracts = load("res://game/contracts/game_save_contracts.gd").new(_fixture.validate_checkpoint)
	t.check(not contracts.validate_economy(candidate).is_empty(),"E2 bounded authority rejects 300000-value extension")
	var before := _read(directory.path_join("game_save.json"))
	var denied: Dictionary = Store.new(directory,_fixture.validate_checkpoint).commit_game(candidate,save.store_revision)
	t.check(denied.get("ok") == false and _read(directory.path_join("game_save.json")) == before,"E2 node budget blocks commit without changing authority")
	candidate.schema_version = 99
	t.check(contracts.validate_economy(candidate) == ["unsupported_schema"],"E2 future schema classification wins over wide-content budget")
	candidate = save.duplicate(true)
	candidate.profile.extension = "x".repeat(16*1024*1024+1)
	t.check(not contracts.validate_economy(candidate).is_empty(),"E2 bounded authority rejects oversized string before serialization")

func _source_race_regressions(t) -> void:
	for boundary in ["second_read","replace"]:
		var directory := _directory("writer_race_"+boundary)
		var save := _funded(t,directory)
		if save.is_empty(): return
		var path := directory.path_join("game_save.json")
		var external := save.duplicate(true)
		external.store_revision += 1
		external.profile.settings.audio_master = 0.1
		var external_bytes := JSON.stringify(external)
		var reads := [0]
		var race = func(at):
			if at == "read_primary": reads[0] += 1
			if (boundary == "second_read" and at == "read_primary" and reads[0] == 2) or (boundary == "replace" and at == "replace"):
				_write(path,external_bytes)
			return OK
		var candidate := save.duplicate(true)
		candidate.profile.settings.audio_master = 0.7
		var result: Dictionary = Store.new(directory,_fixture.validate_checkpoint,race).commit_game(candidate,save.store_revision)
		t.check(result.get("ok") == false and result.get("error_code") == "stale_revision" and _read(path) == external_bytes,"E2 byte/revision race before "+boundary+" rejects overwriting changed authority")

func _backup_oversize_races(t) -> void:
	var directory := _directory("oversize_unknown_primary")
	var save := _funded(t,directory)
	if save.is_empty(): return
	var path := directory.path_join("game_save.json")
	var oversized := "x".repeat(16*1024*1024+1)
	_write(path,oversized)
	var blocked: Dictionary = Store.new(directory,_fixture.validate_checkpoint).load_game()
	t.check(blocked.get("ok") == false and blocked.get("error_code") == "read_failed","E2 review oversized unhashable primary cannot be replaced via backup")
	t.check(_read(path) == oversized,"E2 review unread oversized bytes stay untouched")
	directory = _directory("backup_authority_race")
	save = _funded(t,directory)
	if save.is_empty(): return
	path = directory.path_join("game_save.json")
	_write(path,"{corrupt primary")
	var recovered: Dictionary = Store.new(directory,_fixture.validate_checkpoint).load_game()
	if not recovered.get("ok",false):
		t.check(false,"E2 review backup race fixture recovered")
		return
	var candidate: Dictionary = recovered.game_save.duplicate(true)
	candidate.profile.settings.audio_master = 0.7
	var changed_backup := JSON.stringify(save)
	var race = func(at):
		if at == "replace": _write(path+".bak",changed_backup)
		return OK
	var denied: Dictionary = Store.new(directory,_fixture.validate_checkpoint,race).commit_game(candidate,candidate.store_revision)
	t.check(denied.get("ok") == false and denied.get("error_code") == "stale_revision","E2 review authoritative backup identity rechecked before replace")
	t.check(_read(path) == "{corrupt primary" and _read(path+".bak") == changed_backup,"E2 review newer backup credits/history never overwritten by stale recovered candidate")
func _world_hash_fallback(t) -> void:
	# Real immutable page/hash verification with SHAPE player restoration, not full streamed Core.
	var directory := _directory("world_hash_only")
	var codec = load("res://game/world/world_delta_codec.gd")
	var disk_script = load("res://game/persistence/world_delta_store.gd")
	var adapter_script = load("res://game/app/world_checkpoint_adapter.gd")
	var helpers = load("res://tests/world/test_world_delta_store.gd").new()
	var disk = disk_script.new(directory.path_join("world"))
	var first: Dictionary = disk.prepare(codec.empty_root(),[helpers.record(0,2)],1)
	var second: Dictionary = disk.prepare(first.receipt.candidate_root,[helpers.record(0,1)],2)
	t.check(first.get("ok") == true and second.get("ok") == true,"E2 world hash fallback has actual immutable page roots")
	if not first.get("ok",false) or not second.get("ok",false): return
	var old: Dictionary = _fixture.game_save("started")
	old.store_revision = 2
	old.checkpoint.world = {"world_revision":1,"delta_root":first.receipt.candidate_root,"dirty_chunks":[]}
	var current := old.duplicate(true)
	current.store_revision = 3
	current.checkpoint.player.hp = 73
	current.checkpoint.world = {"world_revision":2,"delta_root":second.receipt.candidate_root,"dirty_chunks":[]}
	var path := directory.path_join("game_save.json")
	_write(path+".bak",JSON.stringify(old))
	_write(path,JSON.stringify(current))
	var original_authority := _read(path)
	var root_hash: String = second.receipt.candidate_root.root_hash
	var world_path := directory.path_join("world/pages").path_join(root_hash.substr(0,2)).path_join(root_hash+".json")
	_write(world_path,"{}")
	var requirements = func(_state): return {"ok":true,"chunks":[["0","0"]]}
	var restore_shape = func(state,_hydrated): return _fixture.validate_checkpoint(state)
	var adapter = adapter_script.new(disk_script.new(directory.path_join("world")),requirements,restore_shape)
	var recovered: Dictionary = Store.new(directory,adapter.validate_checkpoint).load_game()
	t.check(recovered.get("ok") == true and recovered.get("recovered") == true and recovered.game_save.store_revision == 2 and recovered.game_save.checkpoint.player.hp == old.checkpoint.player.hp,"E2 exact world_hash_mismatch may recover validated whole previous player/world")
	t.check(_read(path) == original_authority and _read(world_path) == "{}","E2 hash mismatch recovery preserves primary metadata and corrupt world evidence")
	# A correctly addressed future page is world_page_invalid in the exact codec.
	# It must remain a preservation barrier instead of hiding behind the old backup.
	var future_bytes := JSON.stringify({"format_revision":99,"kind":"leaf","records":[]},"",true,true)
	var future_hash := future_bytes.sha256_text()
	var future_path := directory.path_join("world/pages").path_join(future_hash.substr(0,2)).path_join(future_hash+".json")
	_write(future_path,future_bytes)
	current.checkpoint.world.delta_root.root_hash = future_hash
	_write(path,JSON.stringify(current))
	adapter = adapter_script.new(disk_script.new(directory.path_join("world")),requirements,restore_shape)
	var future: Dictionary = Store.new(directory,adapter.validate_checkpoint).load_game()
	t.check(future.get("ok") == false and future.get("error_code") == "world_page_invalid" and _read(future_path) == future_bytes,"E2 future page invalid classification stays blocked and preserved")
	for code in ["world_read_failed","world_page_missing","world_page_invalid","world_page_oversize","world_unknown_future_code"]:
		var validator = func(state): return {"ok":false,"error_code":code} if state.player.hp == 73 else _fixture.validate_checkpoint(state)
		var blocked: Dictionary = Store.new(directory,validator).load_game()
		t.check(blocked.get("ok") == false and blocked.get("error_code") == code,"E2 only exact hash mismatch is recoverable; preserve "+code)
func _unbounded_version_markers(t) -> void:
	for field in ["profile","checkpoint"]:
		for version in [2147483648,9007199254740992,1.0e100]:
			var directory := _directory("schema_without_counter_cap")
			var save := _funded(t,directory)
			if save.is_empty(): return
			var future := save.duplicate(true)
			future[field].schema_version = version
			var bytes := JSON.stringify(future,"",true,true)
			var path := directory.path_join("game_save.json")
			_write(path,bytes)
			var result: Dictionary = Store.new(directory,_fixture.validate_checkpoint).load_game()
			t.check(result.get("ok") == false and result.get("error_code") == "unsupported_schema" and _read(path) == bytes,"E2 future schema marker is not capped by economy counter "+field+"/"+str(version))
