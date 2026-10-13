class_name CombatVfxDirector
extends RefCounted
const Catalog = preload("res://game/presentation/combat_vfx_catalog.gd")
const MAX_CORE_RESERVATIONS := 64
const MAX_CORE_PROJECTILES := 256
const MAX_FIRE_FIELDS := 2
var _catalog: RefCounted
var _effects: Array[Dictionary] = []
var _run_id := ""
var _event_seq := 0
var _tick := -1
var _origin_revision := 0
var _origin_initialized := false
var _effect_capacity := 96
var _trail_capacity := 32
var _explosion_capacity := 8
# Critical reserve protects the core's bounded scheduled attacks and projectile
# contacts. 96 is an ordinary-pool starting budget, not a correctness hard cap.
var _critical_reserve := 384
var _diagnostics: Array[String] = []
func _init(catalog = null, options: Dictionary = {}) -> void:
	_catalog = catalog if catalog != null else Catalog.new()
	_effect_capacity = maxi(1,int(options.get("effect_capacity",96)))
	_trail_capacity = maxi(0,int(options.get("trail_capacity",32)))
	_explosion_capacity = maxi(0,int(options.get("explosion_capacity",8)))
	_critical_reserve = maxi(0,int(options.get("critical_reserve",384)))
func reset(run_id: String, event_seq: int = 0) -> void:
	_run_id = run_id
	_event_seq = maxi(0,event_seq)
	_effects.clear()
	_diagnostics.clear()
	_tick = -1
	_origin_revision = 0
	_origin_initialized = false
func capacity_valid(core_reservation_limit: int = MAX_CORE_RESERVATIONS) -> bool:
	return _effect_capacity+_critical_reserve >= core_reservation_limit*2+MAX_CORE_PROJECTILES+8
func consume(events: Array[Dictionary], snapshot: Dictionary) -> void:
	_sync_run(snapshot,false)
	_prune(int(snapshot.get("active_tick",0)),snapshot)
	var ordered := events.duplicate()
	ordered.sort_custom(func(a,b): return _sequence(a) < _sequence(b))
	# A targeted triple is hit feedback, not a player-centered range disk.
	# Resolve only this successful batch's positive damage receipt, including kills.
	var reentry_contacts: Dictionary = {}
	for event in ordered:
		var hit: Dictionary = event.get("payload",{})
		if event.get("type") == "damage" and hit.get("source_id") == "reentry_combo" and float(hit.get("amount",0.0)) > 0.0 and hit.has("position") and _sequence(event) > _event_seq and str(event.get("event_id","")).begins_with(_run_id+":"):
			reentry_contacts[str(hit.get("attack_id",""))] = hit
	for event in ordered:
		var seq := _sequence(event)
		if seq <= _event_seq or not str(event.get("event_id","")).begins_with(_run_id+":"): continue
		_event_seq = seq
		var payload: Dictionary = event.get("payload",{})
		var tick := int(event.get("tick",snapshot.get("active_tick",0)))
		match str(event.get("type","")):
			"player_attack": _attack(payload,tick,snapshot,reentry_contacts.get(str(payload.get("attack_id","")),{}))
			"projectile_impact": _projectile_impact(payload,tick,snapshot)
			"damage": _damage(payload,tick)
	_enforce_capacity(int(snapshot.get("active_tick",0)))
func present(snapshot: Dictionary) -> Array[Dictionary]:
	_sync_run(snapshot,true)
	var tick := int(snapshot.get("active_tick",0))
	_prune(tick,snapshot)
	_reconstruct_pending(snapshot)
	_reconstruct_fire_fields(snapshot)
	_reconstruct_projectiles(snapshot)
	var output: Array[Dictionary] = []
	for stored in _effects:
		if tick < int(stored.start_tick) or tick >= int(stored.end_tick): continue
		var effect: Dictionary = stored.duplicate(true)
		if effect.get("projectile_binding","") == "core":
			var projectile := _projectile(snapshot,effect.get("projectile_id",-1))
			if projectile.is_empty(): continue
			effect.origin = _vec(projectile.position)
			effect.geometry.origin = _array(effect.origin)
			if projectile.has("velocity") and not _vec(projectile.velocity).is_zero_approx(): effect.direction = _vec(projectile.velocity).normalized()
		elif effect.get("projectile_binding","") == "crossfire":
			var duration := maxi(1,int(effect.end_tick)-int(effect.start_tick))
			var progress := clampf(float(tick-int(effect.start_tick))/duration,0.0,1.0)
			effect.origin = _vec(effect.flight_start).lerp(_vec(effect.flight_target),progress)
			effect.geometry.origin = _array(effect.origin)
			effect.direction = _vec(effect.flight_start).direction_to(_vec(effect.flight_target))
		var target_id = effect.geometry.get("target_id",null)
		if target_id != null and effect.get("base_item_id","") != "chain_lightning" and not effect.has("contact_position"):
			var target := _target(snapshot,target_id)
			# Only the core's explicit live target address supplies an actual hook.
			if not target.is_empty(): effect.geometry.wire_anchor = target.position.duplicate()
		effect.age_ticks = tick-int(effect.start_tick)
		output.append(effect)
	_tick = tick
	return output
