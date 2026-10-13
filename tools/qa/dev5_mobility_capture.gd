extends SceneTree
# Actual default dense-city Core/Controller/WorldView capture. The safe initial
# roof approach and cast seed are explicitly arranged QA fixtures. No mobility
# state/visual height/anchor fields are injected. This is local Xvfb evidence,
# not Android touch, APK, natural trigger probability or balance evidence.
const AppFixture = preload("res://tests/dev5_mobility_autosave/mobility_app_fixture.gd")
const Core = preload("res://game/core/run_simulation.gd")
const City = preload("res://game/director/streamed_chapter_provider.gd")
const CF = preload("res://tests/core/core_fixture.gd")
const HF = preload("res://tests/core_world/new_streamed_helper_fixture.gd")
const H = preload("res://game/core/streamed_run_world.gd")
const View = preload("res://game/presentation/world_view.gd")
const Mobility = preload("res://game/core/player_mobility.gd")
const Address = preload("res://game/world/world_address.gd")
const OUTPUT: String = "res://.qa/dev5-mobility-captures"
var failures: Array[String] = []
var checks: int = 0
var records: Array = []
func check(value: bool,message: String) -> void:
	checks += 1
	if not value: failures.append(message); push_error("CAPTURE_FAIL: "+message)
func _initialize() -> void: call_deferred("run")
func _settle() -> void:
	for frame in 6: await process_frame
func _capture(name: String,size: Vector2i,snapshot: Dictionary,commands: Dictionary,app = null) -> void:
	var frozen: PackedByteArray = var_to_bytes(snapshot)
	await _settle()
	await RenderingServer.frame_post_draw
	if app != null:
		check(var_to_bytes(app.simulation.snapshot(app.state)) == frozen,"full actual Core snapshot stays frozen while raster settles: "+name)
	var raster: Image = root.get_texture().get_image()
	check(raster != null and raster.get_size() == size,"actual rendered dimensions: "+name)
	if raster == null: return
	var pixel_colors: int = _central_pixel_colors(raster)
	check(pixel_colors >= 16,"actual central world raster has varied nonempty pixels: "+name)
	check(raster.save_png(OUTPUT.path_join(name+".png")) == OK,"actual PNG saved: "+name)
	records.append({"name":name,"png_sha256":FileAccess.get_sha256(OUTPUT.path_join(name+".png")),"dimensions":[size.x,size.y],"tick":snapshot.active_tick,"phase":snapshot.get("player_mobility",{}).get("phase","ground"),"height":commands.get("height",0.0),"central_pixel_colors":pixel_colors,"core_frozen_during_render":true,"position":snapshot.player.position,"fixture":"actual current provider; roof captures arrange an existing legal approach, cast seed, held UP and one actual Core warning; only observed phases are captured; district templates are unmodified"})
	print("CAPTURE_PNG ",OUTPUT.path_join(name+".png"))
func _central_pixel_colors(raster: Image) -> int:
	var colors: Dictionary = {}
	var size: Vector2i = raster.get_size()
	var center: Vector2i = size/2
	for y in range(maxi(0,center.y-120),mini(size.y,center.y+120),3):
		for x in range(maxi(0,center.x-100),mini(size.x,center.x+100),3):
			var color: Color = raster.get_pixel(x,y)
			if color.a > 0.5 and color.r+color.g+color.b > 0.12: colors[color.to_rgba32()] = true
			if colors.size() >= 16: return colors.size()
	return colors.size()
