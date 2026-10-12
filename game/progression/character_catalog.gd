class_name CharacterCatalog
extends RefCounted
# Additive metadata, independent of chapter gameplay fingerprints and run levels.
# Protagonist assignment and permanent unlock rules are separate data fields.
const DEFAULT_CHARACTER := "garrison_01"
const DEFAULT_CHAPTER := "chapter_01_shiganshina"
const SCENARIOS := {
	"chapter_01_shiganshina":{"implementation_status":"implemented","protagonist_id":"garrison_01"},
	"chapter_02":{"implementation_status":"planned","protagonist_id":""}
}
const CHARACTERS := {
	"garrison_01":{"name":"주둔병","description":"기존 시나리오 1 기본 캐릭터입니다.","implementation_status":"implemented","art_status":"ready","art_id":"garrison_01","unlock_condition":{"kind":"default"},"traits":{"move_speed_multiplier":1.0,"blade_cooldown_multiplier":1.0},"trait_text":"기본 이동속도와 기본 쌍검 재사용 간격","unique_skill":{"id":"","implementation_status":"not_applicable"},"signature_ultimate":{"id":"","implementation_status":"not_applicable"}},
	"mikasa_01":{"name":"미카사 · 기능 시제품","description":"시나리오 1 승리로 해금됩니다. 전용 원화와 고유 공격 행동은 미구현입니다. 현재 외형은 주둔병 QA 임시외형입니다.","implementation_status":"prototype","art_status":"missing","art_id":"","unlock_condition":{"kind":"chapter_clear","chapter_id":"chapter_01_shiganshina"},"traits":{"move_speed_multiplier":1.08,"blade_cooldown_multiplier":0.85},"trait_text":"이동속도 +8% · 기본 쌍검/입체기동 연속참 재사용 간격 15% 단축 (초기 수치)","unique_skill":{"id":"mikasa_unique_attack","implementation_status":"planned"},"signature_ultimate":{"id":"mikasa_signature","implementation_status":"planned"}},
	"eren_01":{"name":"에렌 · 미구현","description":"해금 조건과 고유 전투 행동을 아직 구현하지 않았습니다.","implementation_status":"planned","art_status":"missing","art_id":"","unlock_condition":{"kind":"unassigned"},"traits":{"move_speed_multiplier":1.0,"blade_cooldown_multiplier":1.0},"trait_text":"미구현","unique_skill":{"id":"eren_unique_attack","implementation_status":"planned"},"signature_ultimate":{"id":"titan_transformation","implementation_status":"planned"}},
	"levi_01":{"name":"리바이 · 미구현","description":"주인공 배정 여부와 별개로 해금 조건을 지정할 수 있습니다. 현재 해금 조건과 전투 행동은 미구현입니다.","implementation_status":"planned","art_status":"missing","art_id":"","unlock_condition":{"kind":"unassigned"},"traits":{"move_speed_multiplier":1.0,"blade_cooldown_multiplier":1.0},"trait_text":"미구현","unique_skill":{"id":"levi_unique_attack","implementation_status":"planned"},"signature_ultimate":{"id":"levi_signature","implementation_status":"planned"}}
}
func definition(id: String) -> Dictionary:
	return CHARACTERS.get(id,{}).duplicate(true)
func scenario_definition(id: String) -> Dictionary:
	return SCENARIOS.get(id,{}).duplicate(true)
func protagonist_id(chapter_id: String) -> String:
	return str(SCENARIOS.get(chapter_id,{}).get("protagonist_id",""))
func runtime_available(id: Variant) -> bool:
	return id is String and CHARACTERS.has(id) and CHARACTERS[id].implementation_status in ["implemented","prototype"]
func run_traits(id: String) -> Dictionary:
	return CHARACTERS[id].traits.duplicate(true) if runtime_available(id) else {}
func _is_unlocked(profile: Dictionary, id: String) -> bool:
	return CHARACTERS.has(id) and (CHARACTERS[id].unlock_condition.kind == "default" or id in profile.get("unlocked_character_ids",[]))
func profile_selection_valid(profile: Dictionary) -> bool:
	if not profile.has("selected_character_id"): return true
	var id: Variant = profile.selected_character_id
	return runtime_available(id) and _is_unlocked(profile,id)
func selection_error(profile: Dictionary, chapter_id: String, id: String) -> String:
	if SCENARIOS.get(chapter_id,{}).get("implementation_status","") != "implemented": return "not_implemented"
	if not CHARACTERS.has(id): return "invalid_character"
	if not runtime_available(id): return "not_implemented"
	if not chapter_id in profile.get("cleared_chapter_ids",[]): return "chapter_not_cleared"
	if not _is_unlocked(profile,id): return "character_locked"
	return ""
func run_character_id(profile: Dictionary, chapter_id: String) -> String:
	if SCENARIOS.get(chapter_id,{}).get("implementation_status","") != "implemented": return ""
	if not chapter_id in profile.get("cleared_chapter_ids",[]): return protagonist_id(chapter_id)
	var id: Variant = profile.get("selected_character_id",protagonist_id(chapter_id))
	if not id is String or not selection_error(profile,chapter_id,id).is_empty(): return ""
	return id
func unlocks_for_clear(profile: Dictionary, chapter_id: String) -> Array[String]:
	var unlocked: Array[String] = []
	for id in CHARACTERS:
		var condition: Dictionary = CHARACTERS[id].unlock_condition
		if runtime_available(id) and condition.kind == "chapter_clear" and condition.chapter_id == chapter_id and not id in profile.unlocked_character_ids: unlocked.append(id)
	return unlocked
func selection_rows(profile: Dictionary, chapter_id: String, active: bool) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var selected := run_character_id(profile,chapter_id)
	for id in CHARACTERS:
		var item: Dictionary = CHARACTERS[id]
		var blocked := "active_run" if active else selection_error(profile,chapter_id,id)
		rows.append({"id":id,"name":item.name,"description":item.description,"trait_text":item.trait_text,"implementation_status":item.implementation_status,"art_status":item.art_status,"is_unlocked":_is_unlocked(profile,id),"is_selected":id == selected,"can_select":blocked.is_empty(),"blocked_reason":blocked,"unique_skill":item.unique_skill.duplicate(true),"signature_ultimate":item.signature_ultimate.duplicate(true)})
	return rows
