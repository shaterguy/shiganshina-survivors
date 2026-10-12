extends RefCounted
const Cases = preload("res://tests/character_unlock/test_character_unlock.gd")
const Store = preload("res://game/persistence/game_save_store.gd")
const Service = preload("res://game/economy/supply_service.gd")
const Contracts = preload("res://game/contracts/game_save_contracts.gd")
const F = preload("res://tests/core/new_current_regression_fixture.gd")
func run(t) -> void:
	_nonwinning(t)
	_atomic_unlocks(t)
	_selection_boundaries(t)
func _nonwinning(t) -> void:
	for outcome in ["dead","abandoned"]:
		var b: Dictionary = Cases.new()._bundle(t)
		if b.is_empty(): return
		var state: Dictionary = b.save.checkpoint.duplicate(true)
		if outcome == "dead": F.step(b.core,state,Vector2.ZERO,[F.hazard("fatal")])
		else: b.core.abandon_run(state)
		t.check(state.phase == outcome,"Actual nonwinning result: "+outcome)
		var prepared: Dictionary = b.service.prepare_settlement(b.save,state)
		t.check(prepared.get("ok",false),"Nonwinning settlement remains supported")
		if not prepared.get("ok",false): continue
		var committed: Dictionary = b.store.commit_game(prepared.candidate,b.save.store_revision)
		t.check(committed.get("ok",false) and committed.game_save.profile.unlocked_character_ids == ["garrison_01"] and committed.game_save.profile.cleared_chapter_ids.is_empty(),"Death/abandon never unlock or clear a scenario")
func _atomic_unlocks(t) -> void:
	for stage in ["write","flush","verify","backup","replace","after_replace_before_return","readback_after_replace"]:
		var b: Dictionary = Cases.new()._bundle(t)
		if b.is_empty(): return
		var old_bytes := FileAccess.get_file_as_string(b.directory.path_join("game_save.json"))
		var prepared: Dictionary = b.service.prepare_settlement(b.save,b.terminal)
		var fault = func(at): return ERR_UNAVAILABLE if at == stage else OK
		var result: Dictionary = Store.new(b.directory,b.validator.restore,fault).commit_game(prepared.candidate,b.save.store_revision)
		t.check(not result.get("ok",false),"Fault reports unsuccessful result: "+stage)
		var reread: Dictionary = Store.new(b.directory,b.validator.restore).read_game()
		t.check(reread.get("ok",false),"Fault restart has complete authority: "+stage)
		if not reread.get("ok",false): continue
		var applied: bool = stage in ["after_replace_before_return","readback_after_replace"]
		t.check(("mikasa_01" in reread.game_save.profile.unlocked_character_ids) == applied,"Unlock has same atomic outcome as reward: "+stage)
		t.check(("chapter_01_shiganshina" in reread.game_save.profile.cleared_chapter_ids) == applied,"Clear has same atomic outcome: "+stage)
		t.check(reread.game_save.profile.supply_credits == (prepared.candidate.profile.supply_credits if applied else b.save.profile.supply_credits),"Gold matches exact unlock transaction: "+stage)
		if not applied: t.check(FileAccess.get_file_as_string(b.directory.path_join("game_save.json")) == old_bytes,"Pre-replace failure keeps exact original bytes: "+stage)
		else:
			t.check(result.get("error_code") == "commit_outcome_unknown","Post-replace result remains explicitly uncertain")
			t.check(b.service.prepare_settlement(reread.game_save,b.terminal).get("already_applied",false),"Uncertain settlement reconciles without duplicate rewards")
