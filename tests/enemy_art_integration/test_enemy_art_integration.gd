extends RefCounted
const F = preload("res://tests/core/core_fixture.gd")
const G = preload("res://tests/core/test_live_grabber.gd")
const HF = preload("res://tests/core_world/new_streamed_helper_fixture.gd")
const H = preload("res://game/core/streamed_run_world.gd")
# The headless drawing boundary records actual loaded ImageTexture/regions.
# Selection, simulation, city commands, anchors and sprite transforms are real.
class Capture extends "res://game/presentation/world_view.gd":
	var pixels: Array = []
	var captured_transform := Transform2D.IDENTITY
	func _world_transform(point: Vector2, angle := 0.0, scale_value := Vector2.ONE) -> void:
		captured_transform = Transform2D(angle,point).scaled_local(scale_value)
	func _world_region(texture: Texture2D, rect: Rect2, region: Rect2, color := Color.WHITE) -> void:
		var asset := ""
		for id in _textures:
			if _textures[id] == texture: asset = id; break
		pixels.append({"asset":asset,"rect":rect,"region":region,"image":texture.get_image().get_region(Rect2i(region)),"transform":captured_transform,"color":color})
	func _world_rect(_texture: Texture2D, _rect: Rect2, _tiled: bool, _color := Color.WHITE) -> void: pass
	func capture() -> void:
		pixels.clear(); _draw()
func run(t) -> void:
	var view := Capture.new(); view.load_manifest()
	for id in ["titan_quadruped","titan_stone_thrower","enemy_stone_projectile"]:
		t.check(view.approved_art_id(id) == id,"new development registration selects dedicated art: "+id)
		t.check(view._texture(id) != null,"actual PNG resource decodes for "+id)
	if not view._assets.has_all(["titan_quadruped","titan_stone_thrower","enemy_stone_projectile"]): view.free(); return
	_frames(t,view)
	_packaging(t,view)
	view.free()
	for city in [false,true]:
		for role in ["quadruped","stone_thrower"]:
			for side in [-1.0,1.0]: _lifecycle(t,role,side,city)
	_movement(t)
	_wall(t)
func _frames(t,view) -> void:
	for item in [["titan_quadruped",144,96],["titan_stone_thrower",192,176]]:
		var id: String = item[0]; var w: int = item[1]; var h: int = item[2]
		t.check(view.frame_rect(id,"move",0.0) == Rect2(0,0,w,h),"two-pose movement begins at source A")
		t.check(view.frame_rect(id,"move",1.0/6.0) == Rect2(w,0,w,h),"two-pose movement changes to source B at 6fps")
		t.check(view.frame_rect(id,"move",2.0/6.0) == Rect2(0,0,w,h),"two-pose loop never invents more movement frames")
		for pose in ["idle","recover","hit","death"]:
			t.check(view.frame_rect(id,pose,9.0) == Rect2(4*w,0,w,h),"explicit recovery reuse remains one still: "+id+":"+pose)
func _fixture(t,role: String,side: float,city: bool,far := false) -> Dictionary:
	var f: Dictionary
	var base := Vector2.ZERO
	if city:
		var provider = load("res://game/director/streamed_chapter_provider.gd").new()
		var chapter: Dictionary = provider.load_chapter("chapter_01_shiganshina").chapter
		var core = load("res://game/core/run_simulation.gd").new(provider)
		f = {"sim":core,"state":core.new_run(chapter,42,F.run_config())}
		base = Vector2(384,384); f.state.player.position = [base.x,base.y]
		f.state.player.attack_ready_ticks = {"blade_slash":2147483647}
	else: f = G.setup()
	var distance := 500.0 if far else (140.0 if role == "quadruped" else 240.0)
	var point := base+Vector2(side*distance,0)
	var command := G.spawn(71,[point.x,point.y],role)
	if city:
		command.origin_revision = f.state.world.origin_revision
		t.check(f.sim.prepare_world(f.state,HF.hydration(H.requirements(f.state,[command])),[command]).get("ok",false),"real city geometry admits ordinary role spawn")
	F.step(f.sim,f.state,Vector2.ZERO,[command])
	t.check(f.state.entities.size() == 1,"actual Core supplies the ordinary actor")
	return f
