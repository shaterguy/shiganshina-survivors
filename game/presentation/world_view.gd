class_name WorldView
extends Node2D
const CityDepth = preload("res://game/presentation/city_render.gd")
const CityAddress = preload("res://game/world/world_address.gd")
const VfxBridge = preload("res://game/presentation/combat_vfx_bridge.gd")
const ArmoredMotion = preload("res://game/presentation/armored_motion_tracker.gd")
const ArmoredPose = preload("res://game/presentation/armored/armored_pose.gd")
const ArmoredRaster = preload("res://game/presentation/armored/armored_raster.gd")
const ArmoredDrawSplit = preload("res://game/presentation/armored/armored_draw_split.gd")
var _armored_motion = ArmoredMotion.new()
var _armored_pose = ArmoredPose.new()
var _armored_raster = null
var _armored_split = null
var _armored_display: Dictionary = {"supported":false,"reason":"no_actor"}
var _armored_setup_attempted := false
var _armored_setup_error := ""
var _armored_input_bytes := PackedByteArray()
var _combat_bridge = VfxBridge.new()
var _combat_snapshot: Dictionary = {}
# Last successful Core sample only; this is not a second combat clock.
var _enemy_attack_packet: Dictionary = {}
# Explicit derived presentation input, owned read-only by the controller. Its
# cache identity changes with prepared Core/coverage/geometry/origin, never ticks.
var _city_active := false
var _city_view: Dictionary = {}
var _city_draw_data: Dictionary = {}
var _outline_textures: Dictionary = {}
var _raster_images: Dictionary = {}
var _corpse_serial := 0
var _dock_definition: Dictionary = {}
var _assets: Dictionary = {}
var _map: Dictionary = {}
var _effects: Array[Dictionary] = []
var _shake_until := 0.0
var _textures: Dictionary = {}
var _snapshot: Dictionary = {}
var _clock := 0.0
var _attack_until := 0.0
var _hit_until := 0.0
var _enemy_hits: Dictionary = {}
var _actor_draw_tint := Color.WHITE
var _corpses: Array[Dictionary] = []
var _attack_started := 0.0
var reduce_effects := false
var screen_shake := 0.4
var _camera := Vector2.ZERO
var _viewport_size := Vector2(800,450)
# Presentation-only observations; never serialized into RunState. The app emits
# at most eight fixed simulation ticks between presents (bounded catch-up).
const MAX_GAIT_TICK_GAP := 8
var _gait_tracks: Dictionary = {}
var _gait_run_key: Array = []
var _gait_tick := -1
func reset_presentation(reset_combat := true) -> void:
	_enemy_attack_packet.clear()
	_reset_armored_display()
	if reset_combat:
		_combat_bridge.reset()
		_armored_motion.reset()
	_combat_snapshot.clear()
	_city_active = false
	_city_view = {}
	_city_draw_data.clear()
	_corpse_serial = 0
	_snapshot = {}
	_gait_tracks.clear()
	_gait_run_key.clear()
	_gait_tick = -1
	_clock = 0.0
	_attack_until = 0.0
	_attack_started = 0.0
	_hit_until = 0.0
	_shake_until = 0.0
	_enemy_hits.clear()
	_effects.clear()
	_corpses.clear()
	_camera = Vector2.ZERO
func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	load_manifest()
	var map_data = JSON.parse_string(FileAccess.get_file_as_string("res://chapters/chapter_01/map.json"))
	if map_data is Dictionary: _map = map_data
func load_manifest() -> void:
	if not FileAccess.file_exists("res://assets/manifest.json"): return
	var manifest = JSON.parse_string(FileAccess.get_file_as_string("res://assets/manifest.json"))
	if manifest is Dictionary:
		_assets = manifest.get("assets",{})
		_combat_bridge.set_asset_metadata(_assets)
		_textures.clear(); _outline_textures.clear(); _raster_images.clear()
func frame_rect(asset_id: String, animation: String, seconds: float) -> Rect2:
	if not _assets.has(asset_id): return Rect2()
	var record: Dictionary = _assets[asset_id]
	var anim: Dictionary = record.get("animations",{}).get(animation,{"frames":[0],"fps":1,"loop":true})
	var frames: Array = anim.get("frames",[0])
	if frames.is_empty(): return Rect2()
	var index := int(seconds*float(anim.get("fps",8)))
	index = index%frames.size() if anim.get("loop",true) else mini(index,frames.size()-1)
	var frame := int(frames[index])
	var width := int(record.get("cell_w",record.get("width",32)))
	var height := int(record.get("cell_h",record.get("height",32)))
	var columns := int(record.get("columns",1))
	return Rect2((frame%columns)*width,(frame/columns)*height,width,height)
func present(snapshot: Dictionary) -> void:
	_enemy_attack_packet.clear()
	_city_active = false
	_city_view = {}
	_update_gait(snapshot)
	_armored_motion.present(snapshot)
	_snapshot = snapshot
	if not snapshot.is_empty(): _camera = Vector2(snapshot.player.position[0],snapshot.player.position[1])
	_sync_armored_display()
	queue_redraw()
func present_enemy_attacks(packet: Dictionary) -> Dictionary:
	_enemy_attack_packet.clear()
	queue_redraw()
	if _snapshot.is_empty() or (_city_active and _city_view.is_empty()) or not packet.get("ok") is bool or not packet.get("attacks") is Array:
		return {"ok":false,"error_code":"attack_view_unavailable"}
	if not packet.ok:
		return {"ok":false,"error_code":str(packet.get("error_code","attack_view_unavailable"))}
	var world: Dictionary = _snapshot.get("world",{})
	var identity := {"run_id":_snapshot.get("run_id"),"tick":_snapshot.get("active_tick"),"scene_id":world.get("scene_id","finite"),"origin_revision":world.get("origin_revision",0),"world_revision":world.get("world_revision",0)}
	for field in identity:
		if not packet.has(field) or typeof(packet[field]) != typeof(identity[field]) or packet[field] != identity[field]: return {"ok":false,"error_code":"attack_view_stale"}
	if not packet.attacks.is_empty() and _snapshot.get("phase") not in ["survival","evacuation"]:
		return {"ok":false,"error_code":"attack_view_terminal"}
	var owners: Dictionary = {}
	for entity in _snapshot.get("entities",[]):
		if entity.get("enemy_id") in ["grabber","quadruped","stone_thrower"] and str(entity.get("boss_id","")).is_empty() and float(entity.get("hp",0)) > 0: owners[str(entity.id)] = entity
	var seen: Dictionary = {}
	for attack in packet.attacks:
		if not attack is Dictionary or not attack.get("role_id") is String or attack.role_id not in ["grabber","quadruped","stone_thrower"] or not attack.get("source_id") is String or not owners.has(attack.source_id) or owners[attack.source_id].enemy_id != attack.role_id or seen.has(attack.source_id):
			return {"ok":false,"error_code":"attack_view_invalid"}
		if not attack.get("attack_id") is String or not attack.attack_id.begins_with(str(identity.run_id)+":enemy:"+attack.source_id+":") or not _enemy_hand_point_valid(attack.get("position")) or attack.position != owners[attack.source_id].position or not _enemy_attack_sample_valid(attack):
			return {"ok":false,"error_code":"attack_view_invalid"}
		seen[attack.source_id] = true
	_enemy_attack_packet = packet.duplicate(true)
	return {"ok":true}
