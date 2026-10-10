class_name WorldView
extends Node2D
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
func reset_presentation() -> void:
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
	if manifest is Dictionary: _assets = manifest.get("assets",{})
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
	_update_gait(snapshot)
	_snapshot = snapshot
	if not snapshot.is_empty(): _camera = Vector2(snapshot.player.position[0],snapshot.player.position[1])
	queue_redraw()
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
	var key: Array = [snapshot.get("seed",0),snapshot.get("chapter_id",""),snapshot.get("content_revision","")]
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
func consume_events(events: Array[Dictionary]) -> void:
	for event in events:
		if event.type == "damage" and str(event.payload.get("target_id","")) == "player":
			_shake_until = _clock+0.18
			_hit_until = _clock+0.18
		if event.type == "damage" and str(event.payload.get("target_id", "")) != "player":
			_enemy_hits[str(event.payload.target_id)] = _clock+0.14
			if _clock >= _attack_until: _attack_started = _clock
			_attack_until = _clock + 0.28
			for enemy in _snapshot.get("entities",[]):
				if str(enemy.id) == str(event.payload.get("target_id","")) and _effects.size() < 32:
					if float(event.payload.get("hp",1)) <= 0 and _corpses.size() < 24:
						var art_id := str(_snapshot.get("rules",{}).get("enemy_catalog",{}).get(enemy.enemy_id,{}).get("art_id","titan_basic"))
						_corpses.append({"asset":approved_art_id(art_id),"position":enemy.position.duplicate(),"started":_clock})
					_effects.append({"position":enemy.position.duplicate(),"started":_clock,"asset":"impact_fx" if event.payload.get("source_id","") == "wall_cannon" else "slash_fx"})
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
	if not ResourceLoader.exists(path): return null
	var texture = load(path)
	if texture is Texture2D:
		_textures[asset_id] = texture
		return texture
	return null
func _screen(world: Vector2) -> Vector2:
	var shake := Vector2.ZERO
	if _clock < _shake_until and not reduce_effects: shake = Vector2(sin(_clock*101),cos(_clock*83))*screen_shake*4
	return world-_camera+_viewport_size*0.5+shake
func _draw() -> void:
	_draw_city()
	if _snapshot.is_empty():
		var intro := _texture("colossal_intro")
		if intro != null:
			var factor := maxf(_viewport_size.x/640.0,_viewport_size.y/360.0)
			var target := Vector2(640,360)*factor
			draw_texture_rect(intro,Rect2((_viewport_size-target)*0.5,target),false)
		return
	_draw_props()
	for hazard in _snapshot.get("telegraphs",[]): _draw_telegraph(hazard)
	for drop in _snapshot.get("drops",[]):
		_sprite("xp_pickup",Vector2(drop.position[0],drop.position[1]),"idle",1.0)
	# Large final threat is scenery-priority; the small playable soldier must
	# remain visible even where the giant's opaque torso overlaps its sprite.
	if _snapshot.phase == "evacuation":
		var zone: Array = _snapshot.escape_zone
		_sprite("armored_titan",Vector2(zone[0]+zone[2]/2,zone[1]-220),"idle",1.5)
		_sprite("escape_marker",Vector2(zone[0]+zone[2]/2,zone[1]+zone[3]/2),"idle",2.0)
	for corpse in _corpses:
		_sprite(corpse.asset,Vector2(corpse.position[0],corpse.position[1]),"death",1.0,false,_clock-float(corpse.started))
	var entities: Array = _snapshot.get("entities",[]).duplicate()
	entities.sort_custom(func(a,b): return a.position[1] < b.position[1])
	for entity in entities:
		var definition: Dictionary = _snapshot.get("rules",{}).get("enemy_catalog",{}).get(entity.enemy_id,{})
		var asset_id := str(definition.get("art_id","titan_basic"))
		asset_id = approved_art_id(asset_id)
		var action := str(entity.get("action_state","move"))
		var animation_name: String = {"move":"move","windup":"windup","attack":"attack","airborne":"attack","recover":"idle"}.get(action,"move")
		if _enemy_hits.has(str(entity.id)): animation_name = "hit"
		var seconds := maxf(0,float(int(_snapshot.active_tick)-int(entity.get("action_started_tick",0)))/60.0)
		if animation_name == "move": seconds = movement_seconds(asset_id,"entity:"+str(entity.id),1.0,seconds)
		var facing: Array = entity.get("facing",entity.velocity)
		_sprite(asset_id,Vector2(entity.position[0],entity.position[1]),animation_name,1.0,float(facing[0]) < 0,seconds)
	for projectile in _snapshot.get("projectiles",[]):
		var pos := Vector2(projectile.position[0],projectile.position[1])
		if projectile.item_id == "ally_cover":
			_sprite("garrison_01",pos,"attack",0.8,float(projectile.velocity[0]) < 0)
		else: _sprite("debris_fx",pos,"attack",0.35)
	var position_data: Array = _snapshot.player.position
	var animation := player_animation(_snapshot)
	var player_seconds := _clock-_attack_started if animation == "attack" else _clock
	if animation == "move": player_seconds = movement_seconds("garrison_01","player",1.0,player_seconds)
	_sprite("garrison_01",Vector2(position_data[0],position_data[1]),animation,1.0,float(_snapshot.player.facing[0]) < 0,player_seconds)
	for effect in _effects:
		_sprite(effect.asset,Vector2(effect.position[0],effect.position[1])-Vector2(0,64),"attack",0.8,_snapshot.player.facing[0] < 0,_clock-float(effect.started))
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
	draw_set_transform(_screen(Vector2(origin[0],origin[1])),angle)
	var active := int(_snapshot.active_tick) >= int(hazard.active_from_tick)
	var alpha := 0.98 if active else (0.70 if reduce_effects else 0.65 + 0.12*sin(_clock*7.0))
	for piece in telegraph_pieces(hazard):
		draw_set_transform(_screen(Vector2(origin[0],origin[1])),angle+float(piece.get("rotation",0)))
		var texture := _texture(piece.asset)
		if texture != null: draw_texture_rect_region(texture,piece.rect,piece.region,Color(1,1,1,alpha))
	draw_set_transform(Vector2.ZERO)
func _sprite(asset_id: String, world: Vector2, animation: String, scale_value: float, flip := false, seconds := -1.0) -> void:
	var texture := _texture(asset_id)
	if texture == null: return
	var region := frame_rect(asset_id,animation,_clock if seconds < 0 else seconds)
	var anchor: Array = _assets[asset_id].get("anchor_px",[region.size.x/2,region.size.y])
	draw_set_transform(_screen(world),0,Vector2(-1 if flip else 1,1)*scale_value)
	draw_texture_rect_region(texture,Rect2(-Vector2(anchor[0],anchor[1]),region.size),region)
	draw_set_transform(Vector2.ZERO)
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
			if tile_texture != null: draw_texture_rect_region(tile_texture,Rect2(_screen(world),Vector2(cell,cell)),region,tint)

func _draw_props() -> void:
	for prop in _map.get("props",[]):
		var world := Vector2(prop.position[0],prop.position[1])
		var point := _screen(world)
		if point.x < -210 or point.x > _viewport_size.x+210 or point.y < -20 or point.y > _viewport_size.y+210: continue
		_sprite(str(prop.asset_id),world,"idle",1.0)
