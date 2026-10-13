extends RefCounted
const F = preload("res://tests/dev5_legacy_compatibility/legacy_fixture.gd")
const Runtime = preload("res://game/app/prepared_city_runtime.gd")
const Scope = preload("res://game/app/save_validation_scope.gd")
const Service = preload("res://game/economy/supply_service.gd")
func run(t) -> void:
	_fixture_identity(t)
	_active_and_terminal(t)
	_unknown_does_not_recover(t)
func _fixture_identity(t) -> void:
	var source := F.provenance()
	t.check(source.source_commit == "b6e471f9ff4c447c99119fdefeff1c6502807f01" and source.definition_sha256.size() == 13,"legacy fixture is the exact 13-file dev4 capture")
	for path in source.definition_sha256:
		t.check(FileAccess.get_sha256(F.ROOT+"inputs/"+path) == source.definition_sha256[path],"immutable dev4 definition bytes: "+path)
	for path in source.save_sha256:
		t.check(FileAccess.get_sha256(F.ROOT+"active_save/"+path) == source.save_sha256[path],"archived dev4 authority bytes: "+path)
	var core = F.legacy_core()
	t.check(core != null and core._content_error.is_empty() and core._chapter.content_fingerprint == F.FINGERPRINT,"exact dev4 source reconstructs its real production fingerprint")
func _active_and_terminal(t) -> void:
	var directory := F.install("boundary")
	var arranged := F.enrich(directory)
	var old := F.legacy_authority(directory)
	if old.is_empty(): t.check(false,"dev4 reference Core constructs"); return
	var reference: Dictionary = old.store.read_game()
	t.check(reference.get("ok",false),"archived active dev4 checkpoint and arranged economy pass real pinned Core/Store")
	if not reference.get("ok",false): return
	var before := F.bytes(directory)
	var provider := F.City.new()
	var runtime := Runtime.new(provider,F.Disk.new(directory.path_join("world")))
	var store := F.Save.new(directory,Callable(runtime,"validate_checkpoint"))
	var loaded: Dictionary = store.read_game()
	t.check(loaded.get("ok",false),"current application Store reads complete actual dev4 authority without content mismatch")
	t.check(F.bytes(directory) == before,"legacy read preserves primary backup and durable world pages byte-for-byte")
	if not loaded.get("ok",false): return
	t.check(F.same(loaded.game_save,reference.game_save),"legacy load preserves gold upgrades unlocks receipts and checkpoint together")
	var scope = Scope.create(runtime,directory,int(loaded.game_save.store_revision))
	t.check(scope != null,"routed runtime retains the transaction-local validation scope")
	if scope != null:
		var scoped: Dictionary = store.read_game_scoped(scope)
		t.check(scoped.get("ok",false) and F.same(scoped.game_save,loaded.game_save),"scoped and cold legacy Store validation select the same catalog")
		var poisoned: Dictionary = loaded.game_save.duplicate(true)
		poisoned.checkpoint.rules.content_fingerprint = "e".repeat(64)
		poisoned.checkpoint.world.content_fingerprint = "e".repeat(64)
		var rejected: Dictionary = runtime._contracts.validate_and_normalize(poisoned,scope,{"slot":"B"})
		t.check(rejected.get("error_code") == "content_mismatch","warm legacy proof cannot validate a different content identity in candidate slot")
		var repeated: Dictionary = store.read_game_scoped(scope)
		t.check(repeated.get("ok",false) and F.same(repeated.game_save,loaded.game_save),"rejected content route cannot poison the valid predecessor proof")
		scope.close()
	var prepared := runtime.prepare_load(loaded.game_save)
	t.check(prepared.get("ok",false),"legacy active checkpoint prepares its original damaged-world geometry")
	if not prepared.get("ok",false): return
	var pair := runtime.confirm_candidate(store)
	t.check(pair.get("ok",false),"legacy pending runtime is confirmed against exact saved authority")
	if not pair.get("ok",false): return
	t.check(pair.simulation._catalog.evolutions._schema_version == 1 and pair.state.rules.content_fingerprint == F.FINGERPRINT,"legacy Core retains schema1 recipe and original content identity")
	t.check(F.same(pair.simulation._chapter.world_definitions,old.core._chapter.world_definitions),"resumed legacy geometry uses exact dev4 props templates and mechanical assets")
	t.check(pair.state.world.schema_version == 2 and pair.state.world.delta_root == reference.game_save.checkpoint.world.delta_root,"existing damaged-world root and dormant schema are preserved")
	var terminal: Dictionary = pair.simulation.snapshot(pair.state)
	pair.simulation.abandon_run(terminal)
	var service := Service.new(Callable(runtime,"new_run"))
	var settled := service.prepare_settlement(loaded.game_save,terminal)
	t.check(settled.get("ok",false),"real legacy terminal settles without replacing permanent economy")
	if not settled.get("ok",false): return
	var committed: Dictionary = store.commit_game(settled.candidate,int(loaded.game_save.store_revision))
	t.check(committed.get("ok",false),"legacy terminal and settlement receipt commit atomically")
	if not committed.get("ok",false): return
	var cold := Runtime.new(F.City.new(),F.Disk.new(directory.path_join("world")))
	var cold_store := F.Save.new(directory,Callable(cold,"validate_checkpoint"))
	var reloaded: Dictionary = cold_store.read_game()
	t.check(reloaded.get("ok",false) and F.same(reloaded.game_save,committed.game_save),"cold current runtime reads settled legacy terminal checkpoint and receipts")
	t.check(F.same(committed.game_save.purchase_receipts,arranged.purchase_receipts) and F.same(committed.game_save.profile.permanent_upgrades,arranged.profile.permanent_upgrades) and committed.game_save.profile.unlocked_character_ids == arranged.profile.unlocked_character_ids,"settlement preserves prior purchases permanent levels and character unlocks")
	var current: Dictionary = provider.load_chapter(F.Chapters.CHAPTER_ID).chapter
	var start := service.prepare_run_start(committed.game_save,current,77,"start:%s:%d" % [committed.game_save.career_id,int(committed.game_save.next_run_serial)],int(committed.game_save.store_revision))
	t.check(start.get("ok",false) and start.candidate.checkpoint.rules.content_fingerprint == current.content_fingerprint and current.content_fingerprint != F.FINGERPRINT,"only the next new run adopts current dev5 definitions")
