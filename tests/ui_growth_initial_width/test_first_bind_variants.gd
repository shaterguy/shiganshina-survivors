extends RefCounted
# Regression: first one-option growth must not retain the original narrow-wrap
# grid minimum as a blank scroll tail after its only visible group has shrunk.
const Fixture = preload("res://tests/core/new_current_regression_fixture.gd")
const View = preload("res://game/progression/progression_view.gd")
const UI = preload("res://game/ui/game_ui.gd")
const Matrix = preload("res://tests/ui_growth_initial_width/test_width_matrix.gd")
var enforce_geometry := true # Separate original-oracle collection is read-only.
var observations: Array = []
func run(t) -> void:
	var suite = Matrix.new()
	suite.enforce_seed = enforce_geometry
	var sim = Fixture.simulation(t)
	var state: Dictionary = Fixture.earn_offer(sim,21,24)
	var real_view: Dictionary = View.new().build(state)
	var snapshot: Dictionary = sim.snapshot(state)
	for target in [[Vector2i(800,450),Rect2i(0,0,800,450)],[Vector2i(773,449),Rect2i(19,7,719,428)],[Vector2i(450,450),Rect2i(0,0,450,450)],[Vector2i(280,450),Rect2i(7,13,266,420)]]:
		for kind in ["zero","one","two","long","evolved"]:
			var vp := SubViewport.new()
			vp.size = target[0]
			t.root.add_child(vp)
			var ui = UI.new()
			vp.add_child(ui)
			ui.reflow(target[0],target[1])
			await suite._settle(t)
			var view := real_view.duplicate(true)
			view.active_offer.offer_id += ":first_"+kind
			match kind:
				"zero":
					view.active_offer.options = []
					view.target = {}
				"one":
					view.active_offer.options = view.active_offer.options.slice(0,1)
					view.target = {}
				"two": view.active_offer.options = view.active_offer.options.slice(0,2)
				"long":
					view.active_offer.options[0].slot_warning = "이 선택으로 마지막 장비 슬롯이 채워집니다. ".repeat(8)
					view.active_offer.options[1].tradeoff_text = "이동 속도가 감소하고 공격력이 증가합니다. ".repeat(6)
				"evolved":
					view.active_offer.options[0].kind = "evolution"
					view.active_offer.options[0].status = "evolved"
					view.active_offer.options[1].can_select = false
					view.active_offer.options[1].blocked_reason = "missing_weapon"
			suite.signals = []
			suite._connect_signals(ui)
			var label: String = str(target[0])+":first_"+kind
			await suite._offer(ui,t,view,snapshot,label,true)
			if enforce_geometry and kind=="one" and ui._choices.columns==1:
				# The existing Grid has no vertical EXPAND flag. With one visible
				# child there is no inter-row separation; its native height is the
				# child's minimum, not an obsolete narrow-wrap minimum.
				var visible: Array = ui._growth_groups.filter(func(group):return group.visible)
				t.check(visible.size()==1,label+": one visible group defines one grid row")
				var child_height: float = visible[0].get_combined_minimum_size().y
				t.check(is_equal_approx(ui._choices.size.y,child_height),label+": sole-row grid has no stale wrapped-height scroll tail")
				if child_height<ui._scroll.size.y:
					t.check(not ui._scroll.get_v_scroll_bar().visible,label+": fitting sole row does not retain an obsolete AUTO scrollbar")
			vp.free()
			await suite._settle(t)
	observations = suite.observations
