extends RefCounted
const UI = preload("res://game/ui/game_ui.gd")
const Fixture = preload("res://tests/core/new_current_regression_fixture.gd")
const View = preload("res://game/progression/progression_view.gd")
func run(t) -> void:
 var ui = UI.new()
 t.root.add_child(ui)
 ui.reflow(Vector2i(800,450),Rect2i(0,0,800,450))
 var sim = Fixture.simulation(t)
 var state: Dictionary = Fixture.earn_offer(sim,21,24)
 ui.present_progression(View.new().build(state))
 ui.present(sim.snapshot(state))
 for ignored in range(8): await t.process_frame
 var card_font: Font = ui._growth_cards[0].get_theme_font("font")
 t.check(ui.theme != null,"Korean font is an inherited Theme resource, not a local root override")
 t.check(card_font is FontVariation,"native cards use the explicitly weighted bundled font")
 t.check(card_font == ui.get_node("Pause").get_theme_font("font"),"pause and growth share the bundled font")
 t.check(card_font == ui._hud.get_theme_font("font"),"HUD and growth share the bundled font")
 t.check(ui._growth_cards[0].get_theme_font_size("font_size")==15,"card font size remains 15")
 var ts := TextServerManager.get_primary_interface()
 if card_font is FontVariation:
  var rids: Array[RID] = card_font.get_rids()
  t.check(rids.size()==1,"bundled variation has exactly one font RID")
  for rid in rids:
   t.check(ts.font_get_variation_coordinates(rid).get(2003265652,0)==600,"actual RID uses weight 600 rather than default Thin")
  for value in "진격의 거인: 인류의 날개 시간시나구 탈출 보급소 진화 완료 → ← ↑ ↓ ↔ ± Ⅱ 0123456789":
   if value != " ": t.check(card_font.has_char(value.unicode_at(0)),"bundled font covers required glyph "+value)
 ui.free()
