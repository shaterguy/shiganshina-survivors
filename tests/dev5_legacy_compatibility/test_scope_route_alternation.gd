extends RefCounted
const F = preload("res://tests/dev5_legacy_compatibility/legacy_fixture.gd")
const Runtime = preload("res://game/app/prepared_city_runtime.gd")
const Scope = preload("res://game/app/save_validation_scope.gd")
func run(t) -> void:
	var directory := F.install("scope_alternation")
	var reference := F.legacy_authority(directory)
	var control: Dictionary = reference.store.read_game()
	t.check(control.get("ok",false),"scope alternation starts with a valid pinned original dev4 checkpoint")
	if not control.get("ok",false): return
	var provider := F.City.new()
	var disk := F.Disk.new(directory.path_join("world"))
	var runtime := Runtime.new(provider,disk)
	var current_chapter: Dictionary = provider.load_chapter(F.Chapters.CHAPTER_ID).chapter
	var current_state: Dictionary = runtime.new_run(current_chapter,77,control.game_save.checkpoint.run_config)
	t.check(current_state.has("world") and current_state.rules.content_fingerprint != F.FINGERPRINT,"alternating current state comes from the real new-run Core with a distinct current fingerprint")
	if not current_state.has("world"): return
	var pages: Dictionary = disk.prepare(current_state.world.delta_root,[],0)
	t.check(pages.get("ok",false),"current candidate has real verified empty-world pages beside the legacy pages")
	if not pages.get("ok",false): return
	var current: Dictionary = control.game_save.duplicate(true)
	current.checkpoint = current_state
	var scope = Scope.create(runtime,directory,int(control.game_save.store_revision))
	t.check(scope != null,"one production Scope accepts both recognized content routes")
	if scope == null: return
	var legacy_a: Dictionary = runtime._contracts.validate_and_normalize(control.game_save,scope,{"slot":"A"})
	t.check(legacy_a.get("ok",false) and scope._captured_core._chapter_provider.rules_version() == "dev4","first legacy route receives the pinned captured Core")
	var current_b: Dictionary = runtime._contracts.validate_and_normalize(current,scope,{"slot":"B"})
	t.check(current_b.get("ok",false) and scope._captured_core._chapter_provider.rules_version() == "dev5" and scope._captured_core._catalog.evolutions._schema_version == 2,"same Scope validates real current candidate with its separate current Core")
	var legacy_again: Dictionary = runtime._contracts.validate_and_normalize(control.game_save,scope,{"slot":"A"})
	var stats: Dictionary = scope.diagnostics()
	t.check(legacy_again.get("ok",false) and F.same(legacy_again,legacy_a) and scope._captured_core._chapter_provider.rules_version() == "dev4","returning to legacy yields the exact original canonical authority and mode")
	t.check(stats.restore_calls == 2 and stats.hits == 1 and stats.misses_A == 1 and stats.misses_B == 1,"legacy to current to legacy retains only its exact disjoint A/B proof hit")
	scope.close()