func rebase(offset: Vector2, origin_revision: int) -> void:
	if origin_revision <= _origin_revision: return
	for effect in _effects:
		if effect.coordinate_space == "world":
			effect.origin = _vec(effect.origin)-offset
			if effect.has("contact_position"): effect.contact_position = _vec(effect.contact_position)-offset
			for key in ["origin","position","wire_anchor","anchor"]:
				if effect.geometry.has(key): effect.geometry[key] = _array(_vec(effect.geometry[key])-offset)
			for key in ["flight_start","flight_target"]:
				if effect.has(key): effect[key] = _array(_vec(effect[key])-offset)
		effect.origin_revision = origin_revision
	_origin_revision = origin_revision
	_origin_initialized = true
func debug_stats() -> Dictionary:
	return {"run_id":_run_id,"event_seq":_event_seq,"dedup_entries":1,"effect_count":_effects.size(),"ordinary_capacity":_effect_capacity,"critical_reserve":_critical_reserve,"hard_capacity":_effect_capacity+_critical_reserve,"capacity_valid":capacity_valid(),"diagnostics":_diagnostics.duplicate()}
func _sync_run(snapshot: Dictionary, restoring: bool) -> void:
	var run := str(snapshot.get("run_id",snapshot.get("seed","")))
	var tick := int(snapshot.get("active_tick",0))
	if _run_id != run or (_tick >= 0 and tick < _tick):
		reset(run,int(snapshot.get("event_seq",0)) if restoring or _tick >= 0 else 0)
	if not _origin_initialized:
		# The first post-reset snapshot already contains restored local positions.
		# Initialize identity only; rebase() owns later coordinate subtraction.
		var world: Dictionary = snapshot.get("world",{})
		_origin_revision = int(world.get("origin_revision",snapshot.get("origin_revision",0)))
		_origin_initialized = true
func _attack(payload: Dictionary, tick: int, snapshot: Dictionary, contact: Dictionary = {}) -> void:
	var phase := str(payload.get("phase",""))
	var base := str(payload.get("base_item_id",""))
	var evo := str(payload.get("evolution_id",""))
	var geometry: Dictionary = payload.get("geometry",{}).duplicate(true)
	if phase == "scheduled":
		# Wing stages have no authored windup. Do not invent a visible pre-hit slash.
		if evo != "evo_crossfire": return
		_schedule_crossfire(payload,snapshot)
		return
	if phase != "executed": return
	if base == "reentry_combo" and evo.is_empty() and (contact.is_empty() or str(contact.get("target_id","")) != str(geometry.get("target_id",""))): return
	var attack_id := str(payload.get("attack_id",""))
	_remove_attack_role(attack_id,"aim")
	_remove_attack_role(attack_id,"projectile")
	var recipe_phase := "impact" if evo == "evo_crossfire" else ("projectile" if geometry.get("shape","") == "projectile" else "cast")
	if base == "fire_zone" and evo == "evo_inferno_zone" and int(payload.get("stage_index",0)) == int(payload.get("stage_count",0))-1:
		recipe_phase = "eruption"
	var recipe: Dictionary = _catalog.recipe(base,evo,recipe_phase)
	if recipe.is_empty():
		_diagnostic("missing_recipe:"+base+"|"+evo+"|"+recipe_phase)
		return
	var effect := _make_effect(recipe,payload,tick)
	if base == "reentry_combo" and evo.is_empty(): effect.contact_position = _vec(contact.position)
	effect.intensity_tier = _level_tier(int(payload.cast_level)) if payload.has("cast_level") else _tier(snapshot,base)
	if recipe_phase == "projectile":
		effect.projectile_id = geometry.get("projectile_id",-1)
		effect.projectile_binding = "core"
		# Flight lifetime follows actual projectile existence, not a fake target lerp.
		effect.end_tick = 2147483647
	_add(effect)
