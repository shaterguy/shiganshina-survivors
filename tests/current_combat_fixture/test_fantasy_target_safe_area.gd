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
			for requirement in recipe.required_passives: state.passives[requirement.passive_id] = int(requirement.level)-(1 if status == "collecting" else 0)
			for requirement in recipe.get("required_equipment",[]): state.equipment[requirement.equipment_id] = int(requirement.level)-(1 if status == "collecting" else 0)
			state.tactical_seals = 1 if status == "ready" else 0
			if status == "evolved": state.evolutions = {recipe.base_item_id:recipe_id}
			ui.present(sim.snapshot(state))
			ui.present_progression(View.new().build(state))
			for screen in [Vector2i(320,568),Vector2i(640,360)]:
				var safe := Rect2i(12,24,screen.x-24,screen.y-48)
				ui.reflow(screen,safe)
				for frame in 5: await t.process_frame
				var target: Label = ui._owned_hud.get_node("TargetRequirements")
				var label: String = recipe_id+" "+status+" "+str(screen)
				t.check(Rect2(safe).encloses(target.get_global_rect()) and ui._owned_hud.get_global_rect().encloses(target.get_global_rect()),"current four-recipe target stays within safe inset and HUD: "+label)
				for line in target.text.split("\n"):
					var width: float = target.get_theme_font("font").get_string_size(line,HORIZONTAL_ALIGNMENT_LEFT,-1,13).x
					t.check(width <= target.size.x,"current four-recipe target line is fully readable without clipping: "+label+" width="+str(width)+" available="+str(target.size.x))
					print("CURRENT_TARGET_LAYOUT "+JSON.stringify({"recipe":recipe_id,"status":status,"screen":[screen.x,screen.y],"line":line,"width":width,"available":target.size.x}))
	ui.free()