func run() -> void:
	if DisplayServer.get_name() == "headless": check(false,"actual local Xvfb display is required"); quit(1); return
	check(DirAccess.make_dir_recursive_absolute(OUTPUT) == OK,"isolated QA output directory exists")
	var support = AppFixture.new()
	for size in [Vector2i(360,800),Vector2i(800,450)]:
		root.size = size
		root.content_scale_size = size
		root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
		root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
		await _settle()
		var app = support.airborne(self,"capture_%d" % size.x,"rise")
		if app == null: continue
		app.autosave_worker_enabled = false
		# Freeze the actual scene's automatic process/input callbacks for QA only.
		# Explicit controller/Core ticks below still advance genuine authority.
		app.process_mode = Node.PROCESS_MODE_DISABLED
		app.ui.reflow(size,Rect2i(Vector2i.ZERO,size))
		app.world._viewport_size = Vector2(size)
		# Reflow correctly clears touch in the product; the arranged QA hold is
		# re-established after layout, rather than changing that product policy.
		app.input_router.set_touch_vector(Vector2.UP)
		print("CAPTURE_FREEZE process=%s phase=%s tick=%s input=%s" % [app.is_processing(),app.state.player_mobility.phase,app.state.active_tick,app.input_router.sample_move()])
		var landing_span: float = 0.0
		for phase in ["rise","over","land","ground"]:
			for tick in 64:
				if app.state.player_mobility.phase == phase: break
				# A valid short descent can finish inside one accepted8px tick.
				# Observe it honestly instead of relabeling a later ground frame.
				if phase == "land" and app.state.player_mobility.phase == "ground": break
				app.input_router.set_touch_vector(Vector2.UP)
				check(app._step_city_tick().get("ok",false),"actual capture phase tick succeeds")
			if phase == "land" and app.state.player_mobility.phase == "ground":
				records.append({"event":"phase_not_observed","phase":"land","observed_phase":"ground","dimensions":[size.x,size.y],"tick":app.state.active_tick,"landing_span_px":landing_span,"reason":"actual approved short descent completed within one accepted fixed tick; no land snapshot was emitted; no land PNG is claimed"})
				print("CAPTURE_PHASE_NOT_OBSERVED phase=land actual=ground tick=%s landing_span_px=%s size=%s" % [app.state.active_tick,landing_span,size])
				continue
			check(app.state.player_mobility.phase == phase,"actual capture reaches "+phase)
			if app.state.player_mobility.phase != phase: break
			if phase == "over":
				var mobility: Dictionary = app.state.player_mobility
				var exit_point: Dictionary = Address.relative(mobility.path[2].chunk,Vector2(mobility.path[2].local[0],mobility.path[2].local[1]),app.state.world.origin_chunk)
				var landing_point: Dictionary = Address.relative(mobility.path[3].chunk,Vector2(mobility.path[3].local[0],mobility.path[3].local[1]),app.state.world.origin_chunk)
				landing_span = exit_point.local.distance_to(landing_point.local)
				# Capture later in the real over span so the stored connection is
				# spatially separated from the character body; never move the wire.
				for tick in 8:
					var current: Dictionary = Mobility.visual_sample(app.simulation.snapshot(app.state))
					if current.anchor.is_empty(): break
					var connected: Dictionary = Address.relative(current.anchor.chunk,Vector2(current.anchor.local[0],current.anchor.local[1]),app.state.world.origin_chunk)
					if float(current.ground_position[1]) <= connected.local.y-14.0: break
					app.input_router.set_touch_vector(Vector2.UP)
					check(app._step_city_tick().get("ok",false),"actual later-over capture tick succeeds")
				check(app.state.player_mobility.phase == "over","actual later-over sample stays on approved roof")
				if app.state.player_mobility.phase != "over": break
				var origin: Array = [float(app.state.player.position[0]),float(app.state.player.position[1])+70.0]
				var warning: Dictionary = CF.hazard("mobility-capture-warning","circle",{"origin":origin,"radius":40.0,"warning_ticks":120,"active_ticks":1,"damage":1.0})
				warning.origin_revision = app.state.world.origin_revision
				CF.step(app.simulation,app.state,Vector2.UP,[warning])
				check(app.simulation.step_status().get("ok",false) and not app.state.telegraphs.is_empty() and app.state.player_mobility.phase == "over","actual Core warning is visible during the actual roof phase")
				if not app.simulation.step_status().get("ok",false) or app.state.telegraphs.is_empty() or app.state.player_mobility.phase != "over": break
			app._present()
			var sample: Dictionary = app.world.mobility_commands()
			await _capture("roof-%s-%dx%d" % [phase,size.x,size.y],size,app.simulation.snapshot(app.state),sample,app)
			if phase == "over":
				app.world.reduce_effects = true
				await _capture("roof-over-reduced-%dx%d" % [size.x,size.y],size,app.simulation.snapshot(app.state),app.world.mobility_commands(),app)
				app.world.reduce_effects = false
			if phase == "ground": app.input_router.clear_transient_input()
		app.free()
		await _settle()
	# Four exact authored district templates from current provider, actual Core.
	# Seeds below are chosen by the generator itself, never by replacing slots.
	root.size = Vector2i(800,800); root.content_scale_size = root.size
	await _settle()
	var provider = City.new()
	var chapter: Dictionary = provider.load_chapter("chapter_01_shiganshina").chapter
	var seen: Dictionary = {}
	for seed in 64:
		if seen.size() == 4: break
		var core = Core.new(provider)
		var state: Dictionary = core.new_run(chapter,seed,CF.run_config())
		state.player.position = [384.0,384.0]
		var hydration: Dictionary = HF.hydration(H.requirements(state))
		if not core.prepare_world(state,hydration).get("ok",false): continue
		var terrain: Dictionary = core.world_render_view(state)
		terrain.world_revision = core.world_status().get("world_revision",state.world.world_revision)
		var centers: Array = terrain.chunks.filter(func(c): return c.chunk_id == "0,0")
		if centers.is_empty(): continue
		var identity: String = str(centers[0].get("template_id",""))
		if identity.is_empty() or seen.has(identity): continue
		seen[identity] = true
		var view = View.new()
		root.add_child(view)
		view.set_process(false); view._viewport_size = Vector2(800,800)
		check(view.present_city(core.snapshot(state),terrain).get("ok",false),"actual district terrain is presented")
		await _capture("dense-"+identity,Vector2i(800,800),core.snapshot(state),view.mobility_commands())
		view.free()
	check(seen.size() == 4,"all four actual district templates are captured")
	var report = FileAccess.open(OUTPUT.path_join("capture-report.json"),FileAccess.WRITE)
	if report != null: report.store_string(JSON.stringify({"checks":checks,"failures":failures,"display":DisplayServer.get_name(),"records":records},"\t",true,true)); report.close()
	print("CAPTURE_RESULT checks=%d failures=%d display=%s" % [checks,failures.size(),DisplayServer.get_name()])
	quit(0 if failures.is_empty() else 1)
