extends RefCounted
const Unlock = preload("res://tests/character_unlock/test_character_unlock.gd")
const F = preload("res://tests/core/new_current_regression_fixture.gd")
const Core = preload("res://game/core/run_simulation.gd")
const Current = preload("res://tests/core/current_combat_provider.gd")
const Store = preload("res://game/persistence/game_save_store.gd")
func run(t) -> void:
	var b := Unlock.new()._bundle(t)
	if b.is_empty(): return
	var settlement: Dictionary = b.service.prepare_settlement(b.save,b.terminal)
	var committed: Dictionary = b.store.commit_game(settlement.candidate,b.save.store_revision)
	t.check(committed.get("ok",false),"legacy fixture owns actual victory unlock receipt")
	if not committed.get("ok",false): return
	var save: Dictionary = committed.game_save
	var purchase: Dictionary = b.service.prepare_purchase(save,"permanent_might","purchase:%s:%d:permanent_might" % [save.career_id,save.store_revision],save.store_revision)
	t.check(purchase.get("ok",false),"legacy fixture buys permanent damage through actual wallet authority")
	if not purchase.get("ok",false): return
	committed = b.store.commit_game(purchase.candidate,save.store_revision)
	t.check(committed.get("ok",false),"actual legacy permanent purchase commits")
	if not committed.get("ok",false): return
	save = committed.game_save
	for character in ["garrison_01","mikasa_01"]:
		var selection: Dictionary = b.service.prepare_character_selection(save,b.chapter.chapter_id,character,save.store_revision)
		t.check(selection.get("ok",false),"legacy character selection remains authoritative")
		if not selection.get("ok",false): return
		committed = b.store.commit_game(selection.candidate,save.store_revision)
		if not committed.get("ok",false): t.check(false,"legacy selection commits"); return
		save = committed.game_save
		var start: Dictionary = b.service.prepare_run_start(save,b.chapter,72,"start:%s:%d" % [save.career_id,save.next_run_serial],save.store_revision)
		t.check(start.get("ok",false),"authoritative legacy envelope starts")
		if not start.get("ok",false): return
		# This explicit pre-revision schema fixture is the old app's frozen
		# config, not a compatibility fallback or an injected new capability.
		var config: Dictionary = start.candidate.checkpoint.run_config.duplicate(true)
		config.erase("character_skill_revision")
		var legacy: Dictionary = b.core.new_run(b.chapter,72,config)
		legacy.equipment = {"fire_zone":5}
		F.step(b.core,legacy,Vector2.ZERO,[F.spawn("legacy-fire",[80,0],"brute")])
		t.check(not legacy.has("character_skill") and legacy.player_attack_instances.size() > 1,"pre-revision character fixture contains real pending fire stages only")
		start.candidate.checkpoint = legacy
		committed = b.store.commit_game(start.candidate,save.store_revision)
		t.check(committed.get("ok",false),"old schema character and pending attacks commit without migration")
		if not committed.get("ok",false): return
		var expected: Dictionary = committed.game_save.duplicate(true)
		var path: String = b.directory.path_join("game_save.json")
		var before := FileAccess.get_file_as_bytes(path)
		var writes := [0]
		var hook := func(stage):
			if stage in ["write","replace","after_replace"]: writes[0] += 1
			return OK
		var fresh := Core.new(Current.new())
		var store := Store.new(b.directory,fresh.restore,hook)
		var read := store.read_game()
		t.check(read.get("ok",false),"cold Store accepts pre-revision "+character+" checkpoint")
		if not read.get("ok",false): return
		t.check(FileAccess.get_file_as_bytes(path) == before and writes[0] == 0,"old Store read does not rewrite reset or delete original bytes")
		t.check(read.game_save.profile == expected.profile and read.game_save.purchase_receipts == expected.purchase_receipts and read.game_save.settlement_receipts == expected.settlement_receipts,"cold legacy read preserves wallet upgrades unlocks selection and both receipt ledgers")
		t.check(not read.game_save.checkpoint.has("character_skill") and not read.game_save.checkpoint.run_config.has("character_skill_revision"),"old active run never receives signature retroactively")
		var checkpoint: Dictionary = read.game_save.checkpoint.duplicate(true)
		F.step(fresh,checkpoint,Vector2.ZERO)
		t.check(not checkpoint.has("character_skill"),"continued old combat remains revision-less")
		fresh.abandon_run(checkpoint)
		var finished: Dictionary = b.service.prepare_settlement(read.game_save,checkpoint)
		t.check(finished.get("ok",false),"old active run can settle normally")
		if not finished.get("ok",false): return
		committed = store.commit_game(finished.candidate,read.game_save.store_revision)
		if not committed.get("ok",false): t.check(false,"legacy settlement commits"); return
		save = committed.game_save
	var next: Dictionary = b.service.prepare_run_start(save,b.chapter,73,"start:%s:%d" % [save.career_id,save.next_run_serial],save.store_revision)
	t.check(next.get("ok",false) and next.candidate.checkpoint.run_config.get("character_skill_revision") == 1 and next.candidate.checkpoint.has("character_skill"),"after old Mikasa run settles only next new run opts in")
	t.check(next.candidate.profile == save.profile and next.candidate.purchase_receipts == save.purchase_receipts and next.candidate.settlement_receipts == save.settlement_receipts,"new ability has no wallet unlock or receipt side effects")