func _enemy_attack_sample_valid(attack: Dictionary) -> bool:
	if not attack.get("phase") is String or attack.phase not in ["windup","attack","recover"]: return false
	if attack.role_id == "grabber":
		if not attack.get("hand_pose") is Dictionary: return false
		for field in ["rest","previous","current","warning_start","warning_end"]:
			if not _enemy_hand_point_valid(attack.hand_pose.get(field)): return false
	elif attack.has("hand_pose"): return false
	if attack.role_id == "stone_thrower":
		if not attack.get("projectile_pose") is Dictionary: return false
		var pose: Dictionary = attack.projectile_pose
		for field in ["previous","current"]:
			if not _enemy_hand_point_valid(pose.get(field)): return false
		if not (pose.get("radius") is int or pose.get("radius") is float) or not is_finite(float(pose.radius)) or float(pose.radius) <= 0.0: return false
		if not pose.get("visible") is bool or not pose.get("blocked") is bool: return false
		if attack.phase == "attack":
			if pose.visible == pose.blocked: return false
		elif pose.visible or pose.blocked: return false
	elif attack.has("projectile_pose"): return false
	if not attack.get("telegraph_geometry") is Array or not attack.get("damage_geometry") is Array: return false
	if attack.telegraph_geometry.size() != (1 if attack.phase == "windup" else 0): return false
	# The collision tick retains its final clipped sweep. Later blocked ticks
	# are still in the attack phase but have neither damage nor a visible rock.
	var blocked_rock: bool = attack.role_id == "stone_thrower" and attack.projectile_pose.blocked
	if attack.phase == "attack" and blocked_rock:
		if attack.damage_geometry.size() > 1: return false
	elif attack.damage_geometry.size() != (1 if attack.phase == "attack" else 0): return false
	for geometry in attack.telegraph_geometry+attack.damage_geometry:
		if not geometry is Dictionary or not geometry.get("shape") is String or geometry.shape != "line" or not _enemy_hand_point_valid(geometry.get("origin")) or not _enemy_hand_point_valid(geometry.get("direction")): return false
		for field in ["length","width"]:
			var value = geometry.get(field)
			if not (value is int or value is float) or not is_finite(float(value)) or float(value) < 0.0: return false
	return true
func _enemy_hand_point_valid(value: Variant) -> bool:
	if not value is Array or value.size() != 2: return false
	for coordinate in value:
		if not (coordinate is int or coordinate is float) or not is_finite(float(coordinate)): return false
	return true
func enemy_attack_commands() -> Array[Dictionary]:
	var commands: Array[Dictionary] = []
	for attack in _enemy_attack_packet.get("attacks",[]):
		# These footprints are diagnostics of Core geometry, not finished actor
		# or projectile art. Recovery is harmless and has no danger footprint.
		var geometry: Array = attack.telegraph_geometry if attack.phase == "windup" else attack.damage_geometry
		var active_kind: String = {"grabber":"hand_sweep","quadruped":"body_sweep","stone_thrower":"projectile_sweep"}[attack.role_id]
		for primitive in geometry:
			commands.append({"attack_id":attack.attack_id,"source_id":attack.source_id,"role_id":attack.role_id,"kind":"warning" if attack.phase == "windup" else active_kind,"geometry":primitive.duplicate(true)})
		var pose: Dictionary = attack.get("projectile_pose",{})
		if pose.get("visible",false):
			var command := {"attack_id":attack.attack_id,"source_id":attack.source_id,"role_id":attack.role_id,"kind":"projectile","asset_id":"enemy_stone_projectile","position":pose.current.duplicate(),"radius":pose.radius}
			var art: Dictionary = _assets.get(command.asset_id,{})
			if art.is_empty() or art.get("export_blocked",false): command.diagnostic = "enemy_projectile_art_unavailable"
			commands.append(command)
	return commands
func _draw_enemy_attacks() -> void:
	for command in enemy_attack_commands():
		if command.kind == "projectile":
			if command.has("diagnostic"): continue
			var region := frame_rect(command.asset_id,"idle",0.0)
			if region.size.x <= 0.0 or region.size.y <= 0.0: continue
			# A centered square stone atlas is scaled to the real swept diameter.
			_sprite(command.asset_id,Vector2(command.position[0],command.position[1]),"idle",float(command.radius)*2.0/maxf(region.size.x,region.size.y),false,0.0)
			continue
		var hazard: Dictionary = command.geometry
		hazard.active_from_tick = int(_snapshot.active_tick)+(1 if command.kind == "warning" else 0)
		_draw_telegraph(hazard)
func _cycle_distance(asset_id: String) -> float:
	var gait = _assets.get(asset_id,{}).get("gait",{})
	if not gait is Dictionary: return 0.0
	var distance = gait.get("cycle_distance_px",0.0)
	if not (distance is int or distance is float): return 0.0
	return float(distance) if is_finite(float(distance)) and float(distance) > 0.0 else 0.0
func movement_seconds(asset_id: String, actor_id: String, scale_value: float, fallback_seconds: float) -> float:
	var cycle := _cycle_distance(asset_id)*absf(scale_value)
	if cycle <= 0.0 or not is_finite(cycle): return fallback_seconds
	var animation: Dictionary = _assets[asset_id].get("animations",{}).get("move",{})
	var frames: Array = animation.get("frames",[])
	var fps := float(animation.get("fps",8.0))
	if frames.is_empty() or fps <= 0.0 or not is_finite(fps): return fallback_seconds
	var distance := float(_gait_tracks.get(actor_id,{}).get("distance",0.0))
	# Convert distance phase to the existing manifest-driven atlas selector. The
	# clock remains authoritative for every asset without optional gait metadata.
	return fposmod(distance/cycle,1.0)*frames.size()/fps
