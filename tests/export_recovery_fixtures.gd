extends SceneTree
const Chapters = preload("res://game/director/chapter_catalog.gd")
const Core = preload("res://game/core/run_simulation.gd")
const F = preload("res://tests/core/core_fixture.gd")
const Finite = preload("res://tests/core/finite_chapter_provider.gd")
const Migrations = preload("res://game/persistence/save_migrations.gd")
const Service = preload("res://game/economy/supply_service.gd")
const Store = preload("res://game/persistence/game_save_store.gd")
const ROOT := "res://tests/fixtures/evolution_supply_recovery/"
var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; print("FAIL: "+label)
func _initialize() -> void: call_deferred("run")
func write_json(path: String,value: Variant) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path,FileAccess.WRITE)
	f.store_string(JSON.stringify(value,"  ",true,true)+"\n"); f.close()
func run() -> void:
	var chapter: Dictionary = Chapters.new().load_chapter("chapter_01_shiganshina").chapter
	check(chapter.content_revision == "ch01.3-rebuild.6-harmless-recovery","actual catalog has new revision")
	write_json("res://tests/fixtures/c4/finite_chapter_definition_recovery.json",chapter)
	var provider := Finite.new()
	var finite: Dictionary = provider.load_chapter(chapter.chapter_id).chapter
	var sim := Core.new(provider)
	var profile := {"schema_version":1,"settings":{"deadzone":0.2,"audio_master":0.8,"screen_shake":0.5,"reduce_effects":false},"cleared_chapter_ids":[],"unlocked_character_ids":["garrison_01"],"best_runs":{}}
	var empty: Dictionary = Migrations.new().from_v1(profile,false,"0123456789abcdef0123456789abcdef").game_save
	var directory := "user://generated_recovery_fixture_%d" % OS.get_process_id()
	write_json(directory.path_join("game_save.json"),empty)
	var store := Store.new(directory,Callable(sim,"restore"))
	var loaded := store.load_game()
	check(loaded.get("ok",false),"actual Store validates generated never-started career")
	var service := Service.new(Callable(sim,"new_run"))
	var prepared := service.prepare_run_start(loaded.game_save,finite,42,"start:0123456789abcdef0123456789abcdef:1",0)
	check(prepared.get("ok",false),"actual Service/Core generates .6 initial run")
	var committed := store.commit_game(prepared.candidate,0)
	check(committed.get("ok",false),"actual Store commits .6 initial checkpoint")
	var initial: Dictionary = committed.game_save.checkpoint
	check(sim.restore(initial).get("ok",false),"actual finite Core accepts generated initial checkpoint")
	write_json(ROOT+"run_v2.json",{"initial":initial})
	write_json(ROOT+"game_save_v2.json",{"empty":empty,"started":committed.game_save})
	write_json(ROOT+"content_identity_basis.json",{"identity_version":1,"base_definition_fingerprint":chapter.content_fingerprint,"world_mode":"finite_test","chapter":_identity_input(chapter)})
	var ready := F.evolution_ready_state(sim,finite,F.run_config())
	check(not ready.is_empty(),"actual boss kill produces evolution-ready run")
	write_json(ROOT+"actual_evolution_ready.json",ready)
	var selected: Dictionary = sim.choose_upgrade(ready,ready.upgrade_offer.offer_id,"evolution:evo_wing_cut")
	check(selected.get("ok",false) and sim.restore(ready).get("ok",false),"actual evolution choice and strict restore succeed")
	write_json(ROOT+"actual_evolution_chosen.json",ready)
	write_json(ROOT+"actual_evolution_events.json",selected.events)
	var files := {}
	for file in DirAccess.open(ROOT).get_files():
		if file.ends_with(".json") and file != "provenance.json": files[file] = FileAccess.get_sha256(ROOT+file)
	write_json(ROOT+"provenance.json",{"schema_version":1,"origin_class":"NEW","content_revision":chapter.content_revision,"claim":"New initial/evolution runs from actual .6 Core and initial authorities committed by real Store. Not recovered originals. Copied rendering DTOs remain illustrative, not real Core action traces.","fixture_content_fingerprint":initial.rules.content_fingerprint,"fingerprint_basis_file":"content_identity_basis.json","fingerprint_scope":"Canonical digest of actual exported catalog bound by existing finite_test Provider; no legacy run relabeling.","production_fingerprint":chapter.content_fingerprint,"core_sha256":FileAccess.get_sha256("res://game/core/run_simulation.gd"),"engine":Engine.get_version_info().string,"files":files,"copied_unchanged_dtos":["attack_events.json","progression_source_offers.json","progression_views.json","supply_views.json"],"arrangement":"Evolution prerequisite weapon/passive levels are test-only; real authored boss kill, reward, choice and restore paths execute."})
	print("RECOVERY_FIXTURE_EXPORT checks=%d failures=%d" % [checks,failures])
	await process_frame
	await process_frame
	quit(0 if failures == 0 else 1)
func _identity_input(chapter: Dictionary) -> Dictionary:
	var value := chapter.duplicate(true)
	value.world_mode = "finite_test"
	value.content_identity_kind = "frozen_finite_test_definitions"
	return value
