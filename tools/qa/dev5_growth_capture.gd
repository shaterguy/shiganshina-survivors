extends SceneTree
# One-shot real-Core/UI capture. Arranged prerequisites are not balance evidence.
# No SaveStore, account, user files, network, or production-state access.
const F = preload("res://tests/core/new_current_regression_fixture.gd")
const Catalog = preload("res://game/progression/upgrade_catalog.gd")
const View = preload("res://game/progression/progression_view.gd")
const UI = preload("res://game/ui/game_ui.gd")
const OUTPUT := "res://.qa/dev5-captures"
var failures: Array[String] = []
var checks := 0
var _choice_result: Dictionary = {}
func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		push_error("CAPTURE_FAIL: "+message)
func _initialize() -> void:
	call_deferred("run")
func _settle() -> void:
	for frame in range(6): await process_frame
func _capture(name: String, dimensions: Vector2i) -> void:
	await _settle()
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	check(image != null and image.get_size() == dimensions,"capture has the actual requested rendered size: "+name)
	if image == null: return
	var error := image.save_png(OUTPUT.path_join(name+".png"))
	check(error == OK,"rendered PNG is saved: "+name)
	print("CAPTURE_PNG ",OUTPUT.path_join(name+".png")," ",image.get_size())
func run() -> void:
	if DisplayServer.get_name() == "headless":
		check(false,"PNG capture needs the actual local Xvfb display, not the headless display server")
		quit(1)
		return
	check(DirAccess.make_dir_recursive_absolute(OUTPUT) == OK,"isolated QA output directory exists")
	var catalog := Catalog.new()
	check(catalog.validate().is_empty(),"current catalog is valid before capture")
	if not catalog.validate().is_empty(): quit(1); return
	var recipe: Dictionary = catalog.evolutions.definition("evo_whirlwind")
	check(not recipe.is_empty(),"actual new evolution recipe exists")
	if recipe.is_empty(): quit(1); return
	for screen in [Vector2i(800,450),Vector2i(450,800),Vector2i(360,800)]:
		root.size = screen
		root.content_scale_size = screen
		root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
		root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
		await _settle()
		var simulation = F.simulation(self)
		var state: Dictionary = simulation.new_run(F.chapter(),621,F.run_config(1,"doctrine_standard","evo_whirlwind"))
		check(not state.has("error_code"),"real current Core begins the isolated capture")
		if state.has("error_code"): continue
		state.equipment = {recipe.base_item_id:5}
		state.passives = {}
		for material in recipe.get("required_equipment",[]): state.equipment[material.equipment_id] = int(material.level)
		for material in recipe.get("required_passives",[]): state.passives[material.passive_id] = int(material.level)
		for id in state.equipment: state.player.attack_ready_ticks[id] = 2147483647
		check(simulation.restore(state).get("ok",false),"arranged prerequisites are restorable actual Core state")
		# One real XP threshold creates exactly one materialized growth offer.
		var threshold := Catalog.xp_to_next(int(state.player.level),state.rules.progression)
		F.drop_xp(simulation,state,threshold,"capture:xp")
		var view := View.new(catalog).build(state)
		var index := -1
		for slot in view.get("active_offer",{}).get("options",[]).size():
			if view.active_offer.options[slot].get("evolution_id","") == "evo_whirlwind": index = slot
		check(index >= 0,"real XP materializes the authored evolution choice")
		if index < 0: continue
		var background := ColorRect.new()
		background.color = Color("18211d")
		background.size = screen
		background.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(background)
		var ui := UI.new()
		root.add_child(ui)
		_choice_result = {}
		ui.upgrade_chosen.connect(func(offer_id,option_id): _choice_result = simulation.choose_upgrade(state,offer_id,option_id))
		ui.present(simulation.snapshot(state))
		ui.present_progression(view)
		ui.reflow(screen,Rect2i(Vector2i.ZERO,screen))
		ui._growth_cards[index].grab_focus()
		var name := "%dx%d" % [screen.x,screen.y]
		await _capture("evolution-choice-"+name,screen)
		ui.accept_released()
		ui.navigate("accept")
		check(_choice_result.get("ok",false),"the existing controller accept selects the actual Core evolution")
		check(state.evolutions.get(recipe.base_item_id,"") == "evo_whirlwind","selected evolution is authoritative before HUD capture")
		ui.present(simulation.snapshot(state))
		ui.present_progression(View.new(catalog).build(state))
		ui.reflow(screen,Rect2i(Vector2i.ZERO,screen))
		check(ui._owned_hud.slot_controls()[0].get_node("Status").text == "6/6" and ui._owned_hud.slot_controls()[0].get_node("Icon").texture != null,"post-selection HUD projects the actual evolved identity and completed sixth stage")
		await _capture("evolved-hud-"+name,screen)
		ui.free()
		background.free()
	print("CAPTURE_RESULT checks=%d failures=%d display=%s" % [checks,failures.size(),DisplayServer.get_name()])
	quit(0 if failures.is_empty() else 1)
