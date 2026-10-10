extends RefCounted
# NEW E1 blocking review regressions. All authority/factory inputs are SHAPE-only fixtures.
const Service = preload("res://game/economy/supply_service.gd")
const Cases = preload("res://tests/economy/test_supply_service.gd")
const Contracts = preload("res://game/contracts/game_save_contracts.gd")
var _cases = Cases.new()
func _rejected(t, result: Variant, label: String) -> void:
	t.check(result is Dictionary and result.get("ok") == false and result.get("error_code") is String and not result.get("error_code","").is_empty() and not result.has("candidate"),label+" explicit failure without candidate")
func run(t) -> void:
	print("E1 HOSTILE TYPES: reviewer fail-open regressions; SHAPE fixtures only")
	var service = Service.new(_cases._fixture.make_run)
	var active: Dictionary = _cases._fixture.game_save("started")
	var terminal: Dictionary = _cases._terminal(active)
	var settled: Dictionary = service.prepare_settlement(active,terminal).candidate
	settled.store_revision += 1
	var fields := {
		"schema_version":["2",null,true,{},[],NAN,0.5],
		"run_id":[123,null,true,{},[],Vector2.ZERO,""],
		"run_serial":["1",null,true,{},[],NAN,0.5],
		"seed":["42",null,true,{},[],NAN,0.5],
		"chapter_id":[123,null,true,{},[],""],
		"content_revision":[123,null,true,{},[],""],
		"supply_used":["false",null,123,{},[]],
		"phase":[123,null,true,{},[],""]}
	for field in fields:
		for wrong in fields[field]:
			var save: Dictionary = settled.duplicate(true)
			save.checkpoint[field] = wrong
			_check_all_authority_paths(t,service,save,terminal,"checkpoint "+field+" type "+str(typeof(wrong)))
	for field in ["run_id","run_serial","doctrine_id","target_evolution_id","prepared_supply"]:
		for wrong in [123,null,true,{},[],"",Vector2.ZERO]:
			if field == "prepared_supply" and wrong is String and wrong == "": continue
			if field == "run_serial" and wrong is int: wrong = "1"
			var save: Dictionary = settled.duplicate(true)
			save.checkpoint.run_config[field] = wrong
			_check_all_authority_paths(t,service,save,terminal,"config "+field+" type "+str(typeof(wrong)))
	for field in fields:
		for wrong in fields[field]:
			var broken := terminal.duplicate(true)
			broken[field] = wrong
			var before := broken.duplicate(true)
			_rejected(t,service.prepare_settlement(active,broken),"terminal "+field+" type "+str(typeof(wrong)))
			t.check(_cases._same(broken,before),"terminal input unchanged "+field)
	for field in fields:
		for wrong in fields[field]:
			var bad_factory = Service.new(func(chapter,seed,config):
				var run: Dictionary = _cases._fixture.make_run(chapter,seed,config)
				run[field] = wrong
				return run)
			var save: Dictionary = _cases._save()
			var before := save.duplicate(true)
			_rejected(t,bad_factory.prepare_run_start(save,_cases._chapter(),42,_cases._start_id(save),0),"factory "+field+" type "+str(typeof(wrong)))
			t.check(_cases._same(save,before),"bad factory preserves source "+field)
	for output in [{"ok":false},{"ok":"false","error_code":"invalid_chapter"},{"ok":false,"error_code":123},null,[],true]:
		var bad_factory = Service.new(func(_chapter,_seed,_config): return output)
		var save: Dictionary = _cases._save()
		_rejected(t,bad_factory.prepare_run_start(save,_cases._chapter(),42,_cases._start_id(save),0),"factory failure-envelope type "+str(typeof(output)))
	for wrong in [123,true,{},[],null]:
		var save: Dictionary = active.duplicate(true)
		save.checkpoint.rules.content_fingerprint = wrong
		_check_all_authority_paths(t,service,save,terminal,"current fingerprint type "+str(typeof(wrong)))
	for wrong in [123,"true",{},[],null]:
		var won: Dictionary = terminal.duplicate(true)
		won.phase = "won"
		won.evacuation_ready = wrong
		won.survival_tick = 108000
		won.active_tick = 112500
		won.final_started_tick = 108000
		_rejected(t,service.prepare_settlement(active,won),"won evacuation_ready type "+str(typeof(wrong)))
	var poisoned_error := {"ok":false,"error_code":"invalid_chapter","candidate":{"unvalidated":true},"already_applied":true,"receipt":{"unvalidated":true},"diagnostics":{"field":"chapter_id"}}
	var error_factory = Service.new(func(_chapter,_seed,_config): return poisoned_error)
	var error_source: Dictionary = _cases._save()
	var projected: Dictionary = error_factory.prepare_run_start(error_source,_cases._chapter(),42,_cases._start_id(error_source),0)
	_rejected(t,projected,"factory failure cannot forward candidate")
	t.check(not projected.has("receipt") and not projected.has("already_applied"),"factory failure strips success-only markers")
	t.check(projected.get("error_code") == "invalid_chapter" and projected.get("diagnostics") == {"field":"chapter_id"},"factory failure preserves safe error diagnostics")
	projected.diagnostics.field = "changed"
	t.check(poisoned_error.diagnostics.field == "chapter_id","factory failure diagnostics privately copied")
	for wrong in [0.1,0.9,-0.1,"0",null,true,{},[],NAN]:
		var save: Dictionary = _cases._save()
		_rejected(t,service.callv("prepare_purchase",[save,"field_bandage",_cases._purchase_id(save,"field_bandage"),wrong]),"purchase revision must not coerce "+str(typeof(wrong)))
		_rejected(t,service.callv("prepare_loadout",[save,save.profile.loadout,wrong]),"loadout revision must not coerce "+str(typeof(wrong)))
		_rejected(t,service.callv("prepare_run_start",[save,_cases._chapter(),42,_cases._start_id(save),wrong]),"start revision must not coerce "+str(typeof(wrong)))
	for wrong in [-1,2147483648,42.5,"42",null,true,{},[],NAN]:
		var save: Dictionary = _cases._save()
		_rejected(t,service.callv("prepare_run_start",[save,_cases._chapter(),wrong,_cases._start_id(save),0]),"start seed must not coerce "+str(typeof(wrong)))
	for wrong in [null,true,123,"save",[],Vector2.ZERO]:
		_rejected(t,service.callv("prepare_purchase",[wrong,"field_bandage","request",0]),"purchase invalid root "+str(typeof(wrong)))
		_rejected(t,service.callv("prepare_loadout",[wrong,{},0]),"loadout invalid root "+str(typeof(wrong)))
		_rejected(t,service.callv("prepare_run_start",[wrong,_cases._chapter(),42,"request",0]),"start invalid root "+str(typeof(wrong)))
		_rejected(t,service.callv("prepare_settlement",[wrong,terminal]),"settlement invalid root "+str(typeof(wrong)))
		_rejected(t,service.callv("prepare_settlement",[active,wrong]),"terminal invalid root "+str(typeof(wrong)))
		var invalid_view = service.callv("shop_view",[wrong])
		t.check(invalid_view is Dictionary and invalid_view.get("can_shop") == false and invalid_view.get("can_start") == false,"invalid view root fails closed")
	var scalar_save: Dictionary = _cases._save()
	var normalized: Dictionary = service.prepare_run_start(scalar_save,_cases._chapter(),42.0,_cases._start_id(scalar_save),0.0)
	t.check(normalized.get("ok") == true and normalized.candidate.checkpoint.seed is int and normalized.candidate.checkpoint.seed == 42,"integral seed/revision normalize only after validation")
	for seed in [0,2147483647]:
		var edge: Dictionary = service.prepare_run_start(scalar_save,_cases._chapter(),seed,_cases._start_id(scalar_save),0)
		t.check(edge.get("ok") == true and edge.candidate.checkpoint.seed == seed,"31-bit seed endpoint accepted "+str(seed))
	var extra_loadout: Dictionary = settled.duplicate(true)
	extra_loadout.profile.loadout["grant_credits"] = 500
	_rejected(t,service.prepare_purchase(extra_loadout,"field_bandage",_cases._purchase_id(extra_loadout,"field_bandage"),int(extra_loadout.store_revision)),"profile loadout extras rejected")
	var contracts = Contracts.new(Callable())
	for kind in ["purchase","settlement"]:
		for field in (["request_id"] if kind == "purchase" else ["request_id","run_id"]):
			for wrong in [123,null,true,{},[]]:
				var save: Dictionary = settled.duplicate(true)
				if kind == "purchase":
					save.purchase_receipts = [{"request_id":wrong,"item_id":"field_bandage","expected_revision":0,"price":15,"balance_after":40,"owned_after":1}]
				else: save.settlement_receipts[0][field] = wrong
				var before := save.duplicate(true)
				t.check(not contracts.validate_economy(save).is_empty(),"Contracts rejects receipt wrong type "+kind+"/"+field)
				_rejected(t,service.prepare_purchase(save,"field_bandage",_cases._purchase_id(save,"field_bandage"),int(save.store_revision)),"receipt wrong type fails Service "+kind+"/"+field)
				t.check(_cases._same(save,before),"receipt validator input unchanged")
	for profile_schema in ["2",null,true,{},[]]:
		var save: Dictionary = _cases._save()
		save.profile.schema_version = profile_schema
		t.check(not contracts.validate_economy(save).is_empty(),"Contracts rejects profile schema wrong type")
	for schema in ["2",null,true,{},[]]:
		var save: Dictionary = _cases._save()
		save.schema_version = schema
		t.check(not contracts.validate_economy(save).is_empty(),"Contracts rejects root schema wrong type")
func _check_all_authority_paths(t,service,save: Dictionary,terminal: Dictionary,label: String) -> void:
	var before := save.duplicate(true)
	_rejected(t,service.prepare_purchase(save,"field_bandage",_cases._purchase_id(save,"field_bandage"),int(save.store_revision)),label+" purchase")
	_rejected(t,service.prepare_loadout(save,save.profile.loadout,int(save.store_revision)),label+" loadout")
	_rejected(t,service.prepare_run_start(save,_cases._chapter(),42,"start:%s:1" % save.career_id,0),label+" start/retry")
	_rejected(t,service.prepare_settlement(save,terminal),label+" settlement/retry")
	var view: Dictionary = service.shop_view(save)
	t.check(view.get("can_shop") == false and view.get("can_start") == false and not view.get("lock_reason","").is_empty(),label+" view held")
	t.check(_cases._same(save,before),label+" authority input unchanged")
