extends SceneTree
# QA-only arranged legal approach/cast seed and actual Core warning commands.
# No mobility position, route, height, landing or authored geometry is injected.
const AppFixture = preload("res://tests/dev5_mobility_autosave/mobility_app_fixture.gd")
const CF = preload("res://tests/core/core_fixture.gd")
const Address = preload("res://game/world/world_address.gd")
const OUTPUT := "res://.qa/dev5-landing-danger-captures"
var checks: int = 0
var failures: Array[String] = []
var records: Array = []
func check(value: bool,message: String) -> void:
	checks += 1
	if not value: failures.append(message); push_error("CAPTURE_FAIL: "+message)
func _initialize() -> void: call_deferred("run")
func _settle() -> void:
	for frame in 6: await process_frame
func run() -> void:
	if DisplayServer.get_name() == "headless": check(false,"actual X11 display is required"); quit(1); return
	check(DirAccess.make_dir_recursive_absolute(OUTPUT) == OK,"separate landing-danger capture output exists")
	for size in [Vector2i(360,800),Vector2i(800,450)]:
		root.size = size; root.content_scale_size = size
		root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
		root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
		await _settle()
		var app = AppFixture.new().airborne(self,"landing_danger_%d" % size.x,"over")
		if app == null: continue
		app.autosave_worker_enabled = false
		app.process_mode = Node.PROCESS_MODE_DISABLED
		app.ui.reflow(size,Rect2i(Vector2i.ZERO,size))
		app.world._viewport_size = Vector2(size)
		app.input_router.set_touch_vector(Vector2.UP)
		var landing: Dictionary = app.state.player_mobility.landing
		var relative: Dictionary = Address.relative(landing.chunk,Vector2(landing.local[0],landing.local[1]),app.state.world.origin_chunk)
		check(relative.get("ok",false),"actual Core landing address resolves in current origin")
		if not relative.get("ok",false): app.free(); continue
		var point: Vector2 = relative.local
		var values: Array = []
		for shape in ["circle","line","sector"]:
			var offset: Vector2 = {"circle":Vector2(48,0),"line":Vector2(-80,56),"sector":Vector2(-88,-20)}[shape]
			var hazard: Dictionary = CF.hazard("landing-danger-capture-"+shape,shape,{"origin":[point.x+offset.x,point.y+offset.y],"direction":[1.0,0.0],"radius":38.0 if shape == "circle" else 52.0,"length":160.0,"width":18.0,"arc_degrees":90.0,"warning_ticks":120,"active_ticks":1,"damage":1.0})
			hazard.origin_revision = app.state.world.origin_revision
			values.append(hazard)
		CF.step(app.simulation,app.state,Vector2.UP,values)
		check(app.simulation.step_status().get("ok",false) and app.state.player_mobility.phase == "over" and app.state.telegraphs.size() == 3,"actual Core over checkpoint contains three distinct real warnings")
		if not app.simulation.step_status().get("ok",false) or app.state.player_mobility.phase != "over" or app.state.telegraphs.size() != 3: app.free(); continue
		app._present()
		var snapshot: Dictionary = app.simulation.snapshot(app.state)
		var commands: Dictionary = app.world.mobility_commands()
		check(commands.get("landing_position") is Vector2 and commands.landing_position == point,"renderer projects the actual unchanged landing destination")
		for reduced in [false,true]:
			app.world.reduce_effects = reduced
			app.world.queue_redraw()
			check(app.world.mobility_commands() == commands,"reduced effects preserves landing/wire/height projection")
			await _capture(app,"landing-danger-%dx%d%s" % [size.x,size.y,"-reduced" if reduced else ""],size,snapshot,point,reduced)
		app.free()
		await _settle()
	var report = FileAccess.open(OUTPUT.path_join("capture-report.json"),FileAccess.WRITE)
	check(report != null,"landing-danger capture report opens")
	if report != null:
		report.store_string(JSON.stringify({"checks":checks,"failures":failures,"display":DisplayServer.get_name(),"world_view_sha256":FileAccess.get_sha256("res://game/presentation/world_view.gd"),"city_render_sha256":FileAccess.get_sha256("res://game/presentation/city_render.gd"),"records":records},"\t",true,true)); report.close()
	print("LANDING_DANGER_CAPTURE_RESULT checks=%d failures=%d display=%s" % [checks,failures.size(),DisplayServer.get_name()])
	quit(0 if failures.is_empty() else 1)