func _present(t,view,f: Dictionary,city: bool) -> void:
	var before: Dictionary = f.state.duplicate(true)
	if city:
		var terrain: Dictionary = f.sim.world_render_view(f.state)
		terrain.world_revision = f.sim.world_status().get("world_revision",f.state.world.world_revision)
		t.check(view.present_city(f.sim.snapshot(f.state),terrain).get("ok",false),"actual Core derived city is accepted")
	else: view.present(f.sim.snapshot(f.state))
	t.check(view.present_enemy_attacks(f.sim.enemy_attack_view(f.state)).get("ok",false),"actual Core attack packet is accepted")
	view.capture()
	t.check(f.state == before,"real pixel/command adapter never mutates Core authority")
func _assert_actor(t,view,f: Dictionary,role: String,frame: int,side: float) -> void:
	var aid := "titan_quadruped" if role == "quadruped" else "titan_stone_thrower"
	var size := Vector2(144,96) if role == "quadruped" else Vector2(192,176)
	var anchor := Vector2(64,88) if role == "quadruped" else Vector2(72,168)
	var drawn: Array = view.pixels.filter(func(p): return p.asset == aid)
	t.check(drawn.size() == 1,"full finite/city traversal emits one dedicated body: "+role)
	if drawn.size() != 1: return
	var p: Dictionary = drawn[0]; var expected_region := Rect2(frame*size.x,0,size.x,size.y)
	t.check(p.region == expected_region and p.rect == Rect2(-anchor,size),"actual phase uses exact frame cell and authored ground anchor")
	var source := Image.new(); source.load_png_from_buffer(FileAccess.get_file_as_bytes(view._assets[aid].path))
	t.check(p.image.get_data() == source.get_region(Rect2i(expected_region)).get_data(),"emitted body pixel bytes equal registered packed PNG cell")
	var actor: Dictionary = f.state.entities[0];var point := Vector2(actor.position[0],actor.position[1])
	t.check(p.transform.origin == view._screen(point),"real actor position fixes ground origin")
	t.check(p.transform.x == Vector2(-1,0) if side > 0 else p.transform.x == Vector2(1,0),"left/right facing mirrors around the authored anchor at scale 1")
	var body: Dictionary = view._city_draw_data.actor[71]
	var corner_x: float = anchor.x-size.x if side > 0 else -anchor.x
	t.check(body.render_bounds == Rect2(point+Vector2(corner_x,-anchor.y),size),"depth/culling bounds share the same asymmetrical mirrored anchor")
func _lifecycle(t,role: String,side: float,city: bool) -> void:
	var f := _fixture(t,role,side,city)
	t.check(f.state.enemy_attack_instances.size() == 1,"real ordinary role begins W/A/R")
	if f.state.enemy_attack_instances.is_empty(): return
	var end := int(f.state.enemy_attack_instances[0].recover_ends_tick)
	var view := Capture.new();view.load_manifest();view._viewport_size = Vector2(1600,900)
	var seen := {}; var visible_rock := false
	for tick in range(1,end+1):
		if tick > 1: F.step(f.sim,f.state,Vector2.ZERO)
		var actor: Dictionary = f.state.entities[0];var phase: String = actor.action_state
		if not phase in ["windup","attack","recover"] or seen.has(phase): continue
		seen[phase] = true;_present(t,view,f,city)
		_assert_actor(t,view,f,role,{"windup":2,"attack":3,"recover":4}[phase],side)
		var attacks: Dictionary = f.sim.enemy_attack_view(f.state)
		var pose: Dictionary = attacks.attacks[0].get("projectile_pose",{})
		var rocks: Array = view.pixels.filter(func(p): return p.asset == "enemy_stone_projectile")
		t.check(rocks.size() == (1 if pose.get("visible",false) else 0),"separate rock is rendered only in actual visible phase")
		if rocks.size() == 1:
			visible_rock = true;var rock: Dictionary = rocks[0]
			t.check(rock.region == Rect2(0,0,16,16) and rock.rect == Rect2(-8,-8,16,16),"dedicated stone uses one centered cell")
			var source_rock := Image.new()
			source_rock.load_png_from_buffer(FileAccess.get_file_as_bytes(view._assets.enemy_stone_projectile.path))
			t.check(rock.image.get_data() == source_rock.get_data(),"emitted stone pixel bytes equal exact registered source PNG")
			t.check(rock.transform.origin == view._screen(Vector2(pose.current[0],pose.current[1])) and rock.transform.x == Vector2(0.875,0) and rock.transform.y == Vector2(0,0.875),"actual rock center/radius map to 14px draw diameter")
			t.check(not view.enemy_attack_commands().filter(func(c): return c.kind == "projectile")[0].has("diagnostic"),"registered rock exits missing-art diagnostic")
		t.check(not view.pixels.any(func(p): return p.asset == "titan_basic"),"distinct role never silently falls back to generic body")
	t.check(seen.has_all(["windup","attack","recover"]),"real Core traverses all registered poses in finite and prepared city")
	if role == "stone_thrower":t.check(visible_rock,"actual throw reaches separate stone emission")
	_present(t,view,f,city)
	t.check(view.enemy_attack_commands().is_empty() and not view.pixels.any(func(p): return p.asset == "enemy_stone_projectile"),"finished attack leaves no stone command/pixels")
	view.free()
