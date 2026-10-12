extends RefCounted
# Real atomic Store and economic service; SHAPE-only combat fixture is explicit.
const Store = preload("res://game/persistence/game_save_store.gd")
const Service = preload("res://game/economy/supply_service.gd")
const Cases = preload("res://tests/persistence/test_game_save_store.gd")
const EconomyCases = preload("res://tests/economy/test_supply_service.gd")
const Fixture = preload("res://tests/fixtures/evolution_supply_fixture.gd")
func run(t) -> void:
	var fixture = Fixture.new()
	var service = Service.new(fixture.make_run)
	var cases = Cases.new()
	var economy = EconomyCases.new()
	for stage in ["write","flush","verify","backup","replace","after_replace_before_return","readback_after_replace",""]:
		var directory: String = cases._directory("permanent_"+stage)
		var save: Dictionary = cases._funded(t,directory)
		if save.is_empty(): return
		var old_bytes := FileAccess.get_file_as_string(directory.path_join("game_save.json"))
		var id := economy._purchase_id(save,"permanent_vitality")
		var purchase: Dictionary = service.prepare_purchase(save,"permanent_vitality",id,save.store_revision)
		t.check(purchase.get("ok") == true,"Permanent store purchase prepares "+stage)
		if not purchase.get("ok",false): continue
		var fault = func(at): return ERR_UNAVAILABLE if not stage.is_empty() and at == stage else OK
		var result: Dictionary = Store.new(directory,fixture.validate_checkpoint,fault).commit_game(purchase.candidate,save.store_revision)
		var applied: bool = stage in ["after_replace_before_return","readback_after_replace",""]
		t.check(result.get("ok") == stage.is_empty(),"Permanent commit accurately reports outcome "+stage)
		var reread: Dictionary = Store.new(directory,fixture.validate_checkpoint).read_game()
		t.check(reread.get("ok") == true,"Restart reads complete authority "+stage)
		if not reread.get("ok",false): continue
		var fresh: Dictionary = reread.game_save
		t.check(fresh.profile.supply_credits == (35 if applied else 55),"Gold and saved level move atomically "+stage)
		t.check(fresh.profile.get("permanent_upgrades",{}).get("permanent_vitality",0) == (1 if applied else 0),"Upgrade restores on restart "+stage)
		if applied:
			var retry: Dictionary = service.prepare_purchase(fresh,"permanent_vitality",id,save.store_revision)
			t.check(retry.get("already_applied") == true and not retry.has("candidate"),"Readback reconciles duplicate without second debit "+stage)
		else: t.check(FileAccess.get_file_as_string(directory.path_join("game_save.json")) == old_bytes,"Pre-replace failure keeps exact legacy bytes "+stage)
		if stage.is_empty():
			var start_id := economy._start_id(fresh)
			var prepared: Dictionary = service.prepare_run_start(fresh,economy._chapter(),24,start_id,fresh.store_revision)
			t.check(prepared.get("ok") == true,"Persisted upgrade can start next run")
			if not prepared.get("ok",false): continue
			var forged: Dictionary = prepared.candidate.duplicate(true)
			forged.checkpoint.run_config.permanent_upgrades.permanent_vitality = 5
			t.check(Store.new(directory,fixture.validate_checkpoint).commit_game(forged,fresh.store_revision).get("ok") == false,"Forged run bonus cannot exceed purchased profile")
			var started: Dictionary = Store.new(directory,fixture.validate_checkpoint).commit_game(prepared.candidate,fresh.store_revision)
			t.check(started.get("ok") == true,"Next run with purchased bonus commits")
			if not started.get("ok",false): continue
			t.check(started.game_save.checkpoint.run_config.permanent_upgrades.permanent_vitality == 1,"Next run contains saved permanent level")
			t.check(service.prepare_run_start(started.game_save,economy._chapter(),24,start_id,fresh.store_revision).get("already_applied") == true,"Duplicate start preserves upgrade and serial")
			var terminal: Dictionary = economy._terminal(started.game_save)
			var settlement: Dictionary = service.prepare_settlement(started.game_save,terminal)
			var settled: Dictionary = Store.new(directory,fixture.validate_checkpoint).commit_game(settlement.candidate,started.game_save.store_revision)
			t.check(settled.get("ok") == true,"Upgraded run settlement commits")
			if settled.get("ok",false):
				t.check(service.prepare_settlement(settled.game_save,terminal).get("already_applied") == true,"Duplicate settlement never mints gold twice")
				t.check(settled.game_save.profile.supply_credits == 90 and settled.game_save.profile.permanent_upgrades.permanent_vitality == 1,"Settlement keeps permanent level and exact gold")
	var directory: String = cases._directory("permanent_forgery")
	var save: Dictionary = cases._funded(t,directory)
	var tampered := save.duplicate(true)
	tampered.profile.permanent_upgrades = {"permanent_might":5}
	t.check(Store.new(directory,fixture.validate_checkpoint).commit_game(tampered,save.store_revision).get("ok") == false,"Direct save cannot mint permanent levels without purchase")