func _update_gait(snapshot: Dictionary) -> void:
	if snapshot.is_empty():
		reset_presentation()
		return
	var tick := int(snapshot.get("active_tick",0))
	var key: Array = [snapshot.get("run_id",""),snapshot.get("seed",0),snapshot.get("chapter_id",""),snapshot.get("content_revision","")]
	if (not _gait_run_key.is_empty() and key != _gait_run_key) or tick < _gait_tick:
		reset_presentation()
	_gait_run_key = key
	_gait_tick = tick
	var seen: Dictionary = {}
	var active: bool = snapshot.get("phase","") in ["survival","evacuation"]
	var paused: bool = not snapshot.get("pause_reasons",[]).is_empty()
	var player: Dictionary = snapshot.get("player",{})
	if active and float(player.get("hp",1.0)) > 0.0:
		var animation := player_animation(snapshot)
		var action: String = player.get("action_state","move")
		var locomotion: bool = animation in ["move","idle"] and action in ["move","idle"] and player.get("grounded",true)
		var moving: bool = locomotion and animation == "move" and action == "move"
		_track_gait("player","garrison_01",player,tick,moving,locomotion,paused,seen)
	if active:
		for entity in snapshot.get("entities",[]):
			if float(entity.get("hp",1.0)) <= 0.0: continue
			var id := str(entity.id)
			var definition: Dictionary = snapshot.get("rules",{}).get("enemy_catalog",{}).get(entity.enemy_id,{})
			var asset_id := approved_art_id(str(definition.get("art_id","titan_basic")))
			var action: String = entity.get("action_state","move")
			var locomotion: bool = action in ["move","idle"] and entity.get("grounded",true) and not _enemy_hits.has(id)
			var moving: bool = locomotion and action == "move"
			_track_gait("entity:"+id,asset_id,entity,tick,moving,locomotion,paused,seen)
	for id in _gait_tracks.keys():
		if not seen.has(id): _gait_tracks.erase(id)
func _track_gait(id: String, asset_id: String, actor: Dictionary, tick: int, moving: bool, locomotion: bool, paused: bool, seen: Dictionary) -> void:
	if _cycle_distance(asset_id) <= 0.0: return
	seen[id] = true
	var position_data: Array = actor.position
	var position := Vector2(position_data[0],position_data[1])
	var velocity_data: Array = actor.get("velocity",[0.0,0.0])
	var speed := Vector2(velocity_data[0],velocity_data[1]).length()
	var identity: Array = [asset_id,actor.get("spawned_tick",0),actor.get("enemy_id","")]
	var started := int(actor.get("action_started_tick",0))
	var previous: Dictionary = _gait_tracks.get(id,{})
	var distance := 0.0
	if not previous.is_empty() and previous.identity == identity:
		distance = float(previous.distance)
		var elapsed := tick-int(previous.tick)
		var travel := position.distance_to(previous.position)
		# Grounded idle is a valid starting point for the very first move tick;
		# attack/hit/airborne/recovery are not. A changed action epoch between
		# two move samples may hide an entire leap, so rebase that interval too.
		var same_action: bool = started == int(previous.started) or not previous.moving
		var continuous: bool = moving and previous.locomotion and same_action
		var plausible := travel <= maxf(speed,float(previous.speed))*float(elapsed)/60.0+0.001
		if not paused and continuous and elapsed > 0 and elapsed <= MAX_GAIT_TICK_GAP and plausible:
			distance += travel
	_gait_tracks[id] = {"identity":identity,"position":position,"speed":speed,"tick":tick,"moving":moving,"locomotion":locomotion,"started":started,"distance":distance}
func consume_combat_events(events: Array[Dictionary], current_snapshot: Dictionary) -> void:
	# Receive every successful Core tick, including ticks between rendered frames.
	# Reject stale batches before touching accepted scene/identity observations.
	if not _combat_bridge.validate_batch(events,current_snapshot) or not _armored_motion.validate_batch(events,current_snapshot): return
	var key: Array = [current_snapshot.get("run_id",""),current_snapshot.get("seed",0),current_snapshot.get("chapter_id",""),current_snapshot.get("content_revision","")]
	var watermark: Dictionary = _combat_bridge.debug_stats()
	var restored: bool = watermark.run_id == str(current_snapshot.get("run_id",current_snapshot.get("seed",""))) and (int(current_snapshot.get("active_tick",0)) < int(watermark.bridge_tick) or int(current_snapshot.get("event_seq",0)) < int(watermark.event_seq))
	if restored or (not _gait_run_key.is_empty() and key != _gait_run_key) or int(current_snapshot.get("active_tick",0)) < _gait_tick:
		# Bridge owns the restore floor; clearing visual observations must not
		# erase that history before the accepted rollback snapshot is synced.
		reset_presentation(false)
	if not _combat_bridge.consume(events,current_snapshot): return
	_armored_motion.consume(events,current_snapshot)
	_combat_snapshot = current_snapshot.duplicate(true)
	for event in events:
		if event.get("type","") == "player_attack" and event.get("payload",{}).get("phase","") == "executed":
			var id := str(event.event_id)
			var sequence := int(id.get_slice(":",id.get_slice_count(":")-1))
			if watermark.run_id == str(current_snapshot.get("run_id",current_snapshot.get("seed",""))) and sequence <= int(watermark.event_seq): continue
			if _clock >= _attack_until: _attack_started = _clock
			_attack_until = _clock+0.28
func armored_motion_observation() -> Dictionary:
	return _armored_motion.debug_observation()
func combat_vfx_commands(snapshot: Dictionary = {}) -> Array[Dictionary]:
	var current := snapshot if not snapshot.is_empty() else _snapshot
	if snapshot.is_empty() and not _combat_snapshot.is_empty() and (current.is_empty() or _combat_snapshot.get("run_id") != current.get("run_id") or int(_combat_snapshot.get("active_tick",0)) > int(current.get("active_tick",0))):
		current = _combat_snapshot
	var camera := _camera
	if not current.is_empty() and current.get("player",{}).has("position"):
		camera = Vector2(current.player.position[0],current.player.position[1])
	return _combat_bridge.present(current,reduce_effects,Rect2(camera-_viewport_size*0.5,_viewport_size))
