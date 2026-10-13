extends RefCounted
# Isolated one-job writer. No Node or main-thread object is received.
const City = preload("res://game/director/streamed_chapter_provider.gd")
const Runtime = preload("res://game/app/prepared_city_runtime.gd")
const Disk = preload("res://game/persistence/world_delta_store.gd")
const Save = preload("res://game/persistence/game_save_store.gd")
const Contracts = preload("res://game/contracts/game_save_contracts.gd")
const Core = preload("res://game/core/run_simulation.gd")
const Scope = preload("res://game/app/save_validation_scope.gd")
const Adapter = preload("res://game/app/world_checkpoint_adapter.gd")
const Helper = preload("res://game/core/streamed_run_world.gd")
var _control := Mutex.new()
var _job: Dictionary
var _result: Dictionary = {}
var _phase := "new"
var _cancelled := false
var _committing := false
var _trace := []
var _fault_fired := false
var _thread_id := 0
var _pending_canonical: Dictionary = {}
func _init(job: Dictionary) -> void:
	_job = job.duplicate(true)
func phase() -> String:
	_control.lock(); var value := _phase; _control.unlock(); return value
func cancel_before_commit() -> bool:
	_control.lock()
	var accepted: bool = not _committing and not _job.get("reconcile",false) and _phase != "finished"
	if accepted: _cancelled = true
	_control.unlock()
	return accepted
func result() -> Dictionary:
	_control.lock(); var value := _result; _result = {}; _control.unlock(); return value
func _set_phase(value: String) -> void:
	_control.lock(); _phase = value; _control.unlock()
func _stop_requested() -> bool:
	_control.lock(); var value := _cancelled; _control.unlock(); return value
func _begin_commit() -> bool:
	_control.lock()
	var permitted := not _cancelled
	if permitted: _committing = true; _phase = "committing"
	_control.unlock()
	return permitted
func run() -> void:
	_thread_id = OS.get_thread_caller_id()
	var before := Time.get_ticks_usec()
	var output := _execute()
	if not output.get("ok") is bool:
		output = _fail("commit_outcome_unknown" if _committing else "worker_failed")
		if _committing: output.pending_canonical = _pending_canonical.duplicate(true)
	output.worker_usec = Time.get_ticks_usec()-before
	output.worker_thread_id = _thread_id
	output.sequence = _job.sequence
	output.generation = _job.generation
	output.trace = _trace.duplicate()
	_control.lock(); _result = output; _phase = "finished"; _control.unlock()
func _fail(code: String) -> Dictionary: return {"ok":false,"error_code":code}
func _same(a: Variant, b: Variant) -> bool:
	return JSON.parse_string(JSON.stringify(a,"",true,true)) == JSON.parse_string(JSON.stringify(b,"",true,true))
func _fault(stage: String) -> int:
	_trace.append(stage)
	_set_phase("commit:"+stage)
	var plan: Dictionary = _job.get("fault",{})
	if _fault_fired and plan.get("persist_read_failure",false) and stage.begins_with("read_"): return ERR_CANT_CREATE
	if not _fault_fired and stage == plan.get("stage",""):
		_fault_fired = true
		if plan.get("create_alternate",false):
			var source := FileAccess.get_file_as_string(_job.directory.path_join("game_save.json"))
			var alternate: Dictionary = JSON.parse_string(source)
			alternate.profile.supply_credits += 1
			var file := FileAccess.open(_job.directory.get_base_dir().path_join("game_save.json"),FileAccess.WRITE)
			file.store_string(JSON.stringify(alternate,"",true,true)); file.close()
		if plan.get("delay_ms",0) > 0: OS.delay_msec(int(plan.delay_ms))
		if plan.get("return_error",false): return ERR_CANT_CREATE
	return OK
func _execute() -> Dictionary:
	_set_phase("constructing")
	var provider := City.new()
	var disk := Disk.new(_job.directory.path_join("world"))
	var runtime := Runtime.new(provider,disk)
	# Reconstruct the original validator's captured context without main objects.
	var baseline: Dictionary = _job.validator_context
	var validator := Core.new(Scope.CapturedProvider.new(baseline.chapter),null,baseline.definitions)
	validator._chapter_provider = provider
	validator._content_error = baseline.content_error
	runtime._validator = validator
	runtime._checkpoint = Adapter.new(disk,Callable(Helper,"requirements"),Callable(runtime,"_restore_checkpoint"))
	runtime._contracts = Contracts.new(Callable(runtime,"validate_checkpoint"),_job.runtime_catalog)
	# Resolve in this worker from immutable job identity and independently captured
	# files. Never replace the selected legacy provider with the current provider.
	var route: Dictionary = runtime.resolve_content(_job.snapshot)
	if not route.get("ok",false): return route
	if not _same(_job.get("content_route",{}),{"rules_version":route.rules_version,"content_fingerprint":route.chapter.content_fingerprint}): return _fail("content_mismatch")
	var store := Save.new(_job.directory,Callable(runtime,"validate_checkpoint"),Callable(self,"_fault"),Contracts.new(Callable(runtime,"validate_checkpoint"),_job.store_catalog))
	var scope = Scope.create(runtime,_job.directory,int(_job.authority.store_revision))
	var output: Dictionary
	if _job.get("reconcile",false):
		output = _reconcile(store,scope,_job.pending_canonical)
		output.receipt = _job.receipt.duplicate(true)
	else:
		output = _save(runtime,disk,store,scope)
	if scope != null: scope.close()
	return output
