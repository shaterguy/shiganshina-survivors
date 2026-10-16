extends RefCounted
const Address = preload("res://game/world/world_address.gd")
# Draft only. Core must validate the run and perform candidate/commit/ACK.
# Bounded state helpers; no RNG, geometry query or persistence here.
const VERSION := 2
const MAX_POTIONS := 5
const POTION_HEAL := 20.0
const MAX_CHESTS := 10
const MAX_PLACEMENT_CANDIDATES := 16
const PLACEMENT_RETRY_TICKS := 60
const GOLD_PER_CHEST := 5
const MAX_LOOT_GOLD := 50
const FIELD_TICKS := [10800,32400,54000,75600,97200]
const BOSS_IDS := ["ch01_b05","ch01_b10","ch01_b15","ch01_b20","ch01_b25"]

static func xp_tier(amount: int) -> int:
	return 2 if amount >= 80 else (1 if amount >= 10 else 0)

static func xp_scale(amount: int) -> float:
	return 1.0+0.25*float(xp_tier(amount))

static func field_spec(index: int) -> Dictionary:
	if index < 0 or index >= FIELD_TICKS.size(): return {}
	return {"source":"field","source_id":str(FIELD_TICKS[index]),"due_tick":FIELD_TICKS[index],"reward":"gold" if index%2 == 0 else "skill"}

static func boss_spec(boss_id: String) -> Dictionary:
	if boss_id not in BOSS_IDS: return {}
	return {"source":"boss","source_id":boss_id,"reward":"skill"}

static func chest_id(run_id: String, source: String, source_id: String) -> String:
	# Call only with a validated run_id. Unknown sources never receive an ID.
	if source == "boss":
		if source_id not in BOSS_IDS: return ""
	elif source == "field":
		if not source_id.is_valid_int() or str(source_id.to_int()) != source_id or source_id.to_int() not in FIELD_TICKS: return ""
	else: return ""
	return run_id+":chest:"+source+":"+source_id

static func retry_due(active_tick: int, next_retry_tick: int) -> bool:
	return active_tick >= next_retry_tick

static func gold_amount_valid(amount: Variant) -> bool:
	# Godot JSON parses integral numbers as floats; preserve strict integrality.
	if not (amount is int or amount is float): return false
	return is_finite(float(amount)) and float(amount) >= 0.0 and float(amount) <= float(MAX_LOOT_GOLD) and float(amount) == floor(float(amount)) and int(amount)%GOLD_PER_CHEST == 0

static func enabled(state: Dictionary) -> bool:
	var config: Variant = state.get("run_config")
	return config is Dictionary and version_valid(config.get("loot_rules_version"))

static func version_valid(value: Variant) -> bool:
	return _integer(value,1,VERSION)

static func potions_enabled(state: Dictionary) -> bool:
	return enabled(state) and int(state.run_config.loot_rules_version) == 2

static func initial(version: int = 1) -> Dictionary:
	var value := {"chests":[],"next_retry_tick":0,"gold":0}
	if version == 2: value.potions = []
	return value

static func find_chest(state: Dictionary, id: String) -> Dictionary:
	var loot: Variant = state.get("loot")
	if not loot is Dictionary or not loot.get("chests") is Array: return {}
	for chest in loot.chests:
		if chest is Dictionary and chest.get("id") is String and chest.id == id: return chest
	return {}

static func earned_offer_count(state: Dictionary) -> int:
	var count := 0
	for chest in state.get("loot",{}).get("chests",[]):
		if not str(chest.get("offer_id","")).is_empty(): count += 1
	return count

static func local_position(state: Dictionary, chest: Dictionary) -> Dictionary:
	var stage: String = state.get("world",{}).get("stage","finite")
	if chest.stage != stage: return {"ok":false}
	if stage != "city": return {"ok":true,"position":Vector2(chest.position[0],chest.position[1])}
	var relative := Address.relative(chest.address.chunk,Vector2(chest.address.local[0],chest.address.local[1]),state.world.origin_chunk)
	return {"ok":true,"position":relative.local} if relative.get("ok",false) else {"ok":false}

static func set_position(state: Dictionary, chest: Dictionary, point: Vector2) -> bool:
	var stage: String = state.get("world",{}).get("stage","finite")
	if stage == "city":
		var normalized := Address.normalize(state.world.origin_chunk,point)
		if not normalized.get("ok",false): return false
		# Vector2 float32 rounding can turn a tiny negative remainder into 768.
		# Carry that rounded boundary into its adjacent chunk before persistence.
		normalized = Address.normalize(normalized.chunk,normalized.local)
		if not normalized.get("ok",false): return false
		chest.address = {"chunk":normalized.chunk,"local":[normalized.local.x,normalized.local.y]}
		chest.position = [0.0,0.0]
	else:
		chest.address = {}
		chest.position = [point.x,point.y]
	chest.stage = stage
	return true

