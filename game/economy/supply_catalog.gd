class_name SupplyCatalog
extends RefCounted
const Characters = preload("res://game/progression/character_catalog.gd")
# NEW E1 implementation. Definitions are NEW tuning candidates, not recovered bytes.
# No GameSave dependency: this catalog can be used by its validator without a cycle.
const CONTENT_REVISION := "ch01.3-rebuild.7-grabber-hand"
const MAX_COUNTER := 2147483647
const PERMANENT_ITEMS := {
  "permanent_might": {
    "item_id": "permanent_might",
    "kind": "permanent_upgrade",
    "price": 20,
    "level_prices": [
      20,
      35,
      55,
      80,
      110
    ],
    "max_owned": 5,
    "name": "숙련된 칼날",
    "description": "모든 무기와 궁극 진화의 공격력이 단계마다 5% 증가합니다.",
    "tradeoff_text": "구매 후 모든 다음 출격에 적용됩니다. 초기 튜닝값입니다.",
    "effect_id": "permanent_stat",
    "effect_params": {
      "stat": "damage_multiplier",
      "increment": 0.05
    }
  },
  "permanent_vitality": {
    "item_id": "permanent_vitality",
    "kind": "permanent_upgrade",
    "price": 20,
    "level_prices": [
      20,
      35,
      55,
      80,
      110
    ],
    "max_owned": 5,
    "name": "강인한 체력",
    "description": "최대 체력이 단계마다 10 증가합니다.",
    "tradeoff_text": "구매 후 모든 다음 출격에 적용됩니다. 초기 튜닝값입니다.",
    "effect_id": "permanent_stat",
    "effect_params": {
      "stat": "max_hp",
      "increment": 10
    }
  },
  "permanent_magnet": {
    "item_id": "permanent_magnet",
    "kind": "permanent_upgrade",
    "price": 20,
    "level_prices": [
      20,
      35,
      55,
      80,
      110
    ],
    "max_owned": 5,
    "name": "넓은 회수 범위",
    "description": "경험치와 보급품 회수 반경이 단계마다 10 증가합니다.",
    "tradeoff_text": "구매 후 모든 다음 출격에 적용됩니다. 초기 튜닝값입니다.",
    "effect_id": "permanent_stat",
    "effect_params": {
      "stat": "pickup_radius",
      "increment": 10
    }
  }
}
var _items: Dictionary = {}
var _doctrines: Dictionary = {}
var _errors: Array[String] = []
func _init(shop_definition: Variant = null, doctrine_definition: Variant = null, equipment_definition: Variant = null, passives_definition: Variant = null) -> void:
	var shop = _read("res://data/supply_shop.json") if shop_definition == null else shop_definition
	var doctrines = _read("res://data/doctrines.json") if doctrine_definition == null else doctrine_definition
	var equipment = _read("res://data/equipment.json") if equipment_definition == null else equipment_definition
	var passives = _read("res://data/passives.json") if passives_definition == null else passives_definition
	if not _document_valid(shop) or not _document_valid(doctrines):
		_errors.append("invalid_item")
		return
	if not equipment is Dictionary or not equipment.get("items") is Dictionary or not passives is Dictionary or not passives.get("items") is Dictionary:
		_errors.append("invalid_item")
		return
	for id in doctrines.items:
		if not _doctrine_valid(id,doctrines.items[id],equipment.items,passives.items):
			_errors.append("invalid_item")
			return
	for id in shop.items:
		if not _item_valid(id,shop.items[id],doctrines.items):
			_errors.append("invalid_item")
			return
	for id in ["doctrine_standard","doctrine_mobile","doctrine_artillery"]:
		if not doctrines.items.has(id):
			_errors.append("invalid_item")
			return
	if not shop.items.has("field_bandage"):
		_errors.append("invalid_item")
		return
	for id in doctrines.items:
		var unlock: String = doctrines.items[id].unlock_item_id
		if id == "doctrine_standard":
			if unlock != "":
				_errors.append("invalid_item")
				return
		elif not shop.items.has(unlock) or shop.items[unlock].get("kind") != "doctrine" or shop.items[unlock].effect_params.get("doctrine_id") != id:
			_errors.append("invalid_item")
			return
	_items = shop.items.duplicate(true)
	_items.merge(PERMANENT_ITEMS.duplicate(true))
	_doctrines = doctrines.items.duplicate(true)
	for row in _items.values():
		row.price = int(row.price)
		row.max_owned = int(row.max_owned)
		if row.kind == "consumable": row.effect_params.heal = int(row.effect_params.heal)
		if row.kind == "permanent_upgrade":
			for i in row.level_prices.size(): row.level_prices[i] = int(row.level_prices[i])
	for row in _doctrines.values():
		for key in ["initial_equipment","initial_passives"]:
			for id in row[key]: row[key][id] = int(row[key][id])
func validate() -> Array[String]:
	return _errors.duplicate()
func doctrine(id: String) -> Dictionary:
	return _doctrines.get(id,{}).duplicate(true)
func item(id: String) -> Dictionary:
	return _items.get(id,{}).duplicate(true)
func item_ids() -> Array[String]:
	var ids: Array[String] = []
	for id in _items: ids.append(id)
	ids.sort()
	return ids
func _read(path: String) -> Variant:
	if not FileAccess.file_exists(path): return null
	return JSON.parse_string(FileAccess.get_file_as_string(path))
