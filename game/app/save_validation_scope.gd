extends RefCounted
# One transaction-local validation scope, with disjoint predecessor/candidate proofs.
const City = preload("res://game/director/streamed_chapter_provider.gd")
const Disk = preload("res://game/persistence/world_delta_store.gd")
const Runtime = preload("res://game/app/prepared_city_runtime.gd")
const Core = preload("res://game/core/run_simulation.gd")
class CapturedProvider:
	extends RefCounted
	var _chapter: Dictionary
	var _rules_version: String
	func _init(chapter: Dictionary, version: String = "dev5") -> void:
		_chapter = chapter.duplicate(true)
		_rules_version = version
	func rules_version() -> String: return _rules_version
	func load_chapter(_id: String) -> Dictionary:
		return {"ok":true,"chapter":_chapter.duplicate(true)}
var final_fence_enabled := true
var _directory: String
var _revision: int
var _runtime
var _provider
var _provider_id := 0
var _validator
var _world_store
var _closed := false
var _slots := {"A":{},"B":{}}
var _capture_key := ""
var _captured_core
var _stats := {"restore_calls":0,"hits":0,"captures":0,"capture_usec":0,"capture_bytes":0,"key_usec":0,"misses_A":0,"misses_B":0,"peak_entries":0}
func _init(directory: String, revision: int) -> void:
	_directory = directory
	_revision = revision
static func create(runtime, directory: String, revision: int):
	if runtime.get_script() != Runtime or runtime._provider.get_script() != City or runtime._world_store.get_script() != Disk: return null
	var scope = load("res://game/app/save_validation_scope.gd").new(directory,revision)
	scope._runtime = runtime
	scope._provider = runtime._provider
	scope._provider_id = runtime._provider.get_instance_id()
	scope._validator = runtime._validator
	scope._world_store = runtime._world_store
	return scope
func accepts_validator(validator: Callable) -> bool:
	return not _closed and _runtime != null and validator.get_object() == _runtime and validator.get_method() == "validate_checkpoint" and _runtime._provider == _provider and _provider.get_instance_id() == _provider_id and _runtime._validator == _validator and _runtime._world_store == _world_store and _runtime._checkpoint._core_restore.get_object() == _runtime and _runtime._checkpoint._core_restore.get_method() == "_restore_checkpoint" and _runtime._checkpoint._store == _world_store
func exact_key(value: Variant) -> String:
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(var_to_bytes(value))
	return hash.finish().hex_encode()
func remember(slot: String, key: String, value: Dictionary) -> void:
	if _closed or not _slots.has(slot): return
	# A bounded cache within this scope; eviction never avoids a validation.
	if _slots[slot].size() >= 8: _slots[slot].clear()
	_slots[slot][key] = value.duplicate(true)
	_stats.peak_entries = maxi(_stats.peak_entries,_slots.A.size()+_slots.B.size())
func recall(slot: String, key: String) -> Dictionary:
	if _closed or not _slots.has(slot): return {}
	return _slots[slot].get(key,{}).duplicate(true)
func restore(snapshot: Dictionary, hydration: Dictionary, manifest: String, context: Dictionary, envelope: Dictionary) -> Dictionary:
	if _closed or context.get("directory",_directory) != _directory:
		return _runtime._restore_checkpoint(snapshot.duplicate(true),hydration.duplicate(true))
	# Match the original Core error precedence before any provider capture.
	var errors: Array[String] = Core.Contracts.new().validate_snapshot(snapshot)
	if not errors.is_empty(): return {"ok":false,"error_code":"unsupported_schema" if "unsupported_schema" in errors else "invalid_snapshot","errors":errors}
	if snapshot.content_revision != Core.CONTENT_REVISION or snapshot.chapter_id != "chapter_01_shiganshina" or not Core.Characters.new().runtime_available(snapshot.character_id): return {"ok":false,"error_code":"content_mismatch"}
	var capture_start := Time.get_ticks_usec()
	var selected: Dictionary = _runtime.validation_context(snapshot)
	_stats.captures += 1
	_stats.capture_usec += Time.get_ticks_usec()-capture_start
	if not selected.get("ok",false): return selected
	var capture: Dictionary = selected.capture
	for bytes in capture.sources.values(): _stats.capture_bytes += bytes.size()
	var selected_key := exact_key([selected.rules_version,selected.provider.get_instance_id(),selected.core.get_instance_id(),capture.sha256])
	if selected_key != _capture_key:
		_captured_core = Core.new(CapturedProvider.new(selected.chapter,selected.rules_version),null,selected.immutable_inputs)
		_capture_key = selected_key
	var slot: String = context.get("slot","B")
	if slot == "read": slot = "B" if int(envelope.get("store_revision",-1)) == _revision+1 else "A"
	var envelope_identity := envelope.duplicate(true)
	if slot == "B": envelope_identity.store_revision = _revision
	# Both slots bind actual observed file path/bytes when present. In-memory B
	# also binds the whole target envelope; no file-derived proof crosses a path.
	var authority_identity: Variant = [context.get("path",""),context.get("sha256",""),JSON.stringify(envelope_identity,"",true,true)]
	var key_start := Time.get_ticks_usec()
	var key := exact_key([_directory,_revision,_provider_id,_validator.get_instance_id(),_world_store.get_instance_id(),_capture_key,manifest,authority_identity,snapshot,hydration])
	_stats.key_usec += Time.get_ticks_usec()-key_start
	var hit := recall(slot,key)
	if not hit.is_empty():
		_stats.hits += 1
		return hit
	_stats.restore_calls += 1
	_stats["misses_"+slot] += 1
	var restored: Dictionary = _captured_core.restore(snapshot.duplicate(true),hydration.duplicate(true))
	if restored.get("ok",false): remember(slot,key,restored)
	return restored.duplicate(true)
func diagnostics() -> Dictionary:
	return _stats.duplicate(true)
func close() -> void:
	_closed = true
	_slots = {"A":{},"B":{}}
	_captured_core = null
	_capture_key = ""
