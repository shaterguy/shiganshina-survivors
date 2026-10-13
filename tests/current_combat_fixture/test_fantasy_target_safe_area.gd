extends RefCounted
const F = preload("res://tests/core/new_current_regression_fixture.gd")
const View = preload("res://game/progression/progression_view.gd")
const Catalog = preload("res://game/progression/upgrade_catalog.gd")
const UI = preload("res://game/ui/game_ui.gd")
func run(t) -> void:
	var sim = F.simulation(t)
	var ui := UI.new()
	t.root.add_child(ui)
	for recipe_id in Catalog.new().evolutions.ids():
		var recipe: Dictionary = Catalog.new().evolutions.definition(recipe_id)
		for status in ["collecting","ready","evolved"]:
			var state: Dictionary = sim.new_run(F.chapter(),71,F.run_config(1,"doctrine_standard",recipe_id))
			state.equipment = {recipe.base_item_id:5}
			for requirement in recipe.required_passives:
				var level := int(requirement.level)-(1 if status == "collecting" else 0)
				if level > 0: state.passives[requirement.passive_id] = level
			for requirement in recipe.get("required_equipment",[]):
				var level := int(requirement.level)-(1 if status == "collecting" else 0)
				if level > 0: state.equipment[requirement.equipment_id] = level
			state.tactical_seals = int(recipe.seal_cost) if status == "ready" else 0
			if status == "evolved": state.evolutions = {recipe.base_item_id:recipe_id}
			ui.present(sim.snapshot(state))
			var view := View.new().build(state)
			t.check(not view.is_empty() and not view.get("target",{}).is_empty(),"current target fixture must produce a real nonempty progression view")
			if view.is_empty() or view.get("target",{}).is_empty(): continue
			t.check(view.target.get("status","") == status,"current target DTO represents the requested arranged status: "+recipe_id+status)
			ui.present_progression(view)
			for screen in [Vector2i(320,568),Vector2i(640,360)]:
				var safe := Rect2i(12,24,screen.x-24,screen.y-48)
				ui.reflow(screen,safe)
				for frame in 5: await t.process_frame
				var target: Label = ui._owned_hud.get_node("TargetRequirements")
				if status == "evolved":
					t.check(not target.is_visible_in_tree() and ui._owned_hud.slot_controls()[0].get_node("Status").text == "6/6","completed target yields to the actual evolved icon and level rather than duplicate completion copy")
				else: t.check(target.is_visible_in_tree(),"incomplete target label is an actually visible Control")
				var label: String = recipe_id+" "+status+" "+str(screen)
				t.check(Rect2(safe).encloses(target.get_global_rect()) and ui._owned_hud.get_global_rect().encloses(target.get_global_rect()),"current eight-recipe target stays within safe inset and HUD: "+label)
				for line in target.text.split("\n"):
					var width: float = target.get_theme_font("font").get_string_size(line,HORIZONTAL_ALIGNMENT_LEFT,-1,13).x
					t.check(width <= target.size.x,"current eight-recipe target line is fully readable without clipping: "+label+" width="+str(width)+" available="+str(target.size.x))
					print("CURRENT_TARGET_LAYOUT "+JSON.stringify({"recipe":recipe_id,"status":status,"screen":[screen.x,screen.y],"line":line,"width":width,"available":target.size.x}))
	ui.free()