func consume_events(events: Array[Dictionary]) -> void:
	for event in events:
		if event.type == "damage" and str(event.payload.get("target_id","")) == "player":
			_shake_until = _clock+0.18
			_hit_until = _clock+0.18
		if event.type == "damage" and str(event.payload.get("target_id", "")) != "player":
			_enemy_hits[str(event.payload.target_id)] = _clock+0.14
			# The legacy feedback-only entry point retains its historical actor
			# pose. Real runtime casts are driven solely by executed player_attack.
			if _combat_snapshot.is_empty():
				if _clock >= _attack_until: _attack_started = _clock
				_attack_until = _clock + 0.28
			for enemy in _snapshot.get("entities",[]):
				if str(enemy.id) == str(event.payload.get("target_id","")) and _effects.size() < 32:
					if float(event.payload.get("hp",1)) <= 0 and _corpses.size() < 24:
						var art_id := str(_snapshot.get("rules",{}).get("enemy_catalog",{}).get(enemy.enemy_id,{}).get("art_id","titan_basic"))
						_corpse_serial += 1
						_corpses.append({"id":"%s:%d" % [str(enemy.id),_corpse_serial],"asset":approved_art_id(art_id),"position":enemy.position.duplicate(),"started":_clock})
					if not _damage_has_drawable_vfx(event):
						_effects.append({"position":enemy.position.duplicate(),"started":_clock,"asset":"impact_fx"})
func _process(delta: float) -> void:
	if _snapshot.is_empty() or _snapshot.get("pause_reasons",[]).is_empty(): _clock += delta
	_corpses = _corpses.filter(func(corpse): return _clock-float(corpse.started) < 0.45)
	for id in _enemy_hits.keys():
		if float(_enemy_hits[id]) <= _clock: _enemy_hits.erase(id)
	_effects = _effects.filter(func(effect): return _clock-float(effect.started) < 0.34)
	_viewport_size = get_viewport_rect().size
	queue_redraw()
func approved_art_id(asset_id: String) -> String:
	if not _assets.has(asset_id) or _assets[asset_id].get("export_blocked",false): return "titan_basic"
	return asset_id
func _texture(asset_id: String) -> Texture2D:
	if not _assets.has(asset_id): return null
	if _textures.has(asset_id): return _textures[asset_id]
	var path: String = _assets[asset_id].path
	# VFX source hashes authorize PNG bytes, so draw those exact bytes rather
	# than a possibly older editor-imported texture. Candidate QA uses this
	# same pixel adapter after its separate, labelled validation boundary.
	var authored_effect: bool = asset_id.begins_with("vfx_") and _assets[asset_id].get("kind","") == "effect"
	var texture = load(path) if not authored_effect and ResourceLoader.exists(path) else null
	if texture == null and path.ends_with(".png") and FileAccess.file_exists(path):
		var raster := Image.new()
		if raster.load_png_from_buffer(FileAccess.get_file_as_bytes(path)) == OK and not raster.is_empty(): texture = ImageTexture.create_from_image(raster)
	if texture is Texture2D:
		_textures[asset_id] = texture
		return texture
	return null
func _screen(world: Vector2) -> Vector2:
	var shake := Vector2.ZERO
	if _clock < _shake_until and not reduce_effects: shake = Vector2(sin(_clock*101),cos(_clock*83))*screen_shake*4
	return world-_camera+_viewport_size*0.5+shake
func _draw() -> void:
	if is_instance_valid(_armored_split): _armored_split.begin_frame()
	if _city_active:
		_draw_streamed_city()
		return
	_draw_city()
	if _snapshot.is_empty():
		var intro := _texture("colossal_intro")
		if intro != null:
			var factor := maxf(_viewport_size.x/640.0,_viewport_size.y/360.0)
			var target := Vector2(640,360)*factor
			_world_rect(intro,Rect2((_viewport_size-target)*0.5,target),false)
		return
	var packet := _city_render_packet()
	if not packet.get("ok",true): return
	var vfx := combat_vfx_commands()
	_draw_vfx_pass(vfx,"ground")
	for drop in _snapshot.get("drops",[]):
		_sprite("xp_pickup",Vector2(drop.position[0],drop.position[1]),"idle",1.0)
	if _snapshot.phase == "evacuation":
		var zone: Array = _snapshot.escape_zone
		_sprite("escape_marker",Vector2(zone[0]+zone[2]/2,zone[1]+zone[3]/2),"idle",2.0)
	_draw_upright_with_vfx(packet.upright,vfx)
	_draw_vfx_pass(vfx,"contact_overlay")
	_draw_hit_fallbacks()
	# Enemy warnings and the exact player-location feedback stay above effects.
	for hazard in _snapshot.get("telegraphs",[]): _draw_telegraph(hazard)
	_draw_enemy_attacks()
	var player: Dictionary = _city_draw_data.actor["player"]
	_sprite(player.asset_id,player.position,player.pose,player.scale,player.flip,player.seconds)
func player_animation(snapshot: Dictionary) -> String:
	if snapshot.phase == "dead": return "death"
	if _clock < _hit_until: return "hit"
	if _clock < _attack_until: return "attack"
	var velocity: Array = snapshot.player.get("velocity",[0,0])
	return "move" if Vector2(velocity[0],velocity[1]).length() > 1 else "idle"
func telegraph_pieces(hazard: Dictionary) -> Array[Dictionary]:
	var shape := str(hazard.get("shape","circle"))
	var radius := float(hazard.get("radius",32))
	if shape == "circle":
		return [{"asset":"danger_circle","region":Rect2(0,0,64,64),"rect":Rect2(-radius,-radius,2*radius,2*radius)}]
	if shape == "sector":
		var piece := {"asset":"danger_sector","region":Rect2(0,0,128,256),"rect":Rect2(0,-radius,radius,2*radius),"rotation":0.0}
		var arc := float(hazard.get("arc_degrees",90.0))
		if arc <= 90.0: return [piece]
		# Union of two90-degree raster sectors matches140/150-degree attacks.
		var second := piece.duplicate()
		piece.rotation = -deg_to_rad((arc-90.0)/2.0)
		second.rotation = -piece.rotation
		return [piece,second]
	var width := float(hazard.get("width",32))
	var length := float(hazard.get("length",96))
	return [{"asset":"danger_line","region":Rect2(0,0,16,32),"rect":Rect2(-width/2,-width/2,width/2,width)}, {"asset":"danger_line","region":Rect2(16,0,96,32),"rect":Rect2(0,-width/2,length,width)}, {"asset":"danger_line","region":Rect2(112,0,16,32),"rect":Rect2(length,-width/2,width/2,width)}]
