extends RefCounted
const Core = preload("res://game/core/run_simulation.gd")
const Finite = preload("res://tests/core/finite_chapter_provider.gd")
const F = preload("res://tests/core/new_current_regression_fixture.gd")
const Store = preload("res://game/persistence/game_save_store.gd")
const Service = preload("res://game/economy/supply_service.gd")
const Contracts = preload("res://game/contracts/game_save_contracts.gd")
func run(t) -> void:
	_catalog(t)
	_lifecycle(t)
func _catalog(t) -> void:
	var path := "res://game/progression/character_catalog.gd"
	t.check(FileAccess.file_exists(path),"Character registry exists separately from progression levels")
	if not FileAccess.file_exists(path): return
	var registry = load(path).new()
	var profile := {"cleared_chapter_ids":[],"unlocked_character_ids":["garrison_01"]}
	t.check(registry.protagonist_id("chapter_01_shiganshina") == "garrison_01","Original scenario protagonist is preserved")
	t.check(registry.selection_error(profile,"chapter_01_shiganshina","mikasa_01") != "","Uncleared chapter cannot select another character")
	profile.cleared_chapter_ids.append("chapter_01_shiganshina")
	t.check(registry.selection_error(profile,"chapter_01_shiganshina","mikasa_01") == "character_locked","Chapter clear does not bypass permanent unlock")
	profile.unlocked_character_ids.append("mikasa_01")
	t.check(registry.selection_error(profile,"chapter_01_shiganshina","mikasa_01") == "","Unlocked character can replay cleared chapter")
	t.check(registry.selection_error(profile,"chapter_02","mikasa_01") == "not_implemented","Future scenario is unavailable")
	var mikasa: Dictionary = registry.definition("mikasa_01")
	t.check(mikasa.implementation_status == "prototype" and mikasa.art_status == "missing","Prototype and missing original art are explicit")
	t.check(mikasa.signature_ultimate.implementation_status == "planned" and mikasa.unique_skill.implementation_status == "planned","Numeric traits do not claim a finished unique skill or ultimate")
	t.check(registry.definition("levi_01").implementation_status == "planned","Levi remains planned without protagonist exclusion")
	mikasa.traits.move_speed_multiplier = 999
	t.check(registry.run_traits("mikasa_01").move_speed_multiplier == 1.08,"Registry values do not alias callers")
func _bundle(t) -> Dictionary:
	var core = Core.new(Finite.new())
	var validator = Core.new(Finite.new())
	var chapter: Dictionary = Finite.new().load_chapter("chapter_01_shiganshina").chapter
	var service = Service.new(core.new_run)
	var directory := "user://character_unlock_%d_%d" % [OS.get_process_id(),Time.get_ticks_usec()]
	var store = Store.new(directory,validator.restore)
	var loaded: Dictionary = store.load_game()
	t.check(loaded.get("ok") == true,"Real Store creates initial authority")
	if not loaded.get("ok",false): return {}
	var save: Dictionary = loaded.game_save
	var start: Dictionary = service.prepare_run_start(save,chapter,43,"start:%s:%d" % [save.career_id,save.next_run_serial],save.store_revision)
	t.check(start.get("ok") == true,"Real Core first scenario starts")
	if not start.get("ok",false): return {}
	var committed: Dictionary = store.commit_game(start.candidate,save.store_revision)
	t.check(committed.get("ok") == true,"Real initial run commits")
	if not committed.get("ok",false): return {}
	save = committed.game_save
	var state: Dictionary = save.checkpoint.duplicate(true)
	# Arranged finite pre-final state. Actual Core commands, escape and Store
	# validation run; this is not a full chapter playthrough or streamed-world proof.
	state.active_tick = 107999
	state.survival_tick = 107999
	F.step(core,state,Vector2.ZERO,[F.final_command(state)])
	var skipped := 112499-int(state.active_tick)
	state.active_tick = 112499
	for entity in state.entities:
		for field in ["action_started_tick","action_ends_tick","next_action_tick"]: entity[field] = int(entity[field])+skipped
	for hazard in state.telegraphs:
		for field in ["created_tick","active_from_tick","expires_tick"]: hazard[field] = int(hazard[field])+skipped
	state.player.position = [0,350]
	t.check(core.restore(state).get("ok",false),"Arranged pre-exit state passes actual Core restore")
	F.step(core,state,Vector2.ZERO)
	t.check(state.phase == "won","Actual escape tick produces won")
	t.check(core.restore(core.snapshot(state)).get("ok",false),"Actual won state passes Core validation")
	return {"core":core,"validator":validator,"chapter":chapter,"service":service,"store":store,"directory":directory,"save":save,"terminal":state}
func _lifecycle(t) -> void:
	var b := _bundle(t)
	if b.is_empty(): return
	var before := JSON.stringify(b.save)
	var prepared: Dictionary = b.service.prepare_settlement(b.save,b.terminal)
	t.check(prepared.get("ok") == true,"Actual won settlement prepares")
	if not prepared.get("ok",false): return
	t.check("mikasa_01" in prepared.candidate.profile.unlocked_character_ids,"Scenario 1 actual victory unlocks Mikasa")
	t.check(JSON.stringify(b.save) == before,"Prepared unlock does not mutate authority before commit")
	var result: Dictionary = b.store.commit_game(prepared.candidate,b.save.store_revision)
	t.check(result.get("ok") == true,"Victory clear reward and unlock commit atomically")
	if not result.get("ok",false): return
	var save: Dictionary = result.game_save
	t.check(b.service.prepare_settlement(save,b.terminal).get("already_applied") == true,"Duplicate settlement does not unlock or pay twice")
	t.check(b.service.has_method("prepare_character_selection"),"Character selection uses economic transaction boundary")
	if not b.service.has_method("prepare_character_selection"): return
	var picked: Dictionary = b.service.prepare_character_selection(save,"chapter_01_shiganshina","mikasa_01",save.store_revision)
	t.check(picked.get("ok") == true,"Unlocked Mikasa selection prepares for cleared scenario")
	if not picked.get("ok",false): return
	result = b.store.commit_game(picked.candidate,save.store_revision)
	t.check(result.get("ok") == true,"Selected character commits")
	if not result.get("ok",false): return
	var reread: Dictionary = Store.new(b.directory,b.validator.restore).read_game()
	t.check(reread.get("ok") == true and reread.game_save.profile.selected_character_id == "mikasa_01","Restart restores selected character and unlock")
	save = reread.game_save
	var start: Dictionary = b.service.prepare_run_start(save,b.chapter,44,"start:%s:%d" % [save.career_id,save.next_run_serial],save.store_revision)
	t.check(start.get("ok") == true,"Selected character starts real replay")
	if not start.get("ok",false): return
	t.check(start.candidate.checkpoint.character_id == "mikasa_01" and start.candidate.checkpoint.run_config.character_id == "mikasa_01","Selected identity reaches frozen run config and real state")
	result = b.store.commit_game(start.candidate,save.store_revision)
	t.check(result.get("ok") == true,"Selected character checkpoint commits through actual Core validator")
	if not result.get("ok",false): return
	reread = Store.new(b.directory,b.validator.restore).read_game()
	t.check(reread.get("ok") == true and reread.game_save.checkpoint.character_id == "mikasa_01","Cold Store restart restores selected run")
	t.check(b.service.prepare_character_selection(result.game_save,"chapter_01_shiganshina","garrison_01",result.game_save.store_revision).get("error_code") == "active_run","Cannot swap character inside an active run")
