extends RefCounted
# DTO-only UI contract. The gameplay authority is deliberately not changed.
const Card = preload("res://game/ui/growth_card.gd")
const HUD = preload("res://game/ui/progression_hud.gd")
const Detail = preload("res://game/ui/evolution_detail_panel.gd")
const Loadout = preload("res://game/ui/loadout_panel.gd")
const REQUIREMENTS := [
	{"kind":"equipment","item_id":"spin_slash","name":"회전 베기","current":5,"required":5,"met":true,"icon_id":"skill_spin_slash","requirement_type":"base_level","owned":true},
	{"kind":"equipment","item_id":"odm_dash","name":"입체기동 돌진","current":0,"required":1,"met":false,"icon_id":"skill_odm_dash","requirement_type":"owned_skill","owned":false,"blocked_reason":"missing_weapon"}
]
func run(t) -> void:
	var option := {"kind":"evolution","item_id":"spin_slash","evolution_id":"evo_whirlwind","icon_id":"skill_evo_whirlwind","option_id":"evolution:evo_whirlwind","name":"회오리 검무","level":5,"next_level":6,"max_level":6,"can_select":true,"status":"ready","description":"긴 전투 설명은 선택면에 반복하지 않습니다.","requirements":REQUIREMENTS.duplicate(true),"effect_delta":{"damage_before":12,"damage_after":20}}
	var card := Card.new()
	card.present(option)
	t.check(card.icon != null,"growth skill has its own actual texture")
	t.check(card.face_text().contains("5/6") and not card.face_text().contains("6/6"),"evolution card shows current/max level without next-level duplication")
	t.check(card.display_text().contains("진화") and not card.face_text().contains("궁극") and not card.display_text().contains("궁극"),"run evolution detail uses 진화 without repeating a prefix on the compact numeric face")
	t.check(not card.face_text().contains(option.description),"growth choice face does not repeat long descriptions")
	t.check(card.display_text().contains(option.description),"full authored effects remain available through explicit details")
	var requirements := Card.requirements_text(REQUIREMENTS)
	t.check(requirements.contains("입체기동 돌진") and requirements.contains("미보유"),"missing prerequisite keeps its full skill name and ownership state")
	var owned := REQUIREMENTS.duplicate(true)
	owned[1].current = 1
	owned[1].met = true
	owned[1].owned = true
	owned[1].blocked_reason = ""
	t.check(Card.requirements_text(owned).contains("입체기동 돌진 · 보유 ✓"),"one acquired level satisfies and labels the owned-skill prerequisite")
	var evolved := {"item_id":"spin_slash","name":"회전 베기","evolution_id":"evo_whirlwind","evolution_name":"회오리 검무","level":6,"display_level":6,"max_level":6,"display_max_level":6,"is_evolved":true,"is_max":true,"icon_id":"skill_evo_whirlwind"}
	t.check(HUD.level_text(evolved).contains("6/6") and HUD.level_text(evolved).contains("진화"),"evolved HUD state retains numeric 6/6")
	var hud := HUD.new()
	t.root.add_child(hud)
	hud.present({"owned":{"equipment":[evolved],"passives":[{"item_id":"movement","name":"가벼운 발걸음","level":5,"max_level":5,"is_max":true}]},"evolutions":[{"evolution_id":"evo_whirlwind","name":"회오리 검무"}],"target":{}})
	t.check(hud.display_text().contains("6/6") and hud.display_text().contains("5/5"),"HUD displays attack6 and passive5 caps together")
	var slot := hud.slot_controls()[0]
	t.check(slot.get_node_or_null("Icon") is TextureRect and slot.get_node("Icon").texture != null,"HUD equipped slot renders a real skill icon")
	var detail := Detail.new()
	detail.present_owned(evolved,{"evolution_id":"evo_whirlwind","name":"회오리 검무","status":"evolved","requirements":owned})
	t.check(detail.display_text().contains("6/6") and not detail.display_text().contains("궁극"),"owned detail names evolved attack and max level without 궁극")
	t.check(detail.get_node_or_null("Requirements") != null,"evolution detail exposes icon and named prerequisite rows")
	var detail_rows := detail.get_node_or_null("Requirements")
	if detail_rows != null and detail_rows.get_child_count() == 2:
		var held_row := detail_rows.get_child(1)
		t.check(held_row.get_node("Icon").texture != null and held_row.get_node("Text").text.contains("입체기동 돌진 · 보유 ✓"),"owned detail renders the named held prerequisite and its actual icon together")
	else: t.check(false,"owned detail renders both actual prerequisite rows")
	var loadout := Loadout.new()
	loadout.present({"view_revision":1,"loadout":{},"loadout_options":{"targets":[{"id":"evo_whirlwind","name":"회오리 검무","can_select":true,"requirements":owned}]},"can_start":true})
	t.check(loadout.option_button("target_evolution_id","evo_whirlwind").icon != null,"loadout target has the same unique evolution shape")
	t.check(loadout.display_text().contains("입체기동 돌진") and loadout.display_text().contains("보유 ✓"),"loadout prerequisite retains named ownership state")
	card.free()
	hud.free()
	detail.free()
	loadout.free()