func _draw_telegraph(hazard: Dictionary) -> void:
	var origin: Array = hazard.get("origin",[0,0])
	var direction: Array = hazard.get("direction",[1,0])
	var angle := Vector2(direction[0],direction[1]).angle() if hazard.shape != "circle" else 0.0
	_world_transform(_screen(Vector2(origin[0],origin[1])),angle)
	var active := int(_snapshot.active_tick) >= int(hazard.active_from_tick)
	var alpha := 0.98 if active else (0.70 if reduce_effects else 0.65 + 0.12*sin(_clock*7.0))
	for piece in telegraph_pieces(hazard):
		_world_transform(_screen(Vector2(origin[0],origin[1])),angle+float(piece.get("rotation",0)))
		var texture := _texture(piece.asset)
		if texture != null: _world_region(texture,piece.rect,piece.region,Color(1,1,1,alpha))
	_world_transform(Vector2.ZERO)
func _sprite(asset_id: String, world: Vector2, animation: String, scale_value: float, flip := false, seconds := -1.0) -> void:
	var texture := _texture(asset_id)
	if texture == null: return
	var region := frame_rect(asset_id,animation,_clock if seconds < 0 else seconds)
	var anchor: Array = _assets[asset_id].get("anchor_px",[region.size.x/2,region.size.y])
	_world_transform(_screen(world),0,Vector2(-1 if flip else 1,1)*scale_value)
	_world_region(texture,Rect2(-Vector2(anchor[0],anchor[1]),region.size),region,_actor_draw_tint)
	_world_transform(Vector2.ZERO)
func _draw_city() -> void:
	var asset_id := "city_tiles"
	var texture := _texture(asset_id)
	if texture == null: return
	var record: Dictionary = _assets[asset_id]
	var cell := int(record.cell_w)
	var columns := int(record.columns)
	var count := int(record.width/record.cell_w)*int(record.height/record.cell_h)
	var start := Vector2i(floor((_camera.x-_viewport_size.x/2)/cell),floor((_camera.y-_viewport_size.y/2)/cell))
	for row in range(int(_viewport_size.y/cell)+3):
		for column in range(int(_viewport_size.x/cell)+3):
			var world := Vector2((start.x+column)*cell,(start.y+row)*cell)
			var index := posmod((start.x+column)*7+(start.y+row)*11,count)
			var region := Rect2((index%columns)*cell,(index/columns)*cell,cell,cell)
			var tile_texture := texture
			var tint := Color(0.48,0.56,0.52)
			if world.y >= 320 and world.y < 512 and absf(world.x) < 64:
				tile_texture = _texture("dock_planks")
				region = frame_rect("dock_planks","idle",0)
				tint = Color(0.8,0.8,0.8)
			elif world.y >= float(_map.get("river_y",416)):
				tile_texture = _texture("canal_water")
				region = frame_rect("canal_water","idle",_clock)
				tint = Color(0.65,0.7,0.75)
			if tile_texture != null: _world_region(tile_texture,Rect2(_screen(world),Vector2(cell,cell)),region,tint)

func _draw_props() -> void:
	for prop in _map.get("props",[]):
		var world := Vector2(prop.position[0],prop.position[1])
		var point := _screen(world)
		if point.x < -210 or point.x > _viewport_size.x+210 or point.y < -20 or point.y > _viewport_size.y+210: continue
		_sprite(str(prop.asset_id),world,"idle",1.0)

# The terrain packet must be from this snapshot's prepared Core. Refusals leave
# a blank world for the controller's error UI, never a plausible finite fallback.
func present_city(snapshot: Dictionary, derived_terrain_view: Dictionary) -> Dictionary:
	_enemy_attack_packet.clear()
	var world: Dictionary = snapshot.get("world",{})
	var valid: bool = not snapshot.is_empty() and world.get("mode") == "streamed_city" and derived_terrain_view.get("ok",false) and derived_terrain_view.get("stage") == world.get("stage") and derived_terrain_view.get("origin_chunk") == world.get("origin_chunk") and derived_terrain_view.get("origin_revision") == world.get("origin_revision") and derived_terrain_view.has("world_revision") and derived_terrain_view.world_revision == world.get("world_revision")
	var code := "world_not_ready"
	if valid and world.stage == "dock":
		if _dock_definition.is_empty():
			var dock = JSON.parse_string(FileAccess.get_file_as_string("res://chapters/chapter_01/authored_dock.json"))
			if dock is Dictionary: _dock_definition = dock
		valid = derived_terrain_view.get("scene_id") == "authored_dock" and not _dock_definition.is_empty() and _map.get("geometry") == _dock_definition.get("geometry")
		code = "dock_render_unavailable"
	elif valid:
		valid = world.stage == "city" and derived_terrain_view.get("scene_id") == "city" and derived_terrain_view.get("chunks") is Array
	if not valid:
		_reset_armored_display()
		_city_active = true; _city_view = {}; queue_redraw()
		return {"ok":false,"error_code":code}
	_rebase_city_observations(snapshot,derived_terrain_view)
	_update_gait(snapshot)
	_armored_motion.present(snapshot)
	_city_active = true
	# No duplicate, regeneration, serialization or authority mutation here.
	_city_view = derived_terrain_view
	_snapshot = snapshot
	_camera = Vector2(snapshot.player.position[0],snapshot.player.position[1])
	_sync_armored_display()
	queue_redraw()
	return {"ok":true}
func _rebase_city_observations(snapshot: Dictionary, terrain: Dictionary) -> void:
	if _city_view.is_empty() or _city_view.get("origin_chunk") == terrain.origin_chunk: return
	if _snapshot.get("run_id") != snapshot.get("run_id") or _city_view.stage != terrain.stage:
		_corpses.clear(); _effects.clear(); _gait_tracks.clear()
		return
	var shift := CityAddress.relative(_city_view.origin_chunk,Vector2.ZERO,terrain.origin_chunk)
	if not shift.ok:
		_corpses.clear(); _effects.clear(); _gait_tracks.clear()
		return
	for collection in [_corpses,_effects]:
		for observation in collection:
			observation.position = [observation.position[0]+shift.local.x,observation.position[1]+shift.local.y]
	for track in _gait_tracks.values(): track.position += shift.local
func _actor_view(id: Variant, asset_id: String, point: Vector2, pose: String, scale_value: float, flip: bool, seconds: float) -> Dictionary:
	var record: Dictionary = _assets.get(asset_id,{})
	var size := Vector2(record.get("cell_w",32),record.get("cell_h",32))*scale_value
	var anchor: Array = record.get("anchor_px",[size.x/2,size.y])
	var corner := Vector2(-float(anchor[0])*scale_value,-float(anchor[1])*scale_value)
	if flip: corner.x = float(anchor[0])*scale_value-size.x
	var result := {"id":id,"asset_id":asset_id,"position":point,"depth_y":point.y,"render_bounds":Rect2(point+corner,size),"pose":pose,"scale":scale_value,"flip":flip,"seconds":seconds,"tint":Color(1.55,1.40,1.15) if float(_enemy_hits.get(str(id),-1.0))-_clock > 0.14-5.0/60.0 else Color.WHITE}
	if asset_id == "armored_titan" and _armored_display.get("supported",false) and str(id) == _armored_display.actor_id and point == _armored_display.root_position:
		result.armored_raster = true
		result.flip = _armored_display.flip
		result.scale = _armored_display.display_scale
		result.render_bounds = _armored_world_transform() * _armored_raster.local_bounds()
	return result