static func validate(state: Dictionary) -> bool:
	# One cold-boundary validator shared by Core, saves and settlement.
	# This is deliberately not invoked once per live tick or draw.
	if not state.get("run_config") is Dictionary: return false
	var marker: bool = state.run_config.has("loot_rules_version")
	if not marker: return not state.has("loot")
	if not version_valid(state.run_config.loot_rules_version) or not state.get("loot") is Dictionary: return false
	var loot: Dictionary = state.loot
	if not _keys(loot,["chests","next_retry_tick","gold","potions"] if potions_enabled(state) else ["chests","next_retry_tick","gold"]) or not loot.chests is Array or loot.chests.size() > MAX_CHESTS: return false
	if not _integer(loot.next_retry_tick,0,2147483647) or not gold_amount_valid(loot.gold): return false
	if not state.get("run_id") is String or not state.get("reward_ids_claimed") is Array or not state.get("pending_offers") is Array or not state.get("upgrade_offer") is Dictionary: return false
	if not _integer(state.get("survival_tick"),0,108000) or not _integer(state.get("active_tick"),0,2147483647) or not _integer(state.get("offer_seq"),0,2147483647): return false
	if loot.next_retry_tick > mini(2147483647,int(state.active_tick)+PLACEMENT_RETRY_TICKS): return false
	if state.has("world") and (not state.world is Dictionary or not state.world.get("stage") is String or state.world.stage not in ["city","dock"]): return false
	var stage: String = state.get("world",{}).get("stage","finite")
	var terminal: bool = state.get("phase","") in ["dead","won","abandoned"]
	# Offer payloads cross the cold boundary before Growth validates descriptors.
	for offer in state.pending_offers+([state.upgrade_offer] if not state.upgrade_offer.is_empty() else []):
		if not offer is Dictionary or not offer.get("offer_id") is String or not offer.get("source") is String: return false
		if offer.source == "chest" and not offer.get("chest_id") is String: return false
	var seen := {}
	var offer_ids := {}
	var total := 0
	for chest in loot.chests:
		if not chest is Dictionary or not _keys(chest,["id","source","source_id","reward","status","stage","position","address","offer_id","result"]): return false
		for key in ["id","source","source_id","reward","status","stage","offer_id","result"]:
			if not chest[key] is String: return false
		var expected := chest_id(state.run_id,chest.source,chest.source_id)
		if expected.is_empty() or chest.id != expected or seen.has(chest.id): return false
		seen[chest.id] = true
		var spec: Dictionary
		if chest.source == "field":
			spec = field_spec(FIELD_TICKS.find(chest.source_id.to_int()))
			if state.survival_tick < spec.due_tick: return false
		else:
			spec = boss_spec(chest.source_id)
			if not "boss:"+chest.source_id in state.reward_ids_claimed: return false
		if chest.reward != spec.reward or chest.status not in ["pending","placed","queued","claimed","expired"] or chest.stage not in ["city","dock","finite"]: return false
		if (state.has("world") and chest.stage == "finite") or (not state.has("world") and chest.stage != "finite"): return false
		if not _point(chest.position) or not chest.address is Dictionary: return false
		if chest.stage == "city":
			if float(chest.position[0]) != 0.0 or float(chest.position[1]) != 0.0 or not _keys(chest.address,["chunk","local"]) or not chest.address.chunk is Array or not Address.parse(chest.address.chunk).ok or not _point(chest.address.local): return false
			var normalized := Address.normalize(chest.address.chunk,Vector2(chest.address.local[0],chest.address.local[1]))
			if not normalized.get("ok",false) or normalized.chunk != chest.address.chunk or normalized.local != Vector2(chest.address.local[0],chest.address.local[1]): return false
		elif not chest.address.is_empty(): return false
		if chest.status in ["pending","placed"]:
			if chest.stage != stage or not chest.offer_id.is_empty() or not chest.result.is_empty(): return false
		if chest.status == "queued" and (terminal or chest.reward != "skill" or chest.offer_id.is_empty() or not chest.result.is_empty()): return false
		if chest.status == "claimed":
			if chest.result not in ["gold","skill"] or (chest.reward == "gold" and (chest.result != "gold" or not chest.offer_id.is_empty())): return false
			if chest.reward == "skill" and chest.offer_id.is_empty(): return false
			if chest.result == "gold": total += GOLD_PER_CHEST
		elif not chest.result.is_empty(): return false
		if chest.status == "expired":
			if not terminal and (chest.source != "field" or stage != "dock"): return false
			if not chest.offer_id.is_empty() and (not terminal or chest.reward != "skill"): return false
		if not chest.offer_id.is_empty():
			var prefix: String = state.run_id+":offer:"
			if not chest.offer_id.begins_with(prefix) or offer_ids.has(chest.offer_id): return false
			var serial: String = chest.offer_id.trim_prefix(prefix)
			if not serial.is_valid_int() or str(serial.to_int()) != serial or not _integer(serial.to_int(),1,int(state.offer_seq)): return false
			offer_ids[chest.offer_id] = true
			var receipt: bool = "offer:"+chest.offer_id in state.reward_ids_claimed
			if receipt != (chest.status == "claimed"): return false
			var matches := 0
			var offers: Array = state.pending_offers.duplicate()
			if not state.upgrade_offer.is_empty(): offers.append(state.upgrade_offer)
			for offer in offers:
				if not offer is Dictionary: return false
				if offer.get("offer_id","") == chest.offer_id:
					if offer.get("source","") != "chest" or offer.get("chest_id","") != chest.id: return false
					matches += 1
			if matches != (1 if chest.status == "queued" else 0): return false
	for index in range(FIELD_TICKS.size()):
		if state.survival_tick >= FIELD_TICKS[index] and not seen.has(chest_id(state.run_id,"field",str(FIELD_TICKS[index]))): return false
	for boss in BOSS_IDS:
		if "boss:"+boss in state.reward_ids_claimed and not seen.has(chest_id(state.run_id,"boss",boss)): return false
	for offer in state.pending_offers+([state.upgrade_offer] if not state.upgrade_offer.is_empty() else []):
		if not offer is Dictionary: return false
		if offer.get("source","") == "chest" and not offer_ids.has(offer.get("offer_id","")): return false
	return total == int(loot.gold) and (not potions_enabled(state) or _potions_valid(state))

