extends RefCounted
# One transient final actor/current pattern. No saved state, art, audio or damage.
const Address = preload("res://game/world/world_address.gd")
var _identity: Array = []
var _scene: Array = []
var _chunk: Array = []
var _revision := 0
var _tick := -1
var _seq := 0
var _actor: Dictionary = {}
var _contact: Dictionary = {}
var _distance := 0.0
var _last_travel := 0.0
# Whole straight-charge travel is separate from the observed-window contract.
var _charge_distance := 0.0
var _charge_distance_known := false
var _charge_start := -1
var _mode := ""
var _contacts := 0
var _rebases := 0
func reset() -> void:
	_identity.clear(); _scene.clear(); _chunk.clear()
	_revision = 0; _tick = -1; _seq = 0
	_clear_actor(); _contacts = 0; _rebases = 0
func _clear_actor() -> void:
	_actor.clear(); _contact.clear(); _distance = 0.0; _last_travel = 0.0; _charge_start = -1; _mode = ""
	_charge_distance = 0.0; _charge_distance_known = false
func validate_batch(events: Array[Dictionary], snapshot: Dictionary) -> bool:
	# Validate fresh contact input before any rebase, travel or watermark writes.
	if not _snapshot_valid(snapshot): return false
	var identity: Array = [snapshot.get("run_id",snapshot.get("seed","")),snapshot.get("seed",0),snapshot.get("chapter_id",""),snapshot.get("content_revision","")]
	var world: Dictionary = snapshot.get("world",{})
	var scene: Array = [world.get("mode","finite"),world.get("stage",""),world.get("scene_id","")]
	var revision := int(world.get("origin_revision",snapshot.get("origin_revision",0)))
	var same_run := identity == _identity
	# Adoption suppresses impact, but never excuses a fresh malformed payload.
	# A lower snapshot sequence cannot contain an ID above the previous floor.
	var same_epoch := same_run and scene == _scene and int(snapshot.active_tick) >= _tick and int(snapshot.event_seq) >= _seq and revision >= _revision
	var actor: Dictionary = {}
	for entity in snapshot.get("entities",[]):
		if entity.get("enemy_id") == "armored_titan": actor = entity; break
	for event in events:
		if event.get("type") != "final_charge_contact" or (same_run and _sequence(event) <= _seq): continue
		var charge_start := _charge_start if same_epoch and not _actor.is_empty() and _actor.id == actor.get("id") and _actor.pattern_index == actor.get("pattern_index") else -1
		if actor.is_empty() or not _valid_contact(event,snapshot,actor,charge_start): return false
	return true
func consume(events: Array[Dictionary], snapshot: Dictionary) -> void:
	if validate_batch(events,snapshot): _observe(snapshot,events,true)
func present(snapshot: Dictionary) -> void:
	if snapshot.is_empty(): reset(); return
	_observe(snapshot,[],false)