func _city_render_packet() -> Dictionary:
	var vfx_commands := combat_vfx_commands()
	var actors: Array = []
	var corpses: Array = []
	var projectiles: Array = []
	_city_draw_data = {"actor":{},"corpse":{},"projectile":{}}
	var animation := player_animation(_snapshot)
	var seconds := _clock-_attack_started if animation == "attack" else _clock
	if animation == "move": seconds = movement_seconds("garrison_01","player",1.0,seconds)
	var player := _actor_view("player","garrison_01",Vector2(_snapshot.player.position[0],_snapshot.player.position[1]),animation,1.0,float(_snapshot.player.facing[0]) < 0,seconds)
	player.is_player = true
	actors.append(player)
	for entity in _snapshot.get("entities",[]):
		var definition: Dictionary = _snapshot.get("rules",{}).get("enemy_catalog",{}).get(entity.enemy_id,{})
		var asset_id := approved_art_id(str(definition.get("art_id","titan_basic")))
		var action := str(entity.get("action_state","move"))
		var pose: String = {"move":"move","windup":"windup","attack":"attack","airborne":"attack","brake":"idle","recover":"idle"}.get(action,"move")
		if _enemy_hits.has(str(entity.id)): pose = "hit"
		seconds = maxf(0,float(int(_snapshot.active_tick)-int(entity.get("action_started_tick",0)))/60.0)
		# Approved idle/walk remains provisional until dedicated charge poses pass
		# actual contact review. There is no second, screen-only final boss body.
		var actor_scale := 1.5 if asset_id == "armored_titan" else 1.0
		if pose == "move": seconds = movement_seconds(asset_id,"entity:"+str(entity.id),actor_scale,seconds)
		var facing: Array = entity.get("facing",entity.velocity)
		actors.append(_actor_view(entity.id,asset_id,Vector2(entity.position[0],entity.position[1]),pose,actor_scale,float(facing[0]) < 0,seconds))
	for corpse in _corpses:
		corpses.append(_actor_view(corpse.id,corpse.asset,Vector2(corpse.position[0],corpse.position[1]),"death",1.0,false,_clock-float(corpse.started)))
	for projectile in _snapshot.get("projectiles",[]):
		if _projectile_has_drawable_vfx(projectile.id,vfx_commands): continue
		var ally: bool = projectile.item_id == "ally_cover"
		projectiles.append(_actor_view(projectile.id,"garrison_01" if ally else "debris_fx",Vector2(projectile.position[0],projectile.position[1]),"attack",0.8 if ally else 0.35,ally and float(projectile.velocity[0]) < 0,_clock))
	for group in [["actor",actors],["corpse",corpses],["projectile",projectiles]]:
		for record in group[1]: _city_draw_data[group[0]][record.id] = record
	var terrain := _city_view if _city_active else {"stage":"finite"}
	if terrain.stage in ["dock","finite"]:
		var props: Array = []
		for index in _map.get("props",[]).size():
			var prop: Dictionary = _map.props[index]
			var dto := _actor_view("dock:"+str(index),prop.asset_id,Vector2(prop.position[0],prop.position[1]),"idle",1.0,false,_clock)
			dto.prop_id = dto.id
			props.append(dto)
		terrain = {"chunks":[{"chunk_id":"authored_dock","local_origin":Vector2.ZERO,"ground_variant":0,"props":props}]}
	var depth_actors: Array = actors if _city_active else actors.filter(func(actor): return not actor.get("is_player",false))
	return CityDepth.build(terrain,depth_actors,corpses,projectiles,Rect2(_camera-_viewport_size*0.5,_viewport_size))
func _draw_streamed_city() -> void:
	if _city_view.is_empty(): return
	var packet := _city_render_packet()
	if not packet.get("ok",true): return
	if _city_view.stage == "dock": _draw_city()
	else:
		for command in packet.ground:
			if command.kind == "chunk_ground": _draw_city_ground(command)
	var vfx := combat_vfx_commands()
	_draw_vfx_pass(vfx,"ground")
	for drop in _snapshot.get("drops",[]): _sprite("xp_pickup",Vector2(drop.position[0],drop.position[1]),"idle",1.0)
	if _city_view.stage == "dock" and _snapshot.phase == "evacuation":
		var zone: Array = _snapshot.escape_zone
		_sprite("escape_marker",Vector2(zone[0]+zone[2]/2,zone[1]+zone[3]/2),"idle",2.0)
	elif _city_view.stage == "city":
		var passage_position: Variant = selected_passage_world_position()
		if passage_position is Vector2: _sprite("escape_marker",passage_position,"idle",2.0)
	_draw_upright_with_vfx(packet.upright,vfx)
	_draw_vfx_pass(vfx,"contact_overlay")
	_draw_hit_fallbacks()
	_draw_enemy_attacks()
	for marker in packet.visibility_markers:
		var behind := false
		for command in packet.upright:
			if command.id == marker.actor_id: behind = true; continue
			if behind and command.render_bounds.intersects(marker.render_bounds) and _city_rasters_overlap(_city_draw_data.actor["player"],command):
				_draw_player_outline(marker,_city_draw_data.actor["player"])
				break
	# Danger is the final raster pass; a cyan outline never substitutes for it.
	for hazard in _snapshot.get("telegraphs",[]): _draw_telegraph(hazard)
func selected_passage_world_position() -> Variant:
	# Only a committed selection is shown. This is the existing 96px passage
	# center in its absolute chunk, not an invented world-space boss location.
	if _snapshot.get("phase","") != "evacuation": return null
	var world: Dictionary = _snapshot.get("world",{})
	if world.get("stage","") != "city": return null
	var selection: Dictionary = world.get("evacuation",{})
	if not selection.get("chunk") is Array or not CityAddress.parse(selection.chunk).get("ok",false): return null
	if selection.get("passage_id","") != "passage:city_v1:%s:%s" % [selection.chunk[0],selection.chunk[1]]: return null
	var point := CityAddress.relative(selection.chunk,Vector2(384,384),world.get("origin_chunk",[]))
	return point.local if point.get("ok",false) else null
