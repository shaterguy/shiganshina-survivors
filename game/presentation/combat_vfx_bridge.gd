class_name CombatVfxBridge
extends RefCounted
const Director = preload("res://game/presentation/combat_vfx_director.gd")
const Catalog = preload("res://game/presentation/combat_vfx_catalog.gd")
const Renderer = preload("res://game/presentation/combat_vfx_renderer.gd")
const Address = preload("res://game/world/world_address.gd")
# Presentation owns these objects. No Core reference, gameplay clock, reward,
# save DTO or approval override crosses this successful-tick boundary.
var _director = Director.new()
var _renderer = Renderer.new()
var _metadata: Dictionary = {}
var _raster_validation: Dictionary = {}
var _identity: Array = []
var _tick := -1
var _event_seq := 0
var _world_key: Array = []
var _origin_chunk: Array = []
var _origin_revision := 0
var _rebase_count := 0
var _diagnostics: Array[String] = []
func _init(asset_metadata: Dictionary = {}) -> void:
	_renderer = Renderer.new(_raster_problem)
	set_asset_metadata(asset_metadata)
func set_asset_metadata(asset_metadata: Dictionary) -> void:
	_metadata = asset_metadata.get("assets",asset_metadata).duplicate(true)
	_raster_validation.clear()
func reset() -> void:
	_director.reset("")
	_identity.clear()
	_tick = -1
	_event_seq = 0
	_world_key.clear()
	_origin_chunk.clear()
	_origin_revision = 0
	_rebase_count = 0
	_diagnostics.clear()
func validate_batch(events: Array[Dictionary], current_snapshot: Dictionary) -> bool:
	if not _snapshot_valid(current_snapshot): return false
	var run := _run_id(current_snapshot)
	var tick := int(current_snapshot.active_tick)
	var seq := int(current_snapshot.get("event_seq",0))
	# The controller must supply the snapshot from this exact successful tick.
	# Reject the whole batch without advancing the watermark, permitting a valid
	# retry. No geometry from a previous rendered frame is used to fill it in.
	for event in events:
		var id := str(event.get("event_id",""))
		if int(event.get("tick",-1)) != tick or not id.begins_with(run+":") or not id.get_slice(":",id.get_slice_count(":")-1).is_valid_int() or int(id.get_slice(":",id.get_slice_count(":")-1)) > seq:
			_diagnostic("event_snapshot_mismatch")
			return false
	return true
func consume(events: Array[Dictionary], current_snapshot: Dictionary) -> bool:
	if not validate_batch(events,current_snapshot): return false
	var tick := int(current_snapshot.active_tick)
	var seq := int(current_snapshot.get("event_seq",0))
	_sync(current_snapshot,true,events)
	_director.consume(events,current_snapshot)
	_tick = tick
	_event_seq = seq
	return true
func present(snapshot: Dictionary, reduce_effects := false, visible_rect := Rect2(), visual_positions: Dictionary = {}) -> Array[Dictionary]:
	if snapshot.is_empty(): reset(); return []
	if not _snapshot_valid(snapshot): return []
	_sync(snapshot,false,[])
	var actors: Dictionary = {}
	if snapshot.get("player") is Dictionary and snapshot.player.has("position"):
		actors.player = _vec(snapshot.player.position)
	for entity in snapshot.get("entities",[]):
		actors["entity:"+str(entity.get("id",""))] = _vec(entity.get("position",[0,0]))
	var context := {"tick":int(snapshot.active_tick),"reduce_effects":reduce_effects,"asset_metadata":_metadata,"actor_positions":actors,"origin_revision":_origin_revision}
	# Spatial overrides never enter Director, change its clocks, or replace Core
	# contact geometry. Missing identities retain the current accepted position.
	for id in actors:
		if visual_positions.get("actor_positions",{}).has(id): actors[id] = visual_positions.actor_positions[id]
	context.projectile_positions = visual_positions.get("projectile_positions",{})
	context.target_positions = visual_positions.get("target_positions",{})
	if visible_rect.has_area(): context.visible_rect = visible_rect
	var output: Array[Dictionary] = []
	for command in _renderer.commands(_director.present(snapshot),context):
		if command.has("diagnostic"):
			output.append(command)
			continue
		var problem := _raster_problem(str(command.asset_id))
		if not problem.is_empty():
			output.append({"diagnostic":problem,"asset_id":command.asset_id,"effect_id":command.effect_id,"stable_id":command.stable_id+":raster","render_pass":command.render_pass,"depth_y":command.depth_y})
		else:
			output.append(command)
	_tick = int(snapshot.active_tick)
	_event_seq = int(snapshot.get("event_seq",0))
	return output