func _observe(snapshot: Dictionary, events: Array[Dictionary], live: bool) -> void:
	if not _snapshot_valid(snapshot): return
	var tick := int(snapshot.active_tick)
	var seq := int(snapshot.event_seq)
	var identity: Array = [snapshot.get("run_id",snapshot.get("seed","")),snapshot.get("seed",0),snapshot.get("chapter_id",""),snapshot.get("content_revision","")]
	var world: Dictionary = snapshot.get("world",{})
	var scene: Array = [world.get("mode","finite"),world.get("stage",""),world.get("scene_id","")]
	var revision := int(world.get("origin_revision",snapshot.get("origin_revision",0)))
	var chunk: Array = world.get("origin_chunk",[])
	var first := _identity.is_empty()
	var new_run := not first and identity != _identity
	var changed := not first and identity == _identity and scene != _scene
	var restored := not first and not new_run and (tick < _tick or seq < _seq or revision < _revision)
	# A snapshot-only adoption cannot prove live travel or historical impact.
	var adoption := not live and (first or new_run or changed or restored or tick > _tick or seq > _seq)
	var suppress := restored or changed or adoption
	if first or new_run or suppress:
		_clear_actor()
		_seq = seq
		if new_run: _contacts = 0; _rebases = 0
		if (first or new_run) and live:
			for event in events: _seq = mini(_seq,maxi(0,_sequence(event)-1))
	elif revision != _revision or chunk != _chunk:
		var shift := Address.relative(_chunk,Vector2.ZERO,chunk) if _chunk.size() == 2 and chunk.size() == 2 else {"ok":false}
		if revision > _revision and shift.ok:
			if not _actor.is_empty(): _actor.position = _translated(_actor.position,shift.local)
			for key in ["root_position","point","center"]:
				if _contact.has(key): _contact[key] = _translated(_contact[key],shift.local)
			if not _contact.is_empty(): _contact.origin_revision = revision
			_rebases += 1
		else:
			_clear_actor(); suppress = true
	_identity = identity; _scene = scene; _chunk = chunk.duplicate(); _revision = revision
	var current: Dictionary = {}
	for entity in snapshot.get("entities",[]):
		if entity.get("enemy_id") == "armored_titan": current = entity; break
	if current.is_empty() or not snapshot.get("phase","") in ["survival","evacuation"]:
		_clear_actor(); _tick = tick; _seq = seq; return
	var same: bool = not _actor.is_empty() and current.id == _actor.id and current.get("spawned_tick") == _actor.get("spawned_tick") and current.pattern_index == _actor.pattern_index
	if not same: _clear_actor()
	# Keep the last accepted charge delta through stationary brake/recovery.
	if live and tick > _tick:
		if same and tick == _tick+1 and not suppress and snapshot.get("pause_reasons",[]).is_empty():
			# Include the final accepted partial step even though its phase is now brake.
			if _actor.action_state == "attack" and current.action_state in ["attack","brake"] or (_actor.action_state == "windup" and current.action_state == "attack"):
				_last_travel = _vec(_actor.position).distance_to(_vec(current.position))
				_distance += _last_travel
	# A restored attack retains its original anchor. Snapshot arrays are double;
	# Vector2 subtraction would round that prefix and each accepted delta again.
	var same_attack: bool = same and _actor.action_state == "attack" and current.action_state == "attack" and _actor.action_started_tick == current.action_started_tick
	var charge_step: bool = live and same and tick == _tick+1 and not suppress and snapshot.get("pause_reasons",[]).is_empty()
	if current.action_state == "attack":
		if charge_step and same_attack and _charge_distance_known:
			_charge_distance += _array_distance(_actor.position,current.position)
		elif not (same_attack and tick == _tick and not suppress and _charge_distance_known):
			_charge_distance_known = current.has("locked_origin") and current.has("locked_direction") and current.pattern_index >= 1 and current.action_ends_tick > tick and is_equal_approx(_vec(current.locked_direction).length(),1.0)
			_charge_distance = _array_distance(current.position,current.locked_origin) if _charge_distance_known else 0.0
	elif current.action_state in ["brake","recover"]:
		if charge_step and _actor.action_state == "attack" and current.action_state == "brake" and _charge_distance_known:
			# Core overwrites locked_origin at stop; include the last accepted partial
			# delta from the prior translated root before replacing that observation.
			_charge_distance += _array_distance(_actor.position,current.position)
		elif not (same and not suppress and _actor.action_state in ["brake","recover"] and (tick == _tick or charge_step)):
			_charge_distance = 0.0; _charge_distance_known = false
	if current.action_state == "attack": _charge_start = int(current.action_started_tick)
	if current.action_state in ["move","windup"]:
		_contact.clear(); _charge_start = -1; _distance = 0.0; _last_travel = 0.0
		_charge_distance = 0.0; _charge_distance_known = false
	if not suppress and live:
		for event in events:
			if _sequence(event) <= _seq or not _contact.is_empty(): continue
			if _valid_contact(event,snapshot,current,_charge_start):
				_contact = event.payload.duplicate(true)
				_contact.tick = int(event.tick)
				_contact.event_id = str(event.event_id)
				_charge_start = int(_contact.attack_started_tick)
				_contacts += 1
	_mode = str(current.action_state)
	if current.action_state in ["brake","recover"]:
		if not _contact.is_empty(): _mode = "impact"
		elif suppress or first or not same: _mode = "restored_grounded"
		elif not _actor.is_empty() and _actor.get("restored",false): _mode = "restored_grounded"
		else: _mode = "free_brake"
	_actor = {"id":current.id,"spawned_tick":current.get("spawned_tick"),"pattern_index":current.pattern_index,"position":current.position.duplicate(),"action_state":current.action_state,"action_started_tick":current.action_started_tick,"action_ends_tick":current.action_ends_tick,"restored":_mode == "restored_grounded"}
	_tick = tick; _seq = seq