func _schedule_crossfire(payload: Dictionary, snapshot: Dictionary) -> void:
	var start := int(payload.get("attack_started_tick",0))
	var execute := int(payload.get("execute_tick",start))
	if execute <= int(snapshot.get("active_tick",0)): return
	var aim: Dictionary = _catalog.recipe("wall_cannon","evo_crossfire","aim")
	var effect := _make_effect(aim,payload,start)
	effect.intensity_tier = _tier(snapshot,"wall_cannon")
	effect.end_tick = execute
	_add(effect)
	var lead := mini(18,maxi(0,execute-start))
	if lead == 0: return
	var shell: Dictionary = _catalog.recipe("wall_cannon","evo_crossfire","projectile")
	var flight := _make_effect(shell,payload,execute-lead)
	flight.intensity_tier = _tier(snapshot,"wall_cannon")
	flight.end_tick = execute
	flight.animation_duration_ticks = lead
	flight.projectile_binding = "crossfire"
	flight.flight_target = _array(_vec(payload.get("origin",[0,0])))
	# Visual descent lives only in the VFX DTO. It cannot move the locked core disk.
	flight.flight_start = _array(_vec(flight.flight_target)+Vector2(-36,-128))
	flight.geometry.shape = "projectile"
	flight.geometry.radius = 4.0
	flight.visual_recovery = {"upper_stage_visible":true,"contact_tick":execute}
	_add(flight)
func _projectile_impact(payload: Dictionary, tick: int, snapshot: Dictionary) -> void:
	var attack_id := str(payload.get("attack_id",""))
	var projectile_id = payload.get("projectile_id",-1)
	_effects = _effects.filter(func(e): return not (e.role == "projectile" and (e.get("projectile_id",-2) == projectile_id or e.attack_id == attack_id)))
	var base := str(payload.get("base_item_id",""))
	var recipe: Dictionary = _catalog.recipe(base,"","impact")
	if recipe.is_empty(): return
	# Stable impact identity replaces the same projectile/attack's active contact,
	# with no ever-growing history set. Actual damage count is irrelevant.
	var p := {"attack_id":attack_id,"base_item_id":base,"origin":payload.get("position",[0,0]),"direction":[1,0],"execute_tick":tick,"geometry":{"shape":"circle","origin":payload.get("position",[0,0]),"direction":[1,0],"radius":payload.get("radius",0.0)}}
	var effect := _make_effect(recipe,p,tick)
	effect.intensity_tier = _tier(snapshot,base)
	effect.projectile_id = projectile_id
	effect.effect_id = _run_id+":projectile:"+str(projectile_id)+":impact"
	_add(effect)
func _damage(payload: Dictionary, tick: int) -> void:
	# Core enemy damage carries a frozen hit position, including killing blows.
	# Other actor-only damage may resolve from the current snapshot. Never invent
	# a hit point, player attack or projectile explosion.
	var target_id = payload.get("entity_id",payload.get("target_id",null))
	if target_id == null: return
	var recipe := {"recipe_id":"damage.hit_spark","role":"impact","art_id":"vfx_hit_spark","anchor_policy":"target_ground","render_pass":"contact_overlay","duration_ticks":6,"contact_tick_policy":"damage_tick","shape_binding":"point","priority":30,"reduce_mode":"omit","layers":[{"art_id":"vfx_hit_spark","component":"main","render_pass":"contact_overlay","reduce_mode":"omit"}]}
	var point = payload.get("position",[0,0])
	var p := {"attack_id":"damage:"+str(target_id)+":"+str(tick),"origin":point,"direction":[1,0],"geometry":{"shape":"point","origin":point,"radius":9.0}}
	var effect := _make_effect(recipe,p,tick)
	effect.target_id = target_id
	effect.coordinate_space = "actor" if not payload.has("position") else "world"
	effect.actor_id = "player" if str(target_id) == "player" else "entity:"+str(target_id)
	effect.actor_offset = Vector2.ZERO
	_add(effect)