static func _keys(value: Dictionary, keys: Array) -> bool:
	return value.size() == keys.size() and value.has_all(keys)

static func _integer(value: Variant, minimum: int, maximum: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floor(float(value)) and value >= minimum and value <= maximum

static func _point(value: Variant) -> bool:
	if not value is Array or value.size() != 2: return false
	for coordinate in value:
		if not (coordinate is int or coordinate is float) or not is_finite(float(coordinate)) or absf(float(coordinate)) > 10000000.0: return false
	return true

static func transition_valid(before: Dictionary, after: Dictionary) -> bool:
	# Both snapshots have already passed cold-boundary validation.
	if not enabled(before): return not enabled(after)
	if not enabled(after) or after.run_config.loot_rules_version != before.run_config.loot_rules_version or int(after.loot.gold) < int(before.loot.gold): return false
	if potions_enabled(before):
		for previous in before.loot.potions:
			var current := {}
			for potion in after.loot.potions:
				if potion.id == previous.id: current = potion; break
			if current.is_empty(): return false
			for key in ["id","chest_id","stage","position","address","born_tick","heal_amount"]:
				if current[key] != previous[key]: return false
			if previous.status in ["claimed","expired"] and current != previous: return false
	for previous in before.loot.chests:
		var current := find_chest(after,previous.id)
		if current.is_empty(): return false
		for key in ["id","source","source_id","reward"]:
			if current[key] != previous[key]: return false
		if not previous.offer_id.is_empty() and current.offer_id != previous.offer_id: return false
		if previous.status in ["claimed","expired"] and current != previous: return false
		if previous.status == "queued" and current.status not in ["queued","claimed","expired"]: return false
	return true

static func _potions_valid(state: Dictionary) -> bool:
	var potions: Variant = state.loot.get("potions")
	if not potions is Array or potions.size() > MAX_POTIONS: return false
	var seen := {}
	var terminal: bool = state.get("phase","") in ["dead","won","abandoned"]
	var stage: String = state.get("world",{}).get("stage","finite")
	for potion in potions:
		if not potion is Dictionary or not _keys(potion,["id","chest_id","status","stage","position","address","born_tick","heal_amount","healed_amount"]): return false
		for key in ["id","chest_id","status","stage"]:
			if not potion[key] is String: return false
		var chest := find_chest(state,potion.chest_id)
		if chest.is_empty() or chest.source != "field" or chest.status not in ["queued","claimed","expired"]: return false
		if chest.status == "expired" and chest.offer_id.is_empty(): return false
		if potion.id != chest.id+":potion" or seen.has(potion.id): return false
		seen[potion.id] = true
		if not _integer(potion.born_tick,0,int(state.active_tick)) or potion.born_tick < int(chest.source_id): return false
		if not _integer(potion.heal_amount,20,20) or not _number(potion.healed_amount,0.0,POTION_HEAL): return false
		if potion.status not in ["placed","claimed","expired"] or potion.stage != chest.stage: return false
		# Potions never move from the exact opened field chest location.
		if not _point(potion.position) or potion.position != chest.position or not potion.address is Dictionary or potion.address != chest.address: return false
		if potion.status == "placed" and (potion.stage != stage or float(potion.healed_amount) != 0.0): return false
		if potion.status == "claimed" and float(potion.healed_amount) <= 0.0: return false
		if potion.status == "expired" and (float(potion.healed_amount) != 0.0 or (not terminal and stage != "dock")): return false
	for chest in state.loot.chests:
		if chest.source != "field": continue
		var opened: bool = chest.status in ["queued","claimed"] or (chest.status == "expired" and not chest.offer_id.is_empty())
		if opened != seen.has(chest.id+":potion"): return false
	return true

static func _number(value: Variant, minimum: float, maximum: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= minimum and float(value) <= maximum