func _valid_contact(event: Dictionary, snapshot: Dictionary, actor: Dictionary, charge_start: int = -1) -> bool:
	if event.get("type") != "final_charge_contact" or not event.get("payload") is Dictionary: return false
	var id := str(event.get("event_id",""))
	if not id.begins_with(str(snapshot.get("run_id",snapshot.get("seed","")))+":") or event.get("tick") != snapshot.active_tick or _sequence(event) > int(snapshot.event_seq): return false
	var p: Dictionary = event.payload
	if p.get("source_id") != str(actor.id) or p.get("shape") != "shoulder_circle" or not p.get("shape_id") is String or p.shape_id.is_empty() or not p.get("prop_id") is String: return false
	for field in ["pattern_index","attack_started_tick","origin_revision"]:
		if not _counter(p.get(field)): return false
	if int(p.pattern_index) != int(actor.pattern_index) or int(p.origin_revision) != int(snapshot.get("world",{}).get("origin_revision",snapshot.get("origin_revision",0))): return false
	if actor.action_state != "brake" or int(actor.action_started_tick) != int(event.tick): return false
	if int(p.attack_started_tick) > int(event.tick) or int(event.tick)-int(p.attack_started_tick) >= int(snapshot.get("rules",{}).get("enemy_catalog",{}).get("armored_titan",{}).get("action_profile",{}).get("active_ticks",60)): return false
	if charge_start >= 0 and int(p.attack_started_tick) != charge_start: return false
	for field in ["root_position","locked_direction","point","center","normal"]:
		if not _pair(p.get(field)): return false
	if p.root_position != actor.position or p.locked_direction != actor.get("locked_direction"): return false
	if not is_equal_approx(_vec(p.normal).length(),1.0) or not is_equal_approx(_vec(p.locked_direction).length(),1.0): return false
	if not _number(p.get("fraction")) or p.fraction < 0.0 or p.fraction > 1.0: return false
	return true
func debug_observation() -> Dictionary:
	if _actor.is_empty(): return {}
	return {"actor_id":str(_actor.id),"pattern_index":int(_actor.pattern_index),"tick":_tick,"event_seq":_seq,"origin_revision":_revision,"phase":str(_actor.action_state),"phase_started_tick":int(_actor.action_started_tick),"phase_ends_tick":int(_actor.action_ends_tick),"phase_age":_tick-int(_actor.action_started_tick),"attack_started_tick":_charge_start,"root_position":_actor.position.duplicate(),"distance":_distance,"last_travel":_last_travel,"charge_distance":_charge_distance,"charge_distance_known":_charge_distance_known,"mode":_mode,"contact":_contact.duplicate(true),"contact_count":_contacts,"rebase_count":_rebases}
func _sequence(event: Dictionary) -> int:
	var id := str(event.get("event_id","")); var value := id.get_slice(":",id.get_slice_count(":")-1)
	return int(value) if value.is_valid_int() else -1
func _number(value: Variant) -> bool: return (value is int or value is float) and is_finite(float(value))
func _counter(value: Variant) -> bool: return _number(value) and value >= 0 and value <= 2147483647 and value == floor(float(value))
func _pair(value: Variant) -> bool: return value is Array and value.size() == 2 and _number(value[0]) and _number(value[1])
func _vec(value: Array) -> Vector2: return Vector2(value[0],value[1])
func _translated(value: Array, shift: Vector2) -> Array: return [value[0]+shift.x,value[1]+shift.y]

func _snapshot_valid(snapshot: Dictionary) -> bool:
	# Bounded tracker input validation, not a second Core/save-schema validator.
	for field in ["active_tick","event_seq"]:
		if not _counter(snapshot.get(field)): return false
	if not snapshot.get("world",{}) is Dictionary or not snapshot.get("entities",[]) is Array or not snapshot.get("pause_reasons",[]) is Array: return false
	var world: Dictionary = snapshot.get("world",{})
	if not _counter(world.get("origin_revision",snapshot.get("origin_revision",0))): return false
	var chunk = world.get("origin_chunk",[])
	if not chunk is Array or (not chunk.is_empty() and not Address.parse(chunk).ok): return false
	for actor in snapshot.get("entities",[]):
		if not actor is Dictionary: return false
		if actor.get("enemy_id") != "armored_titan": continue
		for field in ["id","pattern_index","action_started_tick","action_ends_tick"]:
			if not _counter(actor.get(field)): return false
		if actor.has("spawned_tick") and not _counter(actor.spawned_tick): return false
		if actor.action_started_tick > snapshot.active_tick or actor.action_ends_tick < actor.action_started_tick: return false
		if not actor.get("action_state") in ["move","windup","attack","brake","recover"]: return false
		if not _pair(actor.get("position")) or not _vec(actor.position).is_finite(): return false
		# Absent optional anchor evidence leaves whole distance unknown. Present
		# malformed arrays are rejected before any existing observation writes.
		for field in ["locked_origin","locked_direction"]:
			if actor.has(field) and (not _pair(actor[field]) or not _vec(actor[field]).is_finite()): return false
	return true
func _array_distance(a: Array, b: Array) -> float:
	var dx := float(a[0])-float(b[0])
	var dy := float(a[1])-float(b[1])
	return sqrt(dx*dx+dy*dy)