func _selection_boundaries(t) -> void:
	var b: Dictionary = Cases.new()._bundle(t)
	if b.is_empty(): return
	var forged: Dictionary = b.save.duplicate(true)
	forged.profile.unlocked_character_ids.append("mikasa_01")
	t.check(not b.store.commit_game(forged,b.save.store_revision).get("ok",false),"Direct Store cannot grant unlock outside real settlement")
	var changed: Dictionary = b.terminal.duplicate(true)
	changed.character_id = "mikasa_01"
	t.check(not b.service.prepare_settlement(b.save,changed).get("ok",false),"Terminal cannot swap the character identity")
	var prepared: Dictionary = b.service.prepare_settlement(b.save,b.terminal)
	var committed: Dictionary = b.store.commit_game(prepared.candidate,b.save.store_revision)
	if not committed.get("ok",false): return
	var save: Dictionary = committed.game_save
	var original := JSON.stringify(save)
	var view: Dictionary = b.service.shop_view(save)
	t.check(view.selected_character_id == "garrison_01" and view.character_options.size() == 4,"Character view displays default and truthful planned rows")
	for row in view.character_options:
		if row.id == "mikasa_01": t.check(row.can_select and row.is_unlocked and row.implementation_status == "prototype" and row.art_status == "missing","Mikasa prototype row selects only after actual unlock")
		if row.id in ["eren_01","levi_01"]: t.check(not row.can_select and row.blocked_reason == "not_implemented","Unimplemented character cannot select")
	view.character_options[0].name = "changed"
	t.check(JSON.stringify(save) == original,"Views never alter profile or character registry")
	for id in ["unknown","eren_01","levi_01",123,null]:
		t.check(not b.service.prepare_character_selection(save,"chapter_01_shiganshina",id,save.store_revision).get("ok",false),"Unavailable/malformed selection rejects: "+str(id))
	t.check(b.service.prepare_character_selection(save,"chapter_01_shiganshina","mikasa_01",save.store_revision-1).get("error_code") == "stale_revision","Stale selection cannot overwrite newer authority")
	t.check(b.service.prepare_character_selection(save,"chapter_02","mikasa_01",save.store_revision).get("error_code") == "not_implemented","Future scenario selection rejects")
	var pick: Dictionary = b.service.prepare_character_selection(save,"chapter_01_shiganshina","mikasa_01",save.store_revision)
	var fault = func(at): return ERR_UNAVAILABLE if at == "replace" else OK
	t.check(not Store.new(b.directory,b.validator.restore,fault).commit_game(pick.candidate,save.store_revision).get("ok",false),"Failed selection commit is not published")
	t.check(not Store.new(b.directory,b.validator.restore).read_game().game_save.profile.has("selected_character_id"),"Failed selection preserves default absent field")
	committed = b.store.commit_game(pick.candidate,save.store_revision)
	if not committed.get("ok",false): return
	save = committed.game_save
	var start: Dictionary = b.service.prepare_run_start(save,b.chapter,44,"start:%s:%d" % [save.career_id,save.next_run_serial],save.store_revision)
	if not start.get("ok",false): return
	forged = start.candidate.duplicate(true)
	forged.profile.unlocked_character_ids.erase("mikasa_01")
	forged.profile.erase("selected_character_id")
	t.check(not Contracts.new(b.validator.restore).validate(forged).is_empty(),"Restored non-protagonist checkpoint requires profile unlock")
	forged = start.candidate.duplicate(true)
	forged.profile.cleared_chapter_ids.clear()
	t.check(not Contracts.new(b.validator.restore).validate(forged).is_empty(),"Restored replay checkpoint requires prior chapter clear")
	var wrong_run: Dictionary = start.candidate.duplicate(true)
	wrong_run.checkpoint.run_config.erase("character_id")
	wrong_run.checkpoint.character_id = "garrison_01"
	wrong_run.checkpoint.rules.erase("character_blade_cooldown_multiplier")
	wrong_run.checkpoint.rules.move_speed /= 1.08
	wrong_run.checkpoint.rules.base_move_speed /= 1.08
	t.check(not b.store.commit_game(wrong_run,save.store_revision).get("ok",false),"Start transition cannot ignore persisted selected character")
