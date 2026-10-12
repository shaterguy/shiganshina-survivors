extends RefCounted
const Card = preload("res://game/ui/growth_card.gd")
const Fixture = preload("res://tests/core/new_current_regression_fixture.gd")
const View = preload("res://game/progression/progression_view.gd")
func run(t) -> void:
 var sim = Fixture.simulation(t)
 var state: Dictionary = Fixture.earn_offer(sim,21,24)
 var view: Dictionary = View.new().build(state)
 var option: Dictionary = view.active_offer.options[0]
 var before := option.duplicate(true)
 var full = Card.new()
 full.present(option)
 var summary = Card.new()
 var accepts_surface := false
 for method in summary.get_method_list():
  if method.name == "present": accepts_surface = method.args.size() == 2
 t.check(accepts_surface,"Card accepts a separate visible summary without assigning rich detail to the face")
 if accepts_surface:
  summary.callv("present",[option,"성장 요약 · A 선택"])
  t.check(summary.text == "성장 요약 · A 선택","explicit summary is the only final face")
  t.check(summary.display_text() == full.display_text(),"full effect and requirements remain accessible")
  t.check(summary.tooltip_text == full.tooltip_text,"rich tooltip remains byte-identical")
  t.check(summary.disabled == full.disabled,"selection eligibility remains unchanged")
  t.check(summary.get_meta("semantic_id") == full.get_meta("semantic_id"),"semantic binding remains unchanged")
  var events: Array = []
  summary.chosen.connect(func(id): events.append(id))
  summary.pressed.emit()
  t.check(events == [option.option_id],"summary selects the same authored option")
  summary.present(option)
  t.check(summary.text == full.text,"one-argument API still shows rich text")
  summary.clear()
  t.check(summary.text.is_empty() and summary.tooltip_text.is_empty() and summary.disabled,"clear removes both surface and rich text")
 t.check(option==before,"source DTO is untouched")
 full.free()
 summary.free()
