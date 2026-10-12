extends "res://tests/app_async_autosave/test_default_worker.gd"
# The real actor's warning permits equivalent integer/float scalar encodings.
# Arrange the integer encoding and prove Core accepts it before saving. JSON
# normalizes it to floats; wire identity cannot be recreated from that value.
func run(t) -> void:
	await _canonical_success(t,false)
	await _canonical_success(t,true)
	await _predecessor_reconciliation(t)
	await t.create_timer(1.0).timeout
func _hazard_fixture(t,label: String):
	var app = _fixture(t,label)
	if app == null: return null
	app.state.active_tick = 107999
	app.state.survival_tick = 107999
	for tick in 1:
		var stepped: Dictionary = app._step_city_tick()
		if not stepped.get("ok",false):
			t.check(false,"wire fixture actual final Director/Core tick succeeds")
			app.free(); return null
	t.check(app.state.active_tick == 108000 and app.state.telegraphs.size() == 1 and app.state.entities.size() == 1,"actual Director/Core starts one physical actor warning")
	if app.state.telegraphs.size() != 1: app.free(); return null
	for field in ["damage","length","width"]:
		t.check(is_equal_approx(float(app.state.telegraphs[0][field]),float(int(app.state.telegraphs[0][field]))),"actual warning permits integral wire representation: "+field)
		app.state.telegraphs[0][field] = int(app.state.telegraphs[0][field])
	var checked: Dictionary = app.simulation.restore(app.state,app.simulation._streamed._hydration)
	t.check(checked.get("ok",false),"arranged integer warning retains actual Core snapshot validity")
	if not checked.get("ok",false): app.free(); return null
	t.check(app.state.telegraphs[0].damage is int and app.state.telegraphs[0].length is int and app.state.telegraphs[0].width is int,"wire fixture explicitly preserves integer scalar types before serialization")
	return app
func _canonical_success(t,unknown: bool) -> void:
	var app = _hazard_fixture(t,"wire_B_unknown" if unknown else "wire_B")
	if app == null: return
	var core = app.simulation
	var live: Dictionary = app.state.duplicate(true)
	var revision: int = app.game_save.store_revision
	if unknown: app.autosave_test_fault = {"stage":"after_replace_before_return","return_error":true,"persist_read_failure":true}
	app._save_checkpoint(); await _drain(t,app)
	if unknown:
		t.check(not app._autosave_unknown.is_empty(),"actual post-replace read failure retains exact pending B")
		app.autosave_test_fault = {}
		app.retry_save_recovery(); await _drain(t,app)
	t.check(app._autosave_blocker.is_empty() and app._autosave_unknown.is_empty() and app.game_save.store_revision == revision+1,"integer hazard B confirms exact wire authority once")
	t.check(app.simulation == core and app.state == live,"wire confirmation does not replace or rewind live state")
	var result: Dictionary = app.autosave_metrics.results.back()
	var path: String = app.save_store._directory.path_join("game_save.json")
	t.check(result.get("source_sha256") == FileAccess.get_sha256(path),"confirmed B SHA binds actual saved bytes")
	t.check(result.get("source_sha256") == JSON.stringify(result.get("authority",{}),"",true,true).sha256_text(),"returned B canonical retains exact source wire types")
	app.free()
func _predecessor_reconciliation(t) -> void:
	var app = _hazard_fixture(t,"wire_A")
	if app == null: return
	app.autosave_worker_enabled = false
	app._save_checkpoint()
	app.autosave_worker_enabled = true
	var path: String = app.save_store._directory.path_join("game_save.json")
	var prior_wire := FileAccess.get_file_as_string(path)
	var prior: Dictionary = app.game_save.duplicate(true)
	t.check(prior_wire.sha256_text() != JSON.stringify(prior,"",true,true).sha256_text(),"predecessor fixture begins with normalized authority different from actual integer wire")
	app.state.stats.damage_dealt += 1.0
	var live: Dictionary = app.state.duplicate(true)
	var core = app.simulation
	app.autosave_test_fault = {"stage":"after_replace_before_return","return_error":true,"persist_read_failure":true}
	app._save_checkpoint(); await _drain(t,app)
	t.check(not app._autosave_unknown.is_empty(),"A retry fixture retains ambiguous worker transaction")
	var job: Dictionary = app._autosave_unknown.duplicate(true)
	job.reconcile = true
	# Reproduce external recovery to the exact A bytes, only in our unique fixture.
	var file := FileAccess.open(path,FileAccess.WRITE)
	file.store_string(prior_wire); file.close()
	app.autosave_test_fault = {}
	app.retry_save_recovery(); await _drain(t,app)
	t.check(app._autosave_unknown.is_empty() and app._autosave_blocker.is_empty(),"exact integer-wire predecessor A resolves without false envelope failure")
	t.check(app.game_save == prior and app.simulation == core and app.state == live,"not-applied reconciliation changes neither authority nor current live state")
	var result: Dictionary = app.autosave_metrics.results.back()
	t.check(result.get("error_code") == "commit_not_applied" and result.get("source_sha256") == prior_wire.sha256_text(),"A result preserves validated primary wire SHA")
	if result.has("authority_wire"):
		t.check(result.authority_wire == prior_wire,"A proof carries actual bounded source bytes rather than normalized serialization")
		var bad: Dictionary = result.duplicate(true)
		bad.authority_wire += " "
		t.check(app._admit_worker_result(bad,job) == "worker_envelope_invalid","A proof rejects exact-byte tampering despite identical parsed meaning")
		bad = result.duplicate(true)
		var different: Dictionary = JSON.parse_string(bad.authority_wire)
		different.profile.supply_credits += 1
		bad.authority_wire = JSON.stringify(different,"",true,true)
		bad.source_sha256 = bad.authority_wire.sha256_text()
		t.check(app._admit_worker_result(bad,job) == "worker_envelope_invalid","A proof rejects fresh hash for a different semantic predecessor")
		bad = result.duplicate(true); bad.authority = []
		t.check(app._admit_worker_result(bad,job) == "worker_envelope_invalid","A proof rejects malformed normalized authority")
		bad = result.duplicate(true); bad.authority_wire = "[]"; bad.source_sha256 = "[]".sha256_text()
		t.check(app._admit_worker_result(bad,job) == "worker_envelope_invalid","A proof rejects non-authority wire payload")
	app.free()