func _draw_vfx_command(command: Dictionary) -> void:
	if command.has("diagnostic"): return
	var texture := _texture(str(command.asset_id))
	if texture == null: return
	_world_transform(_screen(command.world_anchor),float(command.rotation),command.scale)
	_world_region(texture,command.local_rect,command.atlas_region,Color(1,1,1,float(command.alpha)))
	_world_transform(Vector2.ZERO)
func _draw_vfx_pass(commands: Array[Dictionary], pass_name: String) -> void:
	for command in commands:
		if not command.has("diagnostic") and command.render_pass == pass_name: _draw_vfx_command(command)
func _draw_upright_with_vfx(upright: Array, vfx: Array[Dictionary]) -> void:
	var ordered: Array = upright.duplicate()
	for command in vfx:
		if not command.has("diagnostic") and command.render_pass == "world":
			ordered.append({"id":"vfx:"+command.stable_id,"depth_y":command.depth_y,"vfx":command})
	ordered.sort_custom(func(a,b): return a.depth_y < b.depth_y or (a.depth_y == b.depth_y and a.id < b.id))
	for command in ordered:
		if command.has("vfx"):
			_draw_vfx_command(command.vfx)
		else:
			var style: Dictionary = _city_draw_data[command.id.get_slice(":",0)][command.source_id] if command.has("source_id") else {}
			_actor_draw_tint = style.get("tint",Color.WHITE)
			if style.get("armored_raster",false) and _draw_armored_raster():
				_actor_draw_tint = Color.WHITE
				continue
			_sprite(command.asset_id,command.position,command.pose,float(style.get("scale",1.0)),style.get("flip",false),float(style.get("seconds",_clock)))
			_actor_draw_tint = Color.WHITE
func _draw_hit_fallbacks() -> void:
	for effect in _effects:
		_sprite(effect.asset,Vector2(effect.position[0],effect.position[1])-Vector2(0,64),"attack",0.8,_snapshot.player.facing[0] < 0,_clock-float(effect.started))
func _projectile_has_drawable_vfx(projectile_id: Variant, current_commands: Variant = null) -> bool:
	var commands: Array = current_commands if current_commands is Array else combat_vfx_commands()
	for command in commands:
		if not command.has("diagnostic") and command.get("role","") == "projectile" and command.get("component","") == "main" and command.get("projectile_id") == projectile_id: return true
	return false
func _damage_has_drawable_vfx(event: Dictionary) -> bool:
	var current := _combat_snapshot if not _combat_snapshot.is_empty() else _snapshot
	if current.is_empty() or not event.has("tick"): return false
	var payload: Dictionary = event.get("payload",{})
	var target = payload.get("target_id",payload.get("entity_id",null))
	var attack_id := str(payload.get("attack_id",""))
	# A diagnostic record or unrelated/expired effect never removes hit feedback.
	for command in _combat_bridge.present(current,reduce_effects):
		if command.has("diagnostic") or int(command.get("start_tick",-1)) != int(event.tick): continue
		if command.get("target_id") == target and target != null: return true
		if not attack_id.is_empty() and command.get("attack_id","") == attack_id and command.get("role","") in ["cast","impact"]: return true
	return false
func _draw_city_ground(command: Dictionary) -> void:
	var texture := _texture("city_tiles")
	if texture == null: return
	var record: Dictionary = _assets.city_tiles
	var cell := Vector2(record.cell_w,record.cell_h)
	var camera_rect := Rect2(_camera-_viewport_size*0.5,_viewport_size)
	var visible: Rect2 = command.bounds.intersection(camera_rect)
	var start := Vector2i(((visible.position-command.position)/cell).floor())
	var end := Vector2i(((visible.end-command.position)/cell).ceil())
	var columns := int(record.columns)
	var count := int(record.width/record.cell_w)*int(record.height/record.cell_h)
	for y in range(start.y,end.y):
		for x in range(start.x,end.x):
			var index := posmod(int(command.ground_variant)*4+posmod(x*7+y*11,4),count)
			var region := Rect2(Vector2(index%columns,index/columns)*cell,cell)
			_world_region(texture,Rect2(_screen(command.position+Vector2(x,y)*cell),cell),region,Color(0.48,0.56,0.52))
func _player_outline_texture(region: Rect2) -> Texture2D:
	var key := str(region)
	if _outline_textures.has(key): return _outline_textures[key]
	var source := _texture("garrison_01")
	if source == null: return null
	var image := source.get_image().get_region(Rect2i(region))
	var outline := Image.create(image.get_width(),image.get_height(),false,Image.FORMAT_RGBA8)
	# Outline only: derive the contour from approved source alpha, never repaint
	# the opaque body. Cyan separates location feedback from red/yellow danger.
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x,y).a > 0.1: continue
			var edge := false
			for dy in range(-2,3):
				for dx in range(-2,3):
					if x+dx >= 0 and x+dx < image.get_width() and y+dy >= 0 and y+dy < image.get_height() and image.get_pixel(x+dx,y+dy).a > 0.1: edge = true
			if edge: outline.set_pixel(x,y,Color(0.24,0.94,1.0,0.95))
	var texture := ImageTexture.create_from_image(outline)
	_outline_textures[key] = texture
	return texture
func _draw_player_outline(command: Dictionary, style: Dictionary) -> void:
	var region := frame_rect("garrison_01",style.pose,style.seconds)
	var texture := _player_outline_texture(region)
	if texture == null: return
	var anchor: Array = _assets.garrison_01.anchor_px
	_world_transform(_screen(command.position),0,Vector2(-1 if style.flip else 1,1))
	_world_texture(texture,-Vector2(anchor[0],anchor[1]))
	_world_transform(Vector2.ZERO)

func _city_rasters_overlap(player: Dictionary, occluder: Dictionary) -> bool:
	var other: Dictionary = _city_draw_data[occluder.id.get_slice(":",0)][occluder.source_id] if occluder.has("source_id") else {}
	var player_region := frame_rect(player.asset_id,player.pose,player.seconds)
	var other_region := frame_rect(occluder.asset_id,occluder.pose,float(other.get("seconds",_clock)))
	var overlap: Rect2 = player.render_bounds.intersection(occluder.render_bounds)
	for y in range(int(floor(overlap.position.y)),int(ceil(overlap.end.y))):
		for x in range(int(floor(overlap.position.x)),int(ceil(overlap.end.x))):
			var pixel := Vector2(x+0.5,y+0.5)
			if _raster_opaque(player.asset_id,player_region,player.render_bounds,player.flip,pixel) and (_armored_opaque(pixel) if other.get("armored_raster",false) else _raster_opaque(occluder.asset_id,other_region,occluder.render_bounds,other.get("flip",false),pixel)): return true
	return false