func _inspect(store, scope) -> Dictionary:
	_set_phase("inspecting")
	var inspection: Dictionary = store.inspect_known_locations_scoped(_job.directory.get_base_dir(),scope)
	if not inspection.get("ok",false): return _fail("invalid_game_save")
	match str(inspection.decision):
		"choose_lineage": return _fail("distinct_authorities")
		"retry_read": return _fail("read_failed")
		"blocked": return _fail(str(inspection.locations[0].get("error_code","invalid_game_save")))
	if inspection.locations[0].status == "absent": return _fail("authority_missing")
	return {"ok":true}
func _save(runtime, disk, store, scope) -> Dictionary:
	var inspected := _inspect(store,scope)
	if not inspected.ok: return inspected
	var loaded: Dictionary = store.read_game_scoped(scope)
	if not loaded.ok: return loaded
	if not _same(loaded.game_save,_job.authority): return _fail("stale_revision")
	if _stop_requested(): return _fail("autosave_cancelled")
	_set_phase("preparing")
	if _job.get("prepare_delay_ms",0) > 0: OS.delay_msec(int(_job.prepare_delay_ms))
	var candidate: Dictionary = _job.authority.duplicate(true)
	candidate.checkpoint = _job.snapshot.duplicate(true)
	for reason in ["background","controller_lost"]: candidate.checkpoint.pause_reasons.erase(reason)
	var world: Dictionary = candidate.checkpoint.world
	var pages: Dictionary = disk.prepare(world.delta_root,world.dirty_chunks,int(world.world_revision))
	if not pages.ok: return pages
	var accepted: Dictionary = Adapter.accept_receipt(world,pages.receipt)
	if not accepted.ok: return accepted
	candidate.checkpoint.world = accepted.world
	var prepared: Dictionary = runtime.prepare_commit_scoped(candidate,[],scope)
	if not prepared.ok: return prepared
	var canonical: Dictionary = runtime._pending.game_save.duplicate(true)
	_pending_canonical = canonical.duplicate(true)
	if not _begin_commit(): return _fail("autosave_cancelled")
	var committed: Dictionary = store.commit_game_scoped(candidate,int(candidate.store_revision),scope)
	if not committed.ok and committed.get("error_code") != "commit_outcome_unknown": return committed
	if committed.get("error_code") == "commit_outcome_unknown":
		scope.close()
		var fresh = Scope.create(runtime,_job.directory,int(_job.authority.store_revision))
		var observed := _reconcile(store,fresh,canonical)
		fresh.close()
		observed.was_unknown = true
		observed.receipt = pages.receipt.duplicate(true)
		return observed
	# Preserve the controller's post-commit known-location inspection before
	# releasing a confirmed candidate; a new alternate lineage is a barrier.
	var post_inspection := _inspect(store,scope)
	if not post_inspection.ok: return {"ok":false,"error_code":"commit_outcome_unknown","pending_canonical":canonical,"receipt":pages.receipt.duplicate(true)}
	var confirmed: Dictionary = runtime.confirm_candidate_scoped(store,scope)
	if not confirmed.get("ok",false): return {"ok":false,"error_code":"commit_outcome_unknown","pending_canonical":canonical,"receipt":pages.receipt.duplicate(true)}
	# Confirmation already validated the normalized read and exact pending SHA.
	# Return that same pre-write canonical, preserving its original wire types.
	return {"ok":true,"authority":canonical.duplicate(true),"source_sha256":confirmed.source_sha256,"receipt":pages.receipt.duplicate(true)}
func _reconcile(store, scope, canonical: Dictionary) -> Dictionary:
	var inspected := _inspect(store,scope)
	if not inspected.ok: return {"ok":false,"error_code":"commit_outcome_unknown","pending_canonical":canonical.duplicate(true)}
	var observed: Dictionary = store.read_game_scoped(scope)
	if observed.get("ok",false) and not observed.get("recovered",false) and _same(observed.game_save,canonical) and observed.source_sha256 == JSON.stringify(canonical,"",true,true).sha256_text():
		return {"ok":true,"authority":canonical.duplicate(true),"source_sha256":observed.source_sha256,"receipt":_job.get("receipt",{}).duplicate(true)}
	if observed.get("ok",false) and not observed.get("recovered",false) and _same(observed.game_save,_job.authority):
		# A can have been adopted from a read-normalized synchronous save. Its
		# number types cannot reconstruct the writer's original JSON bytes.
		var wire := _confirmed_primary_wire(observed.source_sha256)
		if not wire.is_empty(): return {"ok":false,"error_code":"commit_not_applied","authority":observed.game_save.duplicate(true),"source_sha256":observed.source_sha256,"authority_wire":wire}
	return {"ok":false,"error_code":"commit_outcome_unknown","pending_canonical":canonical.duplicate(true)}

func _confirmed_primary_wire(validated_sha256: String) -> String:
	# Only the exceptional A reconciliation needs raw bytes. Bind this bounded
	# fresh read to the already fully validated, non-recovered primary read.
	var file := FileAccess.open(_job.directory.path_join("game_save.json"),FileAccess.READ)
	if file == null: return ""
	var length := file.get_length()
	if length > Save.MAX_BYTES:
		file.close(); return ""
	var bytes := file.get_buffer(length)
	var error := file.get_error()
	file.close()
	if bytes.size() != length or not error in [OK,ERR_FILE_EOF]: return ""
	var wire := bytes.get_string_from_utf8()
	if wire.to_utf8_buffer() != bytes or wire.sha256_text() != validated_sha256: return ""
	return wire
