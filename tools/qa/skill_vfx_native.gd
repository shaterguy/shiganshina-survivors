extends Node
# Explicit raster-candidate review. No SaveStore, approval edits, or user saves.
const Core = preload("res://game/core/run_simulation.gd")
const City = preload("res://game/director/streamed_chapter_provider.gd")
const World = preload("res://game/presentation/world_view.gd")
const Helper = preload("res://game/core/streamed_run_world.gd")
const Address = preload("res://game/world/world_address.gd")
const Config = preload("res://tests/core/core_fixture.gd")
const CANDIDATE := "res://docs/art/vfx/primary-runtime-candidate.json"
class CandidateBridge:
	extends "res://game/presentation/combat_vfx_bridge.gd"
	var candidate_assets: Dictionary = {}
	var candidate_errors: Array[String] = []
	func install_candidate(value: Dictionary) -> void:
		candidate_assets.clear()
		candidate_errors.clear()
		var catalog = load("res://game/presentation/combat_vfx_catalog.gd").new()
		for id in value.get("assets",{}):
			var record: Dictionary = value.assets[id]
			var errors: Array[String] = catalog.validate_art_metadata(id,record)
			if not errors.is_empty(): candidate_errors.append(str(errors)); continue
			if record.get("vfx_approved") != false: candidate_errors.append(id+":not_unapproved_candidate"); continue
			if FileAccess.get_sha256(record.path) != record.sha256: candidate_errors.append(id+":hash"); continue
			var raster := Image.new()
			if raster.load_png_from_buffer(FileAccess.get_file_as_bytes(record.path)) != OK or raster.get_size() != Vector2i(record.width,record.height): candidate_errors.append(id+":dimensions"); continue
			candidate_assets[id] = record.duplicate(true)
	func present(snapshot: Dictionary, reduce_effects := false, visible_rect := Rect2()) -> Array[Dictionary]:
		# Run the same state synchronization first. No approval bit is changed.
		super.present(snapshot,reduce_effects,visible_rect)
		var output: Array[Dictionary] = []
		var actors := {"player":_vec(snapshot.player.position)}
		for entity in snapshot.get("entities",[]): actors["entity:"+str(entity.id)] = _vec(entity.position)
		var context := {"tick":int(snapshot.active_tick),"origin_revision":int(snapshot.world.origin_revision),"actor_positions":actors}
		for effect in _director.present(snapshot):
			for index in effect.get("layers",[]).size():
				var layer: Dictionary = effect.layers[index]
				var id: String = layer.art_id
				if not candidate_assets.has(id): continue
				if reduce_effects and layer.get("reduce_mode") == "omit": continue
				var command: Dictionary = _renderer._command(effect,layer,str(layer.get("component","main")),candidate_assets[id],int(snapshot.active_tick),context,index)
				if not command.has("diagnostic") and (not visible_rect.has_area() or visible_rect.intersects(command.world_bounds)):
					output.append(command)
		return output

var simulation
var state: Dictionary
var world
var bridge
var _caption: Label
var _accumulator := 0.0
var _paused := true
var _contact_stop := false
var _portrait := false
var _limit := 1200
var _spawn_id := 0
var _mode := 4
var _contact_count := 0
var _error := ""
var _trace: FileAccess
var _terrain_key := ""
var _terrain: Dictionary = {}
var _held_directions: Dictionary = {}
func _ready() -> void:
	var provider := City.new()
	var chapter: Dictionary = provider.load_chapter("chapter_01_shiganshina").chapter
	simulation = Core.new(provider)
	state = simulation.new_run(chapter,42,Config.run_config())
	state.player.position = [384.0,384.0]
	if not _prepare([]).get("ok",false): _error = "prepare_world"; return
	world = World.new()
	add_child(world)
	bridge = CandidateBridge.new()
	var candidate = JSON.parse_string(FileAccess.get_file_as_string(CANDIDATE))
	if not candidate is Dictionary: _error = "missing candidate"; return
	bridge.install_candidate(candidate)
	world._combat_bridge = bridge
	# The manifest remains untouched; only this labelled QA view can read these.
	world._assets.merge(bridge.candidate_assets,true)
	_set_equipment(4)
	var layer := CanvasLayer.new()
	layer.layer = 40
	add_child(layer)
	_caption = Label.new()
	_caption.position = Vector2(8,8)
	_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_caption.add_theme_font_size_override("font_size",12)
	_caption.add_theme_color_override("font_color",Color(1,0.9,0.3))
	layer.add_child(_caption)
	var directory := ProjectSettings.globalize_path("res://.qa/skill-vfx")
	DirAccess.make_dir_recursive_absolute(directory)
	_trace = FileAccess.open(directory.path_join("candidate-%d.jsonl" % Time.get_unix_time_from_system()),FileAccess.WRITE)
	if _trace != null:
		var hashes := {}
		for id in bridge.candidate_assets: hashes[id] = bridge.candidate_assets[id].sha256
		_trace.store_line(JSON.stringify({"source_sha256":get_script().source_code.sha256_text(),"candidate_sha256":FileAccess.get_sha256(CANDIDATE),"asset_sha256":hashes,"approval":"unapproved QA candidates","hp_refill":true}))
		_trace.flush()
	_present()