func _make_effect(recipe: Dictionary, payload: Dictionary, tick: int) -> Dictionary:
	var effect := recipe.duplicate(true)
	var geometry: Dictionary = payload.get("geometry",{}).duplicate(true)
	var attack_id := str(payload.get("attack_id",""))
	effect.merge({"effect_id":attack_id+":"+str(recipe.get("role","cast")),"attack_id":attack_id,"cast_id":str(payload.get("cast_id",attack_id)),"cast_level":int(payload.get("cast_level",0)),"start_tick":tick,"end_tick":tick+int(recipe.get("duration_ticks",1)),"coordinate_space":"world","origin":_vec(payload.get("origin",geometry.get("origin",[0,0]))),"direction":_vec(payload.get("direction",geometry.get("direction",[1,0]))),"geometry":geometry,"intensity_tier":1,"stage_index":int(payload.get("stage_index",0)),"execute_tick":int(payload.get("execute_tick",tick)),"origin_revision":_origin_revision},true)
	# Animation phase is independent of the core-existence retirement sentinel.
	# Ordinary projectile loops share an absolute active-tick phase, so a restore
	# needs no guessed launch tick or extra serialized core state.
	effect.animation_start_tick = 0 if recipe.get("animation_clock","") == "active_tick" else tick
	effect.animation_duration_ticks = int(recipe.get("animation_duration_ticks",recipe.get("duration_ticks",1)))
	effect.animation_loop = recipe.get("animation_loop",false)
	return effect
func _reconstruct_pending(snapshot: Dictionary) -> void:
	for record in snapshot.get("player_attack_instances",[]):
		if record.get("evolution_id","") != "evo_crossfire" or int(record.get("execute_tick",0)) <= int(snapshot.get("active_tick",0)): continue
		if _has(str(record.get("attack_id",""))+":aim"): continue
		var payload: Dictionary = record.duplicate(true)
		payload.geometry = {"shape":record.get("shape","circle"),"origin":record.get("origin",[0,0]),"direction":record.get("direction",[1,0]),"radius":record.get("radius",0.0),"arc_degrees":record.get("arc_degrees",360.0)}
		_schedule_crossfire(payload,snapshot)
	_enforce_capacity(int(snapshot.get("active_tick",0)))
func _reconstruct_fire_fields(snapshot: Dictionary) -> void:
	# Only bounded actual future reservations establish an ongoing floor. The
	# first zero-delay stage has already executed in a canonical Core snapshot;
	# scheduled events alone cannot create it. Rebuild from current local origin
	# so cold restore and rebase need no presentation fields in the save DTO.
	var tick := int(snapshot.get("active_tick",0))
	var groups := {}
	var pending: Array = snapshot.get("player_attack_instances",[])
	for index in mini(MAX_CORE_RESERVATIONS,pending.size()):
		var record: Dictionary = pending[index]
		if record.get("base_item_id","") != "fire_zone" or int(record.get("execute_tick",0)) <= tick or int(record.get("attack_started_tick",tick+1)) > tick or int(record.get("stage_index",0)) <= 0: continue
		var cast := str(record.get("cast_id",""))
		if cast.is_empty(): continue
		if not groups.has(cast):
			if groups.size() >= MAX_FIRE_FIELDS: continue
			groups[cast] = {"record":record,"last_tick":int(record.execute_tick)}
		else:
			groups[cast].last_tick = maxi(int(groups[cast].last_tick),int(record.execute_tick))
	_effects = _effects.filter(func(e): return e.role != "area")
	for cast in groups:
		var group: Dictionary = groups[cast]
		var record: Dictionary = group.record
		var radius: float = _catalog.fire_field_radius(record)
		if radius <= 0: continue
		var recipe: Dictionary = _catalog.recipe("fire_zone",str(record.get("evolution_id","")),"area")
		if recipe.is_empty(): continue
		var payload: Dictionary = record.duplicate(true)
		payload.attack_id = cast
		payload.geometry = {"shape":"circle","origin":record.origin.duplicate(),"direction":record.direction.duplicate(),"radius":radius,"arc_degrees":360.0}
		var effect := _make_effect(recipe,payload,int(record.attack_started_tick))
		effect.end_tick = int(group.last_tick)
		effect.execute_tick = int(record.attack_started_tick)
		effect.stage_index = 0
		effect.intensity_tier = _level_tier(int(record.get("cast_level",1)))
		_add(effect)
	_enforce_capacity(tick)
func _reconstruct_projectiles(snapshot: Dictionary) -> void:
	for projectile in snapshot.get("projectiles",[]):
		var id := str(projectile.get("attack_id",""))+":projectile"
		if _has(id): continue
		var base := str(projectile.get("item_id",""))
		var recipe: Dictionary = _catalog.recipe(base,"","projectile")
		if recipe.is_empty(): continue
		var payload := {"attack_id":projectile.get("attack_id","projectile:"+str(projectile.id)),"origin":projectile.position,"direction":_array(_vec(projectile.get("velocity",[1,0])).normalized()),"geometry":{"shape":"projectile","origin":projectile.position,"direction":_array(_vec(projectile.get("velocity",[1,0])).normalized()),"radius":projectile.get("radius",4.0),"projectile_id":projectile.id}}
		var effect := _make_effect(recipe,payload,int(snapshot.get("active_tick",0)))
		effect.intensity_tier = _tier(snapshot,base)
		effect.projectile_binding = "core"
		effect.projectile_id = projectile.id
		effect.end_tick = 2147483647
		_add(effect)
	_enforce_capacity(int(snapshot.get("active_tick",0)))
