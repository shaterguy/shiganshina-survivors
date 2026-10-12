extends RefCounted
const Catalog = preload("res://game/economy/supply_catalog.gd")
const Service = preload("res://game/economy/supply_service.gd")
const Fixture = preload("res://tests/fixtures/evolution_supply_fixture.gd")
func run(t) -> void:
	var catalog = Catalog.new()
	t.check(catalog.validate().is_empty(),"Permanent catalog is valid")
	for id in ["permanent_might","permanent_vitality","permanent_magnet"]:
		var item: Dictionary = catalog.item(id)
		t.check(item.get("kind") == "permanent_upgrade","Permanent upgrade exists: "+id)
		if item.is_empty(): continue
		t.check(item.max_owned == 5 and item.level_prices == [20,35,55,80,110],"Permanent price ladder and cap: "+id)
	var fixture = Fixture.new()
	var save: Dictionary = fixture.game_save()
	save.profile.supply_credits = 100
	var view: Dictionary = Service.new(fixture.make_run).shop_view(save)
	var found := 0
	for row in view.items:
		if row.kind != "permanent_upgrade": continue
		found += 1
		t.check(row.get("level") == 0 and row.get("max_level") == 5,"Legacy save begins at level zero")
		t.check(row.get("next_price") == 20 and row.price == 20 and row.balance_after == 80,"Next purchase has exact price and balance")
		t.check(row.get("current_effect_text","") != row.get("next_effect_text","") and not row.get("is_max",true),"Current and next effects are distinct")
	t.check(found == 3,"Legacy shop offers three permanent upgrades")
	t.check(not save.profile.has("permanent_upgrades"),"Viewing legacy profile does not mutate it")
	_purchase_cases(t)
	_profile_contract_cases(t)
func _purchase_cases(t) -> void:
	var fixture = Fixture.new()
	var service = Service.new(fixture.make_run)
	var save: Dictionary = fixture.game_save()
	save.profile.supply_credits = 300
	var prices := [20,35,55,80,110]
	for level in range(5):
		var id := "purchase:%s:%d:permanent_might" % [save.career_id,save.store_revision]
		var before := JSON.stringify(save)
		var bought: Dictionary = service.prepare_purchase(save,"permanent_might",id,save.store_revision)
		t.check(bought.get("ok") == true,"Permanent level purchase succeeds: %d" % level)
		t.check(JSON.stringify(save) == before,"Purchase preserves original authority")
		if not bought.get("ok",false): return
		t.check(bought.receipt.price == prices[level] and bought.receipt.owned_after == level+1,"Receipt records actual level and increasing price")
		t.check(bought.candidate.profile.get("permanent_upgrades",{}).get("permanent_might") == level+1,"Permanent level is stored separately from consumables")
		t.check(bought.candidate.profile.consumables == save.profile.consumables and bought.candidate.profile.best_runs == save.profile.best_runs,"Upgrade preserves inventory and career")
		save = bought.candidate
		save.store_revision += 1
		var retry: Dictionary = service.prepare_purchase(save,"permanent_might",id,save.store_revision-1)
		t.check(retry.get("already_applied") == true and not retry.has("candidate"),"Duplicate purchase is receipt-only")
	t.check(save.profile.supply_credits == 0,"Five levels debit exact cumulative price")
	var blocked: Dictionary = service.prepare_purchase(save,"permanent_might","purchase:%s:%d:permanent_might" % [save.career_id,save.store_revision],save.store_revision)
	t.check(blocked.get("error_code") == "max_level","Max level blocks purchase before balance check")
	for row in service.shop_view(save).items:
		if row.item_id == "permanent_might": t.check(row.is_max and row.next_price == null and row.price == 0 and row.blocked_reason == "max_level" and row.current_effect_text == "공격력 +25%","Max DTO has no false next price")
	var poor: Dictionary = fixture.game_save()
	poor.profile.supply_credits = 19
	t.check(service.prepare_purchase(poor,"permanent_vitality","purchase:%s:0:permanent_vitality" % poor.career_id,0).get("error_code") == "insufficient_funds","Insufficient funds cannot upgrade")
	var started: Dictionary = service.prepare_run_start(save,load("res://tests/economy/test_supply_service.gd").new()._chapter(),23,"start:%s:1" % save.career_id,save.store_revision)
	t.check(started.get("ok") == true,"Upgraded profile starts next run")
	if started.get("ok",false):
		t.check(started.candidate.checkpoint.run_config.get("permanent_upgrades",{}) == {"permanent_might":5},"Next run freezes purchased levels")
		started.candidate.profile.permanent_upgrades.permanent_might = 4
		t.check(started.candidate.checkpoint.run_config.get("permanent_upgrades",{}).get("permanent_might") == 5,"Run config does not alias profile levels")
func _profile_contract_cases(t) -> void:
	var contracts = load("res://game/contracts/game_save_contracts.gd").new(Callable())
	var fixture = Fixture.new()
	for invalid in [null,[],{"unknown":1},{"permanent_might":true},{"permanent_might":1.5},{"permanent_might":-1},{"permanent_might":6},{"permanent_might":NAN}]:
		var save: Dictionary = fixture.game_save()
		save.profile.permanent_upgrades = invalid
		t.check(not contracts.validate_economy(save).is_empty(),"Malformed permanent levels fail closed: "+str(invalid))
	var valid: Dictionary = fixture.game_save()
	valid.profile.permanent_upgrades = {"permanent_might":2.0}
	t.check(contracts.validate_economy(valid).is_empty(),"JSON integer-valued levels remain valid")

	var migrations = load("res://game/persistence/save_migrations.gd").new()
	var legacy: Dictionary = load("res://tests/persistence/test_save_migrations.gd").new()._profile()
	legacy["permanent_upgrades"] = {"permanent_might":5}
	t.check(migrations.from_v1(legacy,false,"0123456789abcdef0123456789abcdef").get("error_code") == "invalid_profile","Mislabeled legacy save cannot carry invented permanent levels")