func _document_valid(value: Variant) -> bool:
	return value is Dictionary and _counter(value.get("schema_version")) and value.schema_version == 1 and value.get("content_revision") is String and value.content_revision == CONTENT_REVISION and value.get("items") is Dictionary and not value.items.is_empty() and value.items.size() <= 256
func _doctrine_valid(id: Variant, value: Variant, equipment: Dictionary, passives: Dictionary) -> bool:
	if not id is String or id.is_empty() or not value is Dictionary or not value.get("doctrine_id") is String or value.doctrine_id != id or not _texts_valid(value): return false
	if not value.get("unlock_item_id") is String: return false
	if not _positive(value.get("base_hp")) or not _positive(value.get("base_move_speed")): return false
	return _initial_valid(value.get("initial_equipment"),equipment,false) and _initial_valid(value.get("initial_passives"),passives,true)
func _initial_valid(value: Variant, definitions: Dictionary, allow_empty: bool) -> bool:
	if not value is Dictionary or value.size() > 4 or (not allow_empty and value.is_empty()): return false
	for id in value:
		if not id is String or not definitions.has(id) or not _counter(value[id]) or value[id] < 1 or value[id] > definitions[id].get("max_level",0): return false
	return true
func _item_valid(id: Variant, value: Variant, doctrines: Dictionary) -> bool:
	if not id is String or id.is_empty() or not value is Dictionary or not value.get("item_id") is String or value.item_id != id or not _texts_valid(value): return false
	if not _counter(value.get("price")) or value.price < 1 or not _counter(value.get("max_owned")): return false
	if not value.get("effect_params") is Dictionary or not value.get("kind") is String or not value.get("effect_id") is String: return false
	if value.get("kind") == "doctrine":
		return value.get("effect_id") == "unlock_doctrine" and value.max_owned == 1 and value.effect_params.size() == 1 and value.effect_params.get("doctrine_id") is String and value.effect_params.doctrine_id == id and id != "doctrine_standard" and doctrines.has(id) and doctrines[id].unlock_item_id == id
	if value.get("kind") == "consumable":
		return id == "field_bandage" and value.get("effect_id") == "prepared_bandage" and value.max_owned == 9 and value.effect_params.size() == 2 and _counter(value.effect_params.get("heal")) and value.effect_params.heal == 25 and _positive(value.effect_params.get("threshold_ratio")) and value.effect_params.threshold_ratio == 0.3
	if value.get("kind") == "permanent_upgrade":
		var effects := {"permanent_might":{"stat":"damage_multiplier","increment":0.05},"permanent_vitality":{"stat":"max_hp","increment":10},"permanent_magnet":{"stat":"pickup_radius","increment":10}}
		if not effects.has(id) or value.effect_id != "permanent_stat" or value.max_owned != 5 or value.effect_params.size() != 2 or value.effect_params.get("stat") != effects[id].stat or not _positive(value.effect_params.get("increment")) or value.effect_params.increment != effects[id].increment: return false
		if not value.get("level_prices") is Array or value.level_prices.size() != value.max_owned: return false
		for price in value.level_prices:
			if not _counter(price): return false
		return value.price == value.level_prices[0]
	return false
func permanent_levels_valid(value: Variant) -> bool:
	if not value is Dictionary: return false
	for id in value:
		if not id is String or not _items.has(id) or _items[id].kind != "permanent_upgrade": return false
		var level: Variant = value[id]
		if not (level is int or level is float) or not is_finite(float(level)) or level < 0 or level != floor(level) or level > _items[id].max_owned: return false
	return true
func run_upgrade_config_valid(config: Dictionary) -> bool:
	var character_fields := 1 if config.has("character_id") else 0
	if character_fields and not Characters.new().runtime_available(config.character_id): return false
	if not config.has("permanent_upgrades"): return config.size() == 5+character_fields
	return config.size() == 6+character_fields and permanent_levels_valid(config.permanent_upgrades)
func permanent_levels(profile: Dictionary) -> Dictionary:
	var value: Variant = profile.get("permanent_upgrades",{})
	if not permanent_levels_valid(value): return {}
	var levels := {}
	for id in value: levels[id] = int(value[id])
	return levels
func permanent_bonus(levels: Dictionary, stat: String) -> float:
	if not permanent_levels_valid(levels): return 0.0
	var result := 0.0
	for id in levels:
		if _items[id].effect_params.stat == stat: result += float(_items[id].effect_params.increment)*int(levels[id])
	return result
func purchase_price(definition: Dictionary, owned: int) -> int:
	if definition.kind != "permanent_upgrade": return int(definition.price)
	if owned < 0 or owned >= definition.max_owned: return 0
	return int(definition.level_prices[owned])
func permanent_effect_text(definition: Dictionary, level: int) -> String:
	var value := float(definition.effect_params.increment)*level
	match str(definition.effect_params.stat):
		"damage_multiplier": return "공격력 +%d%%" % roundi(value*100)
		"max_hp": return "최대 체력 +%d" % roundi(value)
		"pickup_radius": return "회수 반경 +%d" % roundi(value)
	return ""
func _texts_valid(value: Dictionary) -> bool:
	for key in ["name","description","tradeoff_text"]:
		if not value.get(key) is String or value[key].is_empty(): return false
	return true
func _positive(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value > 0 and value <= MAX_COUNTER
func _counter(value: Variant) -> bool:
	return _positive(value) and value == floor(value)