func _raster_opaque(asset_id: String, region: Rect2, bounds: Rect2, flip: bool, point: Vector2) -> bool:
	if not bounds.has_point(point) or not region.has_area(): return false
	if not _raster_images.has(asset_id):
		var texture := _texture(asset_id)
		if texture == null: return false
		_raster_images[asset_id] = texture.get_image()
	var local := Vector2i(((point-bounds.position)/bounds.size*region.size).floor())
	if flip: local.x = int(region.size.x)-1-local.x
	return _raster_images[asset_id].get_pixelv(Vector2i(region.position)+local).a > 0.1

# Only known-distance horizontal charge is connected in this candidate. The
# bounds/query/frame pair is derived together from the last accepted snapshot.
func _reset_armored_display() -> void:
	_armored_input_bytes.clear()
	_armored_pose.reset()
	_armored_display = {"supported":false,"reason":"no_actor"}
	if is_instance_valid(_armored_raster): _armored_raster.set_actor_visible(false)
	if is_instance_valid(_armored_split): _armored_split.begin_frame()
func _ensure_armored_resources() -> bool:
	if not is_inside_tree(): return false
	if _armored_setup_attempted: return _armored_setup_error.is_empty()
	_armored_setup_attempted = true
	var path := "res://assets/art/rig/armored_runtime_v1/registration.json"
	var registration = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not registration is Dictionary:
		_armored_setup_error = "registration_unavailable"; return false
	var prepared: Dictionary = _armored_pose.configure(registration)
	if not prepared.get("ok",false):
		_armored_setup_error = str(prepared.get("reason","pose_setup")); return false
	_armored_raster = ArmoredRaster.new()
	add_child(_armored_raster)
	var configured: Dictionary = _armored_raster.configure(registration)
	if not configured.get("ok",false):
		_armored_setup_error = str(configured.get("reason","raster_setup"))
		_armored_raster.free(); _armored_raster = null
		return false
	_armored_raster.set_actor_visible(false)
	_armored_split = ArmoredDrawSplit.new()
	add_child(_armored_split)
	return true
func _sync_armored_display() -> void:
	var actor: Dictionary = {}
	for entity in _snapshot.get("entities",[]):
		if entity.get("enemy_id") == "armored_titan": actor = entity; break
	if actor.is_empty(): _reset_armored_display(); return
	if not _ensure_armored_resources():
		_armored_display = {"supported":false,"reason":_armored_setup_error if not _armored_setup_error.is_empty() else "not_in_tree"}
		return
	var observation: Dictionary = _armored_motion.debug_observation()
	# One owned, type-preserving key; no hash collision or caller aliases. Only
	# a previously accepted packet may bypass duplicate work. Camera state is
	# deliberately outside the key and visibility is always updated below.
	var input_bytes := var_to_bytes([observation,actor])
	if input_bytes == _armored_input_bytes:
		_update_armored_visibility()
		return
	_armored_input_bytes.clear()
	_armored_pose.observe(observation,actor)
	var prepared: Dictionary = _armored_pose.present()
	if not prepared.get("supported",false):
		_armored_display = prepared
		_armored_raster.set_actor_visible(false)
		return
	var transform := Transform2D(0,prepared.root_position).scaled_local(Vector2(-1 if prepared.flip else 1,1)*prepared.display_scale) * Transform2D(0,Vector2(-144,-280))
	var next_bounds: Rect2 = transform * prepared.packet.bounds
	if not next_bounds.intersects(Rect2(_camera-_viewport_size*.5,_viewport_size)):
		_armored_raster.set_actor_visible(false)
	if not _armored_raster.present_packet(prepared.packet):
		_armored_display = {"supported":false,"reason":_armored_raster.last_error}
		_armored_raster.set_actor_visible(false)
		return
	prepared.erase("packet")
	_armored_display = prepared
	_armored_input_bytes = input_bytes
	_update_armored_visibility()
func _update_armored_visibility() -> void:
	if not _armored_display.get("supported",false): return
	var bounds: Rect2 = _armored_world_transform() * _armored_raster.local_bounds()
	_armored_raster.set_actor_visible(bounds.intersects(Rect2(_camera-_viewport_size*.5,_viewport_size)))
func armored_raster_status() -> Dictionary:
	var result := _armored_display.duplicate(true)
	if result.get("supported",false): result.merge(_armored_raster.packet_status())
	result.native_gpu_verified = false
	return result
func _armored_world_transform() -> Transform2D:
	var result := Transform2D(0,_armored_display.root_position).scaled_local(Vector2(-1 if _armored_display.flip else 1,1)*_armored_display.display_scale)
	return result * Transform2D(0,Vector2(-144,-280))
func _armored_opaque(world_point: Vector2) -> bool:
	if not _armored_display.get("supported",false): return false
	return _armored_raster.is_opaque_local(_armored_world_transform().affine_inverse() * world_point)
func _draw_armored_raster() -> bool:
	if not _armored_display.get("supported",false) or not is_instance_valid(_armored_split): return false
	var transform := Transform2D(0,_screen(_armored_display.root_position)).scaled_local(Vector2(-1 if _armored_display.flip else 1,1)*_armored_display.display_scale)
	return _armored_split.insert_actor(_armored_raster.get_raster_texture(),transform,Rect2(-144,-280,288,288),_actor_draw_tint)
func _world_transform(position: Vector2, rotation:=0.0, scale_value:=Vector2.ONE) -> void:
	if is_instance_valid(_armored_split) and _armored_split.routing_tail():
		_armored_split.append_transform(Transform2D(rotation,position).scaled_local(scale_value))
	else: draw_set_transform(position,rotation,scale_value)
func _world_region(texture: Texture2D, rect: Rect2, region: Rect2, color:=Color.WHITE) -> void:
	if is_instance_valid(_armored_split) and _armored_split.routing_tail(): _armored_split.append_region(texture,rect,region,color)
	else: draw_texture_rect_region(texture,rect,region,color)
func _world_rect(texture: Texture2D, rect: Rect2, tiled: bool, color:=Color.WHITE) -> void:
	if is_instance_valid(_armored_split) and _armored_split.routing_tail(): _armored_split.append_rect(texture,rect,tiled,color)
	else: draw_texture_rect(texture,rect,tiled,color)
func _world_texture(texture: Texture2D, position: Vector2, color:=Color.WHITE) -> void:
	_world_rect(texture,Rect2(position,texture.get_size()),false,color)