func debug_stats() -> Dictionary:
	var output: Dictionary = _director.debug_stats()
	output.bridge_tick = _tick
	output.origin_revision = _origin_revision
	output.rebase_count = _rebase_count
	output.diagnostics = _diagnostics.duplicate()+output.diagnostics
	return output
func _snapshot_valid(snapshot: Dictionary) -> bool:
	var tick = snapshot.get("active_tick",null)
	var seq = snapshot.get("event_seq",0)
	if _run_id(snapshot).is_empty() or not _counter(tick) or not _counter(seq):
		_diagnostic("invalid_snapshot")
		return false
	return true
func _sync(snapshot: Dictionary, consuming: bool, events: Array) -> void:
	var run := _run_id(snapshot)
	var next_identity: Array = [run,snapshot.get("seed",0),snapshot.get("chapter_id",""),snapshot.get("content_revision","")]
	var tick := int(snapshot.active_tick)
	var seq := int(snapshot.get("event_seq",0))
	var world: Dictionary = snapshot.get("world",{})
	var key: Array = [world.get("mode","finite"),world.get("stage","")]
	var revision := int(world.get("origin_revision",snapshot.get("origin_revision",0)))
	var chunk: Array = world.get("origin_chunk",[])
	var restoring: bool = not _identity.is_empty() and next_identity == _identity and (tick < _tick or seq < _event_seq or revision < _origin_revision)
	var changed: bool = next_identity != _identity or key != _world_key
	if changed or restoring:
		var floor_seq := seq
		if consuming and not restoring and not events.is_empty():
			floor_seq = seq
			for event in events:
				var id := str(event.get("event_id",""))
				floor_seq = mini(floor_seq,int(id.get_slice(":",id.get_slice_count(":")-1))-1)
		_director.reset(run,maxi(0,floor_seq))
		_identity = next_identity
		_world_key = key
		_origin_chunk = chunk.duplicate()
		_origin_revision = revision
	elif revision != _origin_revision or chunk != _origin_chunk:
		var shift := Address.relative(_origin_chunk,Vector2.ZERO,chunk) if _origin_chunk.size() == 2 and chunk.size() == 2 else {"ok":false}
		if revision > _origin_revision and shift.ok:
			# relative() supplies the additive translation; Director subtracts its
			# offset. This happens before current-origin events are ingested.
			_director.rebase(-shift.local,revision)
			_rebase_count += 1
		else:
			_director.reset(run,_event_seq)
			_diagnostic("origin_rebase_unavailable")
		_origin_chunk = chunk.duplicate()
		_origin_revision = revision
func _raster_problem(asset_id: String) -> String:
	if _raster_validation.has(asset_id): return _raster_validation[asset_id]
	var problem := Catalog.raster_problem(_metadata[asset_id])
	_raster_validation[asset_id] = problem
	return problem
func _run_id(snapshot: Dictionary) -> String:
	return str(snapshot.get("run_id",snapshot.get("seed","")))
func _counter(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value >= 0 and value == floor(float(value))
func _diagnostic(message: String) -> void:
	if not message in _diagnostics: _diagnostics.append(message)
func _vec(value: Variant) -> Vector2:
	if value is Vector2: return value
	if value is Array and value.size() == 2: return Vector2(float(value[0]),float(value[1]))
	return Vector2.ZERO
