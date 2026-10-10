extends RefCounted
# NEW E1, hand-calculated economics. No Core or authority validity claims.
const Catalog = preload("res://game/economy/supply_catalog.gd")
func run(t) -> void:
	var catalog = Catalog.new()
	t.check(catalog.validate().is_empty(), "E1 catalog accepts reviewed definitions")
	t.check(catalog.item_ids() == ["doctrine_artillery","doctrine_mobile","field_bandage"], "E1 catalog stable sorted sale identities")
	var expected := {
		"doctrine_standard":{"base_hp":100,"base_move_speed":150,"initial_equipment":{"blade_slash":1},"initial_passives":{},"unlock_item_id":""},
		"doctrine_mobile":{"base_hp":85,"base_move_speed":150,"initial_equipment":{"blade_slash":1},"initial_passives":{"movement":1},"unlock_item_id":"doctrine_mobile"},
		"doctrine_artillery":{"base_hp":100,"base_move_speed":135,"initial_equipment":{"wall_cannon":1},"initial_passives":{"fire_interval":1},"unlock_item_id":"doctrine_artillery"}}
	for id in expected:
		var row: Dictionary = catalog.doctrine(id)
		t.check(not row.is_empty(), "E1 doctrine exists " + id)
		for key in expected[id]:
			t.check(row.get(key) == expected[id][key], "E1 doctrine hand value " + id + "/" + key)
		for key in ["name","description","tradeoff_text"]:
			t.check(row.get(key,"") is String and not row.get(key,"").is_empty(), "E1 doctrine actual benefit/tradeoff " + id + "/" + key)
	for id in ["doctrine_mobile","doctrine_artillery","field_bandage"]:
		var row: Dictionary = catalog.item(id)
		t.check(row.get("price") == (15 if id == "field_bandage" else 40), "E1 sale price " + id)
		t.check(row.get("max_owned") == (9 if id == "field_bandage" else 1), "E1 sale cap " + id)
		t.check(row.get("item_id") == id, "E1 sale ID " + id)
		for key in ["name","description","tradeoff_text"]:
			t.check(row.get(key,"") is String and not row.get(key,"").is_empty(), "E1 sale explanation " + id + "/" + key)
	var bandage: Dictionary = catalog.item("field_bandage")
	t.check(bandage.get("effect_id") == "prepared_bandage", "E1 bandage semantic effect")
	t.check(bandage.get("effect_params") == {"heal":25,"threshold_ratio":0.3}, "E1 bandage actual healing parameters")
	t.check(catalog.doctrine("unknown").is_empty() and catalog.item("unknown").is_empty(), "E1 unknown catalog IDs fail closed")
	var copy: Dictionary = catalog.doctrine("doctrine_standard")
	copy["base_hp"] = -1
	copy.initial_equipment.blade_slash = 5
	t.check(catalog.doctrine("doctrine_standard").get("base_hp") == 100, "E1 catalog value copied")
	t.check(catalog.doctrine("doctrine_standard").get("initial_equipment") == {"blade_slash":1}, "E1 catalog nested state copied")
	var sale_copy: Dictionary = catalog.item("doctrine_mobile")
	sale_copy.effect_params.doctrine_id = "unknown"
	t.check(catalog.item("doctrine_mobile").effect_params.doctrine_id == "doctrine_mobile","E1 nested sale effects copied")
	var items: Array = catalog.item_ids()
	items.clear()
	t.check(catalog.item_ids().size() == 3, "E1 IDs returned privately")
	var shop = JSON.parse_string(FileAccess.get_file_as_string("res://data/supply_shop.json"))
	var doctrines = JSON.parse_string(FileAccess.get_file_as_string("res://data/doctrines.json"))
	if not shop is Dictionary or not doctrines is Dictionary:
		t.check(false,"E1 authored data files load")
		return
	for mutation in ["negative_price","fraction_price","nonfinite_price","bad_kind","unknown_doctrine","unknown_effect","missing_tradeoff","duplicate_identity","bad_cap","missing_bandage","schema_string","revision_number","item_id_number","effect_target_number"]:
		var changed: Dictionary = shop.duplicate(true)
		match mutation:
			"schema_string": changed.schema_version = "1"
			"revision_number": changed.content_revision = 3
			"item_id_number": changed.items.field_bandage.item_id = 3
			"effect_target_number": changed.items.doctrine_mobile.effect_params.doctrine_id = 3
			"negative_price": changed.items.field_bandage.price = -1
			"fraction_price": changed.items.field_bandage.price = 1.5
			"nonfinite_price": changed.items.field_bandage.price = NAN
			"bad_kind": changed.items.field_bandage.kind = "lootbox"
			"unknown_doctrine": changed.items.doctrine_mobile.effect_params.doctrine_id = "unknown"
			"unknown_effect": changed.items.field_bandage.effect_id = "revive"
			"missing_tradeoff": changed.items.field_bandage.erase("tradeoff_text")
			"duplicate_identity": changed.items.field_bandage.item_id = "doctrine_mobile"
			"bad_cap": changed.items.field_bandage.max_owned = 10
			"missing_bandage": changed.items.erase("field_bandage")
		var bad = Catalog.new(changed,doctrines)
		t.check(not bad.validate().is_empty(), "E1 rejects malformed shop " + mutation)
		t.check(bad.item_ids().is_empty() and bad.item("field_bandage").is_empty(), "E1 invalid shop exposes no usable rows " + mutation)
	for mutation in ["unknown_weapon","level_zero","hp_nan","speed_negative","unlock_mismatch","future_schema","bad_revision"]:
		var changed: Dictionary = doctrines.duplicate(true)
		match mutation:
			"unknown_weapon": changed.items.doctrine_mobile.initial_equipment = {"unknown":1}
			"level_zero": changed.items.doctrine_mobile.initial_passives.movement = 0
			"hp_nan": changed.items.doctrine_mobile.base_hp = NAN
			"speed_negative": changed.items.doctrine_mobile.base_move_speed = -1
			"unlock_mismatch": changed.items.doctrine_mobile.unlock_item_id = "doctrine_artillery"
			"future_schema": changed.schema_version = 99
			"bad_revision": changed.content_revision = "ch01.3"
		var bad = Catalog.new(shop,changed)
		t.check(not bad.validate().is_empty(), "E1 rejects malformed doctrine " + mutation)
		t.check(bad.doctrine("doctrine_standard").is_empty(), "E1 invalid doctrine data fails closed " + mutation)
