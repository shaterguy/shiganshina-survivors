extends RefCounted
# NEW 2026-10-10 optional city boundary. No default activation, writes or live Core.
# Retain this object while its validator/new_run Callables are bound by consumers.
const City = preload("res://game/director/streamed_chapter_provider.gd")
const Router = preload("res://game/director/run_content_router.gd")
const Core = preload("res://game/core/run_simulation.gd")
const Helper = preload("res://game/core/streamed_run_world.gd")
const Checkpoint = preload("res://game/app/world_checkpoint_adapter.gd")
const Contracts = preload("res://game/contracts/game_save_contracts.gd")
const Disk = preload("res://game/persistence/world_delta_store.gd")
var _provider
var _content_router
var _legacy_validator
var _world_store
var _validator
var _checkpoint
var _contracts
var _pending: Dictionary = {}
func _init(provider, world_store) -> void:
	_provider = provider
	_world_store = world_store
	_validator = Core.new(_provider)
	if _provider.get_script() == City: _content_router = Router.new(_provider)
	_checkpoint = Checkpoint.new(_world_store,Callable(Helper,"requirements"),Callable(self,"_restore_checkpoint"))
	_contracts = Contracts.new(Callable(self,"validate_checkpoint"))
func validate_checkpoint(snapshot: Dictionary) -> Dictionary:
	if _known_finite_checkpoint(snapshot) or _unknown_content_identity(snapshot): return _fail("content_mismatch")
	return _checkpoint.validate_checkpoint(snapshot)
func validate_checkpoint_scoped(snapshot: Dictionary, scope, context: Dictionary, envelope: Dictionary) -> Dictionary:
	if _known_finite_checkpoint(snapshot) or _unknown_content_identity(snapshot): return _fail("content_mismatch")
	return _checkpoint.validate_checkpoint(snapshot,scope,context,envelope)
func _unknown_content_identity(snapshot: Dictionary) -> bool:
	if _content_router == null: return false
	# A recognized unknown identity is a compatibility barrier even if its page
	# tree is damaged. Do not let corrupt pages turn it into backup adoption.
	if not Core.Contracts.new().validate_snapshot(snapshot).is_empty() or not Helper.validate_world(snapshot).get("ok",false): return false
	return snapshot.rules.content_fingerprint not in [City.DEV4_FINGERPRINT,_validator._chapter.get("content_fingerprint","")]
func _known_finite_checkpoint(snapshot: Dictionary) -> bool:
	# Recognize only a fully valid current finite run. Missing/malformed world
	# alone never authorizes replacement; city and invalid input keep their
	# original world validator. This barrier prevents older-backup adoption.
	if snapshot.has("world"): return false
	return Core.new().restore(snapshot).get("ok",false)
func new_run(chapter: Dictionary, seed: Variant, config: Dictionary) -> Dictionary:
	if chapter.get("world_mode") != "streamed_city": return _fail("content_mismatch")
	var core = _new_core()
	if core == null: return _fail("content_mismatch")
	return core.new_run(chapter,seed,config)
func prepare_commit_scoped(game_save: Dictionary, commands: Array, scope) -> Dictionary:
	return _prepare(game_save,commands,true,scope)
func prepare_commit(game_save: Dictionary, commands: Array = []) -> Dictionary:
	return _prepare(game_save,commands,true)
func prepare_load(game_save: Dictionary, commands: Array = []) -> Dictionary:
	return _prepare(game_save,commands,false)
func _prepare(game_save: Dictionary, commands: Array, committing: bool, scope = null) -> Dictionary:
	# Normalize through the exact GameSave and world-checkpoint contracts. A
	# caller must stage pages/accept the exact receipt before supplying clean B.
	var checked: Dictionary = _contracts.validate_and_normalize(game_save,scope,{"slot":"B"})
	if not checked.ok: return _fail(checked.error_code)
	var canonical: Dictionary = checked.game_save
	if not canonical.get("checkpoint") is Dictionary: return _fail("invalid_snapshot")
	if committing:
		if canonical.store_revision >= Contracts.MAX_COUNTER: return _fail("counter_exhausted")
		# Exactly GameSaveStore._commit_locked's one increment, never world counters.
		canonical.store_revision = int(canonical.store_revision)+1
	var pair := _prepared_pair(canonical.checkpoint,commands)
	if not pair.get("ok",false): return pair
	# Publish only private pending state. Failed preparation preserves prior B;
	# a successful explicit preparation may replace it, including after conflict.
	_pending = {"simulation":pair.simulation,"state":pair.state,"game_save":canonical,"committing":committing}
	return {"ok":true}
func confirm_candidate(game_save_store) -> Dictionary:
	return _confirm_candidate(game_save_store)
func confirm_candidate_scoped(game_save_store, scope) -> Dictionary:
	return _confirm_candidate(game_save_store,scope)
