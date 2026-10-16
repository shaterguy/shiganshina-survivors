extends RefCounted
const Card = preload("res://game/ui/growth_card.gd")
func run(t) -> void:
	for values in [[0,6],[0,5],[3,5],[5,6],[6,6]]:
		var option := {"kind":"equipment","item_id":"spin_slash","name":"회전 베기","level":values[0],"max_level":5,"display_level":values[0],"display_max_level":values[1],"next_level":values[0]+1,"effect_delta":{"damage_before":1,"damage_after":2}}
		var before := option.duplicate(true)
		var face := Card.summary(option)
		t.check(face.split("\n")[0] == "회전 베기 %d/%d" % values,"UI-01 actual current/display cap appears beside full name")
		t.check(not face.contains("신규 습득") and not face.contains("레벨업") and face.split("\n").size() == 2,"UI-01 no redundant level transition row")
		t.check(face.contains("\n피해 1→2") and option == before,"effect delta and source DTO remain exact")
	var option := {"kind":"passive","item_id":"movement","name":"가벼운 발걸음","level":0,"max_level":5,"evolution_previews":[{"name":"태풍 회전참","requirements":[{"kind":"equipment","item_id":"spin_slash","name":"회전 베기","required":5,"current":0,"met":false},{"kind":"passive","item_id":"movement","name":"가벼운 발걸음","required":1,"current":0,"met":false},{"kind":"passive","item_id":"different","name":"가벼운 발걸음","required":1,"current":1,"met":true},{"kind":"seal","item_id":"tactical_seal","name":"개조권","required":1,"current":1,"met":true}]}]}
	var before := option.duplicate(true)
	var card := Card.new()
	card.present(option)
	t.check(not card.display_text().contains("가벼운 발걸음 · Lv 0/1 · 미보유"),"UI-02 selected passive's own missing condition is absent")
	t.check(card.display_text().contains("회전 베기 · Lv 0/5 · 미보유") and card.display_text().contains("가벼운 발걸음 · Lv 1/1 · 충족 ✓") and card.display_text().contains("개조권 · 1/1"),"other IDs, same-name companion and cost are retained")
	t.check(option == before,"UI-02 presentation does not alter authoritative requirements")
	card.free()
