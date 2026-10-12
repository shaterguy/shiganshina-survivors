extends RefCounted
const X = preload("res://tests/fantasy_skills/fantasy_fixture.gd")
const Core = preload("res://game/core/run_simulation.gd")
const F = preload("res://tests/core/new_current_regression_fixture.gd")
const Finite = preload("res://tests/core/finite_chapter_provider.gd")
const Store = preload("res://game/persistence/game_save_store.gd")
const Service = preload("res://game/economy/supply_service.gd")
const Fixture = preload("res://tests/fixtures/evolution_supply_fixture.gd")
const Files = preload("res://tests/persistence/test_game_save_store.gd")
func run(t) -> void:
	var inputs := {}
	for path in Core.GAMEPLAY_PATHS: inputs[path] = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fantasy_skills/legacy_inputs/"+path.get_file()))
	var old := Core.new(Finite.new(),null,inputs)
	var config: Dictionary = F.run_config()
	config.permanent_upgrades = {"permanent_might":2,"permanent_vitality":1}
	var source: Dictionary = Fixture.new().game_save()
	source.store_revision = 7
	source.next_run_serial = 2
	source.profile.supply_credits = 145
	source.profile.permanent_upgrades = config.permanent_upgrades.duplicate(true)
	source.profile.owned_doctrine_ids = ["doctrine_standard","doctrine_mobile"]
	source.profile.settings.retained_marker = "same-career"
	source.profile.best_runs = {"chapter_01_shiganshina":{"survival_tick":120,"kills":2,"won":false}}
	source.checkpoint = old.new_run(Finite.new().load_chapter("chapter_01_shiganshina").chapter,42,config)
	t.check(old.restore(source.checkpoint).get("ok",false),"source checkpoint is an actual valid old-content run")
	var files := Files.new()
	var directory: String = files._directory("fantasy_preserve")
	var original := JSON.stringify(source,"  ")
	files._write(directory.path_join("game_save.json"),original)
	var sim = X.simulation()
	var store := Store.new(directory,sim.restore)
	var blocked: Dictionary = store.read_game()
	t.check(blocked.get("error_code") == "content_mismatch","changed gameplay fingerprint preserves old checkpoint behind existing mismatch boundary")
	var offer: Dictionary = store.inspect_checkpoint_recovery()
	t.check(offer.get("ok",false),"existing preserve/new-run route exposes old economic authority")
	if not offer.get("ok",false): return
	var archived: Dictionary = store.preserve_checkpoint_authority(offer.recovery_offer.source_sha256,7)
	t.check(archived.get("ok",false),"actual Store archives exact old save before new fantasy-content run")
	if not archived.get("ok",false): return
	var selection: Dictionary = source.profile.loadout.duplicate(true)
	selection.target_evolution_id = "evo_storm_chain"
	var id := "recover:%s:%s:2" % [source.career_id,offer.recovery_offer.source_sha256]
	var service := Service.new(sim.new_run)
	var prepared: Dictionary = service.prepare_preserved_run_start(archived.source,X.chapter(),44,selection,id,archived.archive_receipt,7)
	t.check(prepared.get("ok",false),"preserved profile starts actual current Core with a new ultimate target")
	if not prepared.get("ok",false): return
	var committed: Dictionary = store.commit_preserved_run_start(prepared.candidate,offer.recovery_offer.source_sha256,id,7)
	t.check(committed.get("ok",false),"actual atomic Store commits replacement fantasy run")
	if not committed.get("ok",false): return
	var reread: Dictionary = Store.new(directory,sim.restore).read_game()
	t.check(reread.get("ok",false),"new fantasy run and profile survive actual disk reread")
	if not reread.get("ok",false): return
	var profile: Dictionary = reread.game_save.profile
	for field in ["supply_credits","permanent_upgrades","unlocked_character_ids","owned_doctrine_ids","best_runs","settings"]:
		t.check(profile[field] == source.profile[field],"content replacement preserves exact profile "+field)
	t.check(is_equal_approx(reread.game_save.checkpoint.rules.permanent_damage_bonus,0.1),"preserved might level still contributes to new skill damage")
	t.check(files._read(directory.path_join("archives/"+offer.recovery_offer.source_sha256+".json")) == original,"old gameplay authority remains byte-exact in archive")