func _unknown_does_not_recover(t) -> void:
	var directory := F.install("unknown")
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(directory.path_join("game_save.json")))
	source.checkpoint.rules.content_fingerprint = "f".repeat(64)
	source.checkpoint.world.content_fingerprint = "f".repeat(64)
	F.write(directory.path_join("game_save.json"),JSON.stringify(source,"",true,true))
	var before := F.bytes(directory)
	var runtime := Runtime.new(F.City.new(),F.Disk.new(directory.path_join("world")))
	var result: Dictionary = F.Save.new(directory,Callable(runtime,"validate_checkpoint")).read_game()
	t.check(result.get("ok") == false and result.get("error_code") == "content_mismatch" and not result.get("recovered",false),"unknown production fingerprint blocks instead of silently adopting old backup")
	t.check(F.bytes(directory) == before,"unknown identity never rewrites primary backup or world pages")
	# This separate negative deliberately corrupts a copied page after the valid
	# fixture/control. Unknown content must remain a barrier, never backup repair.
	var root_hash: String = source.checkpoint.world.delta_root.root_hash
	var root_path := directory.path_join("world/pages").path_join(root_hash.substr(0,2)).path_join(root_hash+".json")
	F.write(root_path,"{}")
	before = F.bytes(directory)
	result = F.Save.new(directory,Callable(runtime,"validate_checkpoint")).read_game()
	t.check(result.get("error_code") == "content_mismatch" and not result.get("recovered",false) and F.bytes(directory) == before,"unknown content stays a read-only barrier even beside a deliberately corrupted copied page")