func _prune(tick: int, snapshot: Dictionary) -> void:
	_effects = _effects.filter(func(e): return int(e.end_tick) > tick and (e.get("projectile_binding","") != "core" or not _projectile(snapshot,e.get("projectile_id",-1)).is_empty()))
func _add(effect: Dictionary) -> void:
	for index in _effects.size():
		if _effects[index].effect_id == effect.effect_id:
			# Reconstructed reservations must not reset an existing visual clock.
			if _effects[index].start_tick == effect.start_tick: return
			_effects[index] = effect
			return
	_effects.append(effect)
func _has(id: String) -> bool:
	for effect in _effects:
		if effect.effect_id == id: return true
	return false
func _remove_attack_role(attack_id: String, role: String) -> void:
	_effects = _effects.filter(func(e): return e.attack_id != attack_id or e.role != role)
func _enforce_capacity(tick: int) -> void:
	_limit_recovery(tick,"cast",_trail_capacity)
	_limit_recovery(tick,"impact",_explosion_capacity)
	if not capacity_valid(): _diagnostic("insufficient_critical_capacity")
	# Low-priority optional damage/trails disappear before active scheduled/contact.
	while _effects.size() > _effect_capacity:
		var candidate := -1
		for index in _effects.size():
			var e: Dictionary = _effects[index]
			var protected: bool = e.role in ["aim","projectile","area"] or (e.priority >= 80 and tick == e.execute_tick)
			if protected: continue
			if candidate == -1 or e.priority < _effects[candidate].priority or (e.priority == _effects[candidate].priority and e.start_tick < _effects[candidate].start_tick): candidate = index
		if candidate >= 0:
			_effects.remove_at(candidate)
		elif _effects.size() <= _effect_capacity+_critical_reserve:
			break
		else:
			_diagnostic("critical_pool_exhausted")
			_effects.remove_at(_effects.size()-1)
	var trail_count := 0
	var explosion_count := 0
	for e in _effects:
		if e.role == "trail":
			trail_count += 1
			e.omit_optional = trail_count > _trail_capacity
		if e.role == "impact" and e.priority >= 100:
			explosion_count += 1
			# Explosion cap reduces optional dust, never actual contact/main form.
			e.omit_optional = explosion_count > _explosion_capacity
func _limit_recovery(tick: int, role: String, capacity: int) -> void:
	var recovery: Array[Dictionary] = []
	for e in _effects:
		if e.role == role and tick > int(e.execute_tick) and (role != "impact" or e.priority >= 100): recovery.append(e)
	recovery.sort_custom(func(a,b): return a.priority < b.priority or (a.priority == b.priority and (a.start_tick < b.start_tick or (a.start_tick == b.start_tick and a.effect_id < b.effect_id))))
	while recovery.size() > capacity:
		var removed: Dictionary = recovery.pop_front()
		_effects = _effects.filter(func(e): return e.effect_id != removed.effect_id)
func _diagnostic(message: String) -> void:
	if not message in _diagnostics: _diagnostics.append(message)
func _sequence(event: Dictionary) -> int:
	var id := str(event.get("event_id",""))
	var suffix := id.get_slice(":",id.get_slice_count(":")-1)
	return int(suffix) if suffix.is_valid_int() else -1
func _projectile(snapshot: Dictionary, id: Variant) -> Dictionary:
	for projectile in snapshot.get("projectiles",[]):
		if projectile.get("id",null) == id: return projectile
	return {}
func _target(snapshot: Dictionary, id: Variant) -> Dictionary:
	for target in snapshot.get("entities",[]):
		if str(target.get("id","")) == str(id) and float(target.get("hp",0.0)) > 0.0: return target
	return {}
func _vec(value: Variant) -> Vector2:
	if value is Vector2: return value
	if value is Array and value.size() == 2: return Vector2(float(value[0]),float(value[1]))
	return Vector2.ZERO
func _array(value: Vector2) -> Array:
	return [value.x,value.y]

func _tier(snapshot: Dictionary, base_item_id: String) -> int:
	var level := int(snapshot.get("equipment",{}).get(base_item_id,1))
	return _level_tier(level)
func _level_tier(level: int) -> int:
	return 3 if level >= 5 else (2 if level >= 3 else 1)