func _confirm_candidate(game_save_store, scope = null) -> Dictionary:
	if _pending.is_empty(): return _fail("no_prepared_candidate")
	# Read-only existing authority; load_game could initialize/migrate instead.
	var observed: Dictionary = game_save_store.read_game_scoped(scope) if scope != null else game_save_store.read_game()
	if not observed.get("ok",false): return observed
	var canonical: Dictionary = _contracts.normalize(observed.get("game_save"),scope,{"slot":"B"})
	if canonical.is_empty(): return _fail("invalid_snapshot")
	if not _same(canonical,_pending.game_save): return _fail("authority_mismatch")
	if _pending.committing:
		# A recovered previous authority is not confirmation of a new write.
		if observed.get("recovered",false): return _fail("authority_mismatch")
		var expected_hash := JSON.stringify(_pending.game_save,"",true,true).sha256_text()
		if observed.get("source_sha256","") != expected_hash: return _fail("authority_mismatch")
	# No environmental pause flags are mixed into saved bytes. The controller
	# reapplies its latest lifecycle generation only after assigning both values.
	var result := {"ok":true,"simulation":_pending.simulation,"state":_pending.state,"game_save":canonical,"source_sha256":observed.get("source_sha256",""),"recovered":observed.get("recovered",false)}
	_pending = {}
	return result
func refresh_live_coverage(current_core, current_state: Dictionary, commands: Array = []) -> Dictionary:
	# Public cold APIs and injected callbacks remain unchanged. This entry is
	# used only by the Controller's ordinary fixed-tick coverage continuation.
	if get_script() != load("res://game/app/prepared_city_runtime.gd") or _content_router == null or _content_router.get_script() != Router or _provider.get_script() != City or not _world_store is Disk or _world_store.get_script() != Disk or not current_core is Object or current_core.get_script() != Core or current_core._chapter_provider != _provider or not current_core._can_prepare_live_coverage(current_state):
		return refresh_coverage(current_state,commands)
	var needed := Helper.requirements(current_state,commands)
	if not needed.get("ok",false): return needed
	_world_store.begin_verified_read()
	var verified: Dictionary = _world_store.verify_root(current_state.world.delta_root)
	if not verified.get("ok",false): return verified
	var hydration: Dictionary = _world_store.hydrate(current_state.world.delta_root,needed.chunks)
	if not hydration.get("ok",false): return hydration
	var core = current_core._fork_live_configuration()
	if core == null: return refresh_coverage(current_state,commands)
	var prepared: Variant = core._prepare_live_world(current_state,hydration.deltas,commands,current_core._streamed)
	if not prepared is Dictionary: return _fail("world_not_ready")
	if not prepared.get("ok",false): return prepared
	return {"ok":true,"simulation":core,"state":prepared.state}
func refresh_coverage(current_state: Dictionary, commands: Array = []) -> Dictionary:
	# Derived-cache replacement only. The caller supplies its current state and
	# must swap the returned pair synchronously, without consuming a refused tick.
	# This is not an authority/commit API and must never increment a save revision.
	return _prepared_pair(current_state,commands)
func _prepared_pair(snapshot: Dictionary, commands: Array) -> Dictionary:
	var needed := Helper.requirements(snapshot,commands)
	if not needed.get("ok",false): return needed
	if _world_store is Disk: _world_store.begin_verified_read()
	var verified: Dictionary = _world_store.verify_root(snapshot.world.delta_root)
	if not verified.get("ok",false): return verified
	var hydration: Dictionary = _world_store.hydrate(snapshot.world.delta_root,needed.chunks)
	if not hydration.get("ok",false): return hydration
	var core = _new_core(snapshot)
	if core == null: return _fail("content_mismatch")
	var restored: Dictionary = core.restore(snapshot,hydration.deltas)
	if not restored.get("ok",false): return restored
	var state: Dictionary = restored.state
	var prepared: Dictionary = core.prepare_world(state,hydration.deltas,commands)
	if not prepared.get("ok",false): return prepared
	return {"ok":true,"simulation":core,"state":state}
func resolve_content(snapshot: Dictionary = {}) -> Dictionary:
	if _content_router == null: return _fail("content_mismatch")
	return _content_router.resolve(snapshot)
func validation_context(snapshot: Dictionary) -> Dictionary:
	if _content_router == null: return {"ok":true,"core":_validator,"provider":_provider}
	var route := resolve_content(snapshot)
	if not route.get("ok",false): return route
	var core = _validator
	if route.rules_version == "dev4":
		if _legacy_validator == null: _legacy_validator = Core.new(route.provider,null,route.immutable_inputs)
		core = _legacy_validator
	if not core._content_error.is_empty(): return _fail(core._content_error)
	if not core._same_json(route.chapter,core._chapter): return _fail("content_mismatch")
	route.core = core
	return route
func _restore_checkpoint(snapshot: Dictionary, hydration: Dictionary = {}) -> Dictionary:
	# Preserve Core's structural/schema precedence; route only recognized states.
	var errors: Array[String] = Core.Contracts.new().validate_snapshot(snapshot)
	if not errors.is_empty(): return {"ok":false,"error_code":"unsupported_schema" if "unsupported_schema" in errors else "invalid_snapshot","errors":errors}
	var selected := validation_context(snapshot)
	if not selected.get("ok",false): return selected
	return selected.core.restore(snapshot,hydration)
func _new_core(snapshot: Dictionary = {}):
	if _content_router == null: return Core.new(_provider)
	var route := resolve_content(snapshot)
	if not route.get("ok",false): return null
	return Core.new(route.provider,null,route.immutable_inputs)
func _same(left: Dictionary, right: Dictionary) -> bool:
	# Same full JSON semantic equality as the exact Store after normalization.
	return JSON.parse_string(JSON.stringify(left,"",true,true)) == JSON.parse_string(JSON.stringify(right,"",true,true))
func _fail(code: String) -> Dictionary:
	return {"ok":false,"error_code":code}