func _capture(app,name: String,size: Vector2i,snapshot: Dictionary,point: Vector2,reduced: bool) -> void:
	var frozen: PackedByteArray = var_to_bytes(snapshot)
	await _settle(); await RenderingServer.frame_post_draw
	check(var_to_bytes(app.simulation.snapshot(app.state)) == frozen,"full Core snapshot is frozen during render: "+name)
	var raster: Image = root.get_texture().get_image()
	check(raster != null and raster.get_size() == size,"rendered PNG dimensions match: "+name)
	if raster == null: return
	var center: Vector2 = app.world._screen(point)
	var cyan: Dictionary = _pixels(raster,Rect2(center-Vector2(18,18),Vector2(36,36)),false)
	var red: Dictionary = _pixels(raster,Rect2(center+Vector2(10,-38),Vector2(76,76)),true)
	check(cyan.count >= 50,"cyan landing circle/dot pixels are visible beside the actual warning: "+name)
	check(red.count >= 50,"tinted danger raster is visibly red in actual PNG: "+name)
	check(float(cyan.get("luma",0.0))-float(red.get("luma",0.0)) >= 0.15,"landing and hazard retain distinct grayscale luminance: "+name)
	check(raster.save_png(OUTPUT.path_join(name+".png")) == OK,"color PNG saved: "+name)
	var gray: Image = raster.duplicate()
	for y in gray.get_height():
		for x in gray.get_width():
			var color: Color = gray.get_pixel(x,y)
			var value: float = color.r*0.2126+color.g*0.7152+color.b*0.0722
			gray.set_pixel(x,y,Color(value,value,value,color.a))
	check(gray.save_png(OUTPUT.path_join(name+"-grayscale.png")) == OK,"grayscale PNG saved for direct shape inspection: "+name)
	var hazards: Array = []
	for hazard in snapshot.telegraphs: hazards.append({"shape":hazard.shape,"origin":hazard.origin,"active_from_tick":hazard.active_from_tick})
	records.append({"name":name,"png_sha256":FileAccess.get_sha256(OUTPUT.path_join(name+".png")),"grayscale_name":name+"-grayscale","grayscale_sha256":FileAccess.get_sha256(OUTPUT.path_join(name+"-grayscale.png")),"dimensions":[size.x,size.y],"tick":snapshot.active_tick,"phase":snapshot.player_mobility.phase,"position":snapshot.player.position,"landing_world":[point.x,point.y],"landing_screen":[center.x,center.y],"reduced_effects":reduced,"core_frozen_during_render":true,"cyan_pixels":cyan,"red_pixels":red,"warnings":hazards,"fixture":"current authored provider; legal approach/cast seed/held UP and three genuine Core warning commands arranged; no path/landing/geometry injection"})
	print("LANDING_DANGER_CAPTURE_PNG ",OUTPUT.path_join(name+".png"))
	print("LANDING_DANGER_CAPTURE_PNG ",OUTPUT.path_join(name+"-grayscale.png"))
func _pixels(raster: Image,box: Rect2,danger: bool) -> Dictionary:
	var count: int = 0
	var total_luma: float = 0.0
	for y in range(maxi(0,int(box.position.y)),mini(raster.get_height(),int(box.end.y))):
		for x in range(maxi(0,int(box.position.x)),mini(raster.get_width(),int(box.end.x))):
			var color: Color = raster.get_pixel(x,y)
			var matches: bool = color.r >= 0.3 and color.r > color.g*1.8 and color.r > color.b*1.8 if danger else color.g >= 0.65 and color.b >= 0.65 and color.g > color.r*1.8 and color.b > color.r*1.8
			if matches:
				count += 1
				total_luma += color.r*0.2126+color.g*0.7152+color.b*0.0722
	return {"count":count,"luma":total_luma/maxi(1,count)}