func _movement(t) -> void:
	for role in ["quadruped","stone_thrower"]:
		var f := _fixture(t,role,1.0,false,true);var view := Capture.new();view.load_manifest();view._viewport_size = Vector2(1600,900)
		var seen := {}
		for tick in range(1,22):
			if tick > 1:F.step(f.sim,f.state,Vector2.ZERO)
			_present(t,view,f,false)
			var aid: String = "titan_quadruped" if role == "quadruped" else "titan_stone_thrower"
			for p in view.pixels:
				if p.asset == aid:seen[int(p.region.position.x/p.region.size.x)] = true
		t.check(seen.keys().size() == 2 and seen.has_all([0,1]),"actual moving Core uses only two authored walk images: "+role)
		view.free()
func _wall(t) -> void:
	var encounter = load("res://tests/titan_encounters/test_distinct_attacks.gd")
	var provider = encounter.GeometryProvider.new({"bounds":[-500,-500,1000,1000],"obstacles":[[-30,-120,20,240]]})
	var core = load("res://game/core/run_simulation.gd").new(provider)
	var f := {"sim":core,"state":core.new_run(provider.chapter,42,F.run_config())}
	f.state.player.attack_ready_ticks = {"blade_slash":2147483647}
	F.step(core,f.state,Vector2.ZERO,[G.spawn(71,[-240.0,0.0],"stone_thrower")])
	var view := Capture.new();view.load_manifest();var blocked := false
	for tick in range(2,int(f.state.enemy_attack_instances[0].recover_ends_tick)):
		F.step(core,f.state,Vector2.ZERO)
		var packet: Dictionary = core.enemy_attack_view(f.state)
		if packet.attacks.is_empty() or not packet.attacks[0].projectile_pose.blocked:continue
		blocked = true;_present(t,view,f,false)
		t.check(not view.pixels.any(func(p): return p.asset == "enemy_stone_projectile"),"wall-blocked registered rock never produces ghost pixels")
	t.check(blocked and f.state.player.hp == f.state.player.max_hp,"registered art preserves actual wall collision authority")
	view.free()

func _packaging(t,view) -> void:
	var readiness = load("res://tools/build/export_readiness.gd").new()
	for aid in ["titan_quadruped","titan_stone_thrower","enemy_stone_projectile"]:
		t.check(readiness.is_runtime_asset_path(view._assets[aid]),"Godot packaging accepts exact reviewed enemy PNG: "+aid)
	for mutation in [["enemy_art_development_ready",false],["enemy_art_development_ready",1],["export_blocked",true],["kind","effect"],["packing_profile","unreviewed"],["path","res://assets/art/characters/enemy_diversity_v1/titan_quadruped_00.png"],["path","res://assets/art/characters/enemy_diversity_v1/source/titan_quadruped.png"]]:
		var record: Dictionary = view._assets.titan_quadruped.duplicate(true)
		record[mutation[0]] = mutation[1]
		t.check(not readiness.is_runtime_asset_path(record),"Godot predicate rejects unreviewed or expanded enemy path")
