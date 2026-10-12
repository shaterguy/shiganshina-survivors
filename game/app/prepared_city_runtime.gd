extends RefCounted
# NEW 2026-10-10 optional city boundary. No default activation, writes or live Core.
# Retain this object while its validator/new_run Callables are bound by consumers.
const Core = preload("res://game/core/run_simulation.gd")
const Helper = preload("res://game/core/streamed_run_world.gd")
const Checkpoint = preload("res://game/app/world_checkpoint_adapter.gd")
const Contracts = preload("res://game/contracts/game_save_contracts.gd")
const Disk = preload("res://game/persistence/world_delta_store.gd")
var _provider
var _world_store
var _validator
var _checkpoint
var _contracts
var _pending: Dictionary = {}
func _init(provider, world_store) -> void:
	_provider = provider
	_world_store = world_store
	_validator = Core.new(_provider)
	_checkpoint = Checkpoint.new(_world_store,Callable(Helper,"requirements"),Callable(_validator,"restore"))
	_contracts = Contracts.new(Callable(self,"validate_checkpoint"))
func validate_checkpoint(snapshot: Dictionary) -> Dictionary:
	if _known_finite_checkpoint(snapshot): return _fail("content_mismatch")
	return _checkpoint.validate_checkpoint(snapshot)
func validate_checkpoint_scoped(snapshot: Dictionary, scope, context: Dictionary, envelope: Dictionary) -> Dictionary:
	if _known_finite_checkpoint(snapshot): return _fail("content_mismatch")
	return _checkpoint.validate_checkpoint(snapshot,scope,context,envelope)
func _known_finite_checkpoint(snapshot: Dictionary) -> bool:
	# Recognize only a fully valid current finite run. Missing/malformed world
	# alone never authorizes replacement; city and invalid input keep their
	# original world validator. This barrier prevents older-backup adoption.
	if snapshot.has("world"): return false
	return Core.new().restore(snapshot).get("ok",false)
func new_run(chapter: Dictionary, seed: Variant, config: Dictionary) -> Dictionary:
	if chapter.get("world_mode") != "streamed_city": return _fail("content_mismatch")
	return _new_core().new_run(chapter,seed,config)
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
	var core = _new_core()
	var restored: Dictionary = core.restore(snapshot,hydration.deltas)
	if not restored.get("ok",false): return restored
	var state: Dictionary = restored.state
	var prepared: Dictionary = core.prepare_world(state,hydration.deltas,commands)
	if not prepared.get("ok",false): return prepared
	return {"ok":true,"simulation":core,"state":state}
func _new_core():
	return Core.new(_provider)
func _same(left: Dictionary, right: Dictionary) -> bool:
	# Same full JSON semantic equality as the exact Store after normalization.
	return JSON.parse_string(JSON.stringify(left,"",true,true)) == JSON.parse_string(JSON.stringify(right,"",true,true))
func _fail(code: String) -> Dictionary:
	return {"ok":false,"error_code":code}