func _set_equipment(mode: int) -> void:
	_mode = mode
	state.equipment = {"blade_slash":1} if mode == 1 else ({"spin_slash":1} if mode == 2 else ({"wall_cannon":1} if mode == 3 else {"blade_slash":1,"spin_slash":1,"wall_cannon":1}))
	state.player.attack_ready_ticks = {}
	for id in state.equipment: state.player.attack_ready_ticks[id] = int(state.active_tick)+1
func _process(delta: float) -> void:
	if world == null: return
	if not _paused and _error.is_empty():
		_accumulator += minf(delta,0.1)
		var count := 0
		while _accumulator >= 1.0/60.0 and count < 8 and not _paused:
			_step()
			_accumulator -= 1.0/60.0
			count += 1
	_present()
func _step() -> void:
	var commands: Array[Dictionary] = []
	if state.entities.size() < 3:
		for offset in [Vector2(42,0),Vector2(-60,25),Vector2(160,-35)]:
			var position: Vector2 = Vector2(state.player.position[0],state.player.position[1])+offset
			var checked: Dictionary = simulation._streamed.walkable(position,24.0)
			if not checked.get("ok",false) or not checked.get("walkable",false): continue
			_spawn_id += 1
			commands.append({"command_id":"qa:spawn:"+str(_spawn_id),"kind":"spawn_enemy","origin_revision":state.world.origin_revision,"payload":{"entity_id":_spawn_id,"enemy_id":"brute","position":[position.x,position.y],"spawned_tick":state.active_tick}})
	# Survival aid only: actual collision, attack timing and geometry still run.
	state.player.hp = state.player.max_hp
	for entity in state.entities: entity.hp = entity.max_hp
	var move := Vector2(float(_held_directions.get(KEY_RIGHT,false))-float(_held_directions.get(KEY_LEFT,false)),float(_held_directions.get(KEY_DOWN,false))-float(_held_directions.get(KEY_UP,false))).limit_length()
	var events: Array[Dictionary] = simulation.step(state,move,commands)
	var status: Dictionary = simulation.step_status()
	if status.get("error_code") == "world_not_ready" and _prepare(commands).get("ok",false):
		events = simulation.step(state,move,commands)
		status = simulation.step_status()
	if not status.get("ok",false): _error = str(status); _paused = true; return
	var snapshot: Dictionary = simulation.snapshot(state)
	world.consume_combat_events(events,snapshot)
	world.consume_events(events)
	for event in events:
		if event.type == "player_attack" and event.payload.phase == "executed":
			_contact_count += 1
			if _contact_stop: _paused = true; _contact_stop = false
	if _trace != null and (not events.is_empty() or int(state.active_tick)%60 == 0):
		_trace.store_line(JSON.stringify({"tick":state.active_tick,"events":events,"candidates":bridge.candidate_assets.keys(),"mode":_mode,"position":state.player.position,"origin":state.world.origin_chunk,"origin_revision":state.world.origin_revision,"visual_commands":world.combat_vfx_commands(snapshot).size()}))
		_trace.flush()
	if int(state.active_tick) >= _limit: _paused = true
func _prepare(commands: Array) -> Dictionary:
	var required := Helper.requirements(state,commands)
	if not required.get("ok",false): return required
	var hydration := {}
	# This isolated scene starts a new pristine city; every requested chunk has
	# an explicit empty delta. It never substitutes absence for disk read failure.
	for chunk in required.chunks: hydration[Address.key(chunk)] = []
	return simulation.prepare_world(state,hydration,commands)
func _present() -> void:
	var status: Dictionary = simulation.world_status()
	var key := str([status.get("coverage_revision"),status.get("world_revision"),state.world.origin_chunk,state.world.origin_revision])
	if key != _terrain_key:
		_terrain_key = key
		_terrain = simulation.world_render_view(state)
		_terrain.world_revision = status.get("world_revision",state.world.world_revision)
	var shown: Dictionary = world.present_city(simulation.snapshot(state),_terrain)
	if not shown.get("ok",false): _error = str(shown); _paused = true
	_caption.text = "미승인 VFX 후보 · 실제 Core · 체력회복 검수 · 저장없음\nSpace 재생/정지 · C 다음접촉정지 · J 1틱 · 1쌍검 2회전 3포격 4함께 · F11화면비 · E효과축소\n%0.2f초 / 접촉%d · 모드%d · %s · 후보%d · %s" % [state.active_tick/60.0,_contact_count,_mode,"정지" if _paused else "재생",bridge.candidate_assets.size(),_error if not _error.is_empty() else str(bridge.candidate_errors)]
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_held_directions.clear()
		_paused = true
func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or state.is_empty(): return
	var code: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
	if code in [KEY_LEFT,KEY_RIGHT,KEY_UP,KEY_DOWN]:
		_held_directions[code] = event.pressed
		get_viewport().set_input_as_handled()
		return
	if not event.pressed or event.echo: return
	match event.keycode:
		KEY_SPACE:
			_paused = not _paused
			if int(state.active_tick) >= _limit: _limit = int(state.active_tick)+1200
		KEY_C: _contact_stop = true; _paused = false; _limit = int(state.active_tick)+1200
		KEY_J: _paused = true; _step()
		KEY_1: _set_equipment(1)
		KEY_2: _set_equipment(2)
		KEY_3: _set_equipment(3)
		KEY_4: _set_equipment(4)
		KEY_E: world.reduce_effects = not world.reduce_effects
		KEY_F11:
			_portrait = not _portrait
			get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
			get_window().content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
			get_window().content_scale_size = Vector2i(450,800) if _portrait else Vector2i(800,450)
	_present()
