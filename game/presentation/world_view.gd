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
	_snapshot = snapshot
	if not snapshot.is_empty(): _camera = Vector2(snapshot.player.position[0],snapshot.player.position[1])
	queue_redraw()
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
		_sprite("armored_titan",Vector2(zone[0]+zone[2]/2,zone[1]-220),"move",1.5)
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
		var facing: Array = entity.get("facing",entity.velocity)
		_sprite(asset_id,Vector2(entity.position[0],entity.position[1]),animation_name,1.0,float(facing[0]) < 0,seconds)
	for projectile in _snapshot.get("projectiles",[]):
		var pos := Vector2(projectile.position[0],projectile.position[1])
		if projectile.item_id == "ally_cover":
			_sprite("garrison_01",pos,"attack",0.8,float(projectile.velocity[0]) < 0)
		else: _sprite("debris_fx",pos,"attack",0.35)
	var position_data: Array = _snapshot.player.position
	var animation := player_animation(_snapshot)
	_sprite("garrison_01",Vector2(position_data[0],position_data[1]),animation,1.0,float(_snapshot.player.facing[0]) < 0, _clock-_attack_started if animation == "attack" else _clock)
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
