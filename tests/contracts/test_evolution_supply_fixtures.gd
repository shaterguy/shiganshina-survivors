extends RefCounted
# NEW R0a agreement tests. No production Core, economy or storage validator used.
const Fixture = preload("res://tests/fixtures/evolution_supply_fixture.gd")
const ROOT := "res://tests/fixtures/evolution_supply_grabber/"
const REVISION := "ch01.3-rebuild.7-grabber-hand"
const CAREER := "0123456789abcdef0123456789abcdef"
const RUN_ID := CAREER+":1"
const EQUIPMENT := ["blade_slash","spin_slash","odm_dash","reentry_combo","wall_cannon","ally_cover"]
const PASSIVES := ["damage","fire_interval","movement","max_health","recovery","pickup_radius","attack_range","armor"]
const RUN_FIELDS := ["schema_version","content_revision","chapter_id","character_id","seed","rng_state","active_tick","survival_tick","next_entity_id","event_seq","phase","pause_reasons","player","equipment","passives","entities","projectiles","drops","telegraphs","boss_ids_fired","reward_ids_claimed","command_ids_applied","upgrade_offer","pending_offers","final_started_tick","evacuation_ready","escape_zone","stats","rules","run_id","run_serial","run_config","evolutions","tactical_seals","progression_rng_state","attack_seq","offer_seq","view_revision","player_attack_instances","enemy_attack_instances","evolution_runtime","supply_used"]
const SAVE_FIELDS := ["schema_version","career_id","store_revision","next_run_serial","settled_through_serial","profile","checkpoint","purchase_receipts","settlement_receipts","legacy_checkpoint_present"]
func run(t) -> void:
	print("R0a fixtures: NEW contract agreement only; no real Core/GameSave/world validator.")
	var fixture := Fixture.new()
	var packets := {}
	for name in ["run_v2.json","game_save_v2.json","progression_views.json","progression_source_offers.json","supply_views.json","attack_events.json","content_identity_basis.json","provenance.json"]:
		var parser := JSON.new()
		var parsed := parser.parse(FileAccess.get_file_as_string(ROOT+name))
		t.check(parsed == OK and parser.data is Dictionary,"NEW fixture parses as object: "+name)
		if parsed != OK or not parser.data is Dictionary: return
		packets[name] = parser.data
		t.check(_json_safe(parser.data),"fixture contains only finite JSON values: "+name)
	t.check(_exact_keys(packets["run_v2.json"],["initial"]),"exactly one authored initial run")
	t.check(_exact_keys(packets["game_save_v2.json"],["empty","started"]),"exactly empty and started saves")
	var state: Dictionary = fixture.run_state()
	t.check(state.get("run_id") == RUN_ID,"helper routes initial run case instead of returning packet wrapper")
	var empty: Dictionary = fixture.game_save("empty")
	var started: Dictionary = fixture.game_save("started")
	t.check(empty.get("checkpoint","missing") == null,"helper selects empty authority")
	t.check(started.get("checkpoint") is Dictionary and started.get("next_run_serial") == 2,"helper selects distinct started authority")
	t.check(fixture.game_save() == empty,"legacy initial save alias is explicit empty case")
	t.check(fixture.run_state("missing_case").is_empty(),"unknown run case does not substitute another state")
	t.check(fixture.game_save("missing_case").is_empty(),"unknown save case does not substitute another authority")
	if state.get("run_id") != RUN_ID or not empty.has("profile") or not started.has("profile"): return
	t.check(_exact_keys(state,RUN_FIELDS),"initial run has explicit persistent inventory and no fake world")
	t.check(_run_agreement(state).is_empty(),"initial reference meets R0 contract shape and simple invariants only")
	t.check(_exact_keys(empty,SAVE_FIELDS) and _exact_keys(started,SAVE_FIELDS),"save top-level inventory exact")
	t.check(_save_agreement(empty).is_empty() and _save_agreement(started).is_empty(),"empty/started references meet R0 relationship checks only")
	t.check(started.checkpoint == state,"started checkpoint equals declared reference run")
	t.check(empty.profile == started.profile,"starting without supplies preserves profile")
	t.check(empty.store_revision == 0 and started.store_revision == 1,"one committed start increments store revision once")
	t.check(state.rules.base_hp == 100 and state.player.max_hp == 100 and state.rules.base_move_speed == 150,"standard doctrine hand values 100 HP and speed150")
	t.check(state.equipment.size() == 1 and state.equipment.get("blade_slash") == 1 and state.passives.is_empty(),"standard loadout is blade1 and no passive")
	t.check(_exact_keys(state.run_config,["run_id","run_serial","doctrine_id","target_evolution_id","prepared_supply"]) and state.run_config.run_id == RUN_ID and state.run_config.run_serial == 1 and state.run_config.doctrine_id == "doctrine_standard" and state.run_config.target_evolution_id == "evo_wing_cut" and state.run_config.prepared_supply == "","factory config matches recovered consumer exactly")
	t.check(state.active_tick == 0 and state.survival_tick == 0 and state.event_seq == 0 and state.attack_seq == 0,"initial clocks and attack/event counters are zero")
	t.check(state.final_started_tick == -1 and not state.evacuation_ready,"initial final threat remains unstarted")
	state.player.position[0] = 999
	started.profile.settings.audio_master = 0
	t.check(fixture.run_state().player.position[0] == 0,"run reads do not alias prior returned position")
	t.check(fixture.game_save("started").profile.settings.audio_master == 0.8,"save reads do not alias returned profile")
	t.check(empty.profile.settings.audio_master == 0.8,"empty/started profiles do not alias each other")
	_progression(t,fixture,packets["progression_views.json"])
	_supply(t,fixture,packets["supply_views.json"])
	_attacks(t,fixture,packets["attack_events.json"])
	_hostile_agreement_mutations(t,fixture)
	_shape_fake_scope(t,fixture)
func _progression(t,fixture,packet: Dictionary) -> void:
	t.check(_exact_keys(packet,["missing","blocked","ready","evolved"]),"four authored rendering views only")
	t.check(fixture.has_method("progression_source_offer"),"helper exposes authored source offer for copy/identity agreement")
	if not fixture.has_method("progression_source_offer"): return
	for case_id in packet:
		var view: Dictionary = fixture.progression_view(case_id)
		t.check(_exact_keys(view,["view_revision","slots","target","evolutions","active_offer"]),"progression exact top-level shape: "+case_id)
		t.check(_exact_keys(view.slots,["equipment","passive"]),"UI slots use singular passive: "+case_id)
		t.check(view.slots.equipment.max == 4 and view.slots.passive.max == 4,"four-slot displayed limits: "+case_id)
		var source: Dictionary = fixture.progression_source_offer(case_id)
		t.check(view.active_offer == source,"source upgrade_offer and derived active_offer identity/levels/focus: "+case_id)
		for detail in view.evolutions:
			t.check(detail.evolution_id in ["evo_wing_cut","evo_crossfire"],"stable evolution semantic ID")
			t.check(detail.status in ["unavailable","collecting","blocked","ready","evolved"],"approved status enum")
			t.check(detail.can_evolve == (detail.status == "ready"),"ready is the only evolvable status")
			for requirement in detail.requirements:
				t.check(_exact_keys(requirement,["kind","item_id","name","current","required","met","blocked_reason"]),"requirement exact consumer shape")
				t.check(requirement.met == (requirement.current >= requirement.required),"hand requirement comparison")
		if not source.is_empty():
			t.check(source.options.size() == 1,"single legal example does not invent filler cards")
			t.check(source.selected_option_id == source.options[0].option_id,"semantic selection references present option")
			view.active_offer.options[0].next_level = 999
			t.check(source.options[0].next_level != 999,"mutating view never mutates source offer")
			t.check(fixture.progression_source_offer(case_id).options[0].next_level != 999,"subsequent source read remains unchanged")
	var missing: Dictionary = fixture.progression_view("missing")
	t.check(missing.target.requirements[0].current == 4 and missing.target.requirements[1].current == 2 and missing.target.requirements[2].current == 0,"missing example shows weapon4 passive2 seal0")
	t.check(missing.active_offer.options[0].effect_delta.damage_before == 30 and missing.active_offer.options[0].effect_delta.damage_after == 36,"hand blade4→5 arithmetic 12+3*6 and12+4*6")
	var blocked: Dictionary = fixture.progression_view("blocked")
	t.check(blocked.slots.passive.used == 3 and blocked.active_offer.options[0].can_select,"fourth-slot warning is prospective and legal")
	t.check(blocked.target.status == "collecting" and blocked.target.requirements[1].blocked_reason == "missing_passive","not already slot-blocked before fourth slot is consumed")
	t.check(blocked.active_offer.options[0].slot_warning == "이 선택으로 목표 진화의 필수 기술을 새로 배울 수 없습니다","exact last-slot warning explains consequence")
	t.check(fixture.progression_view("last_slot_warning") == blocked,"new descriptive alias preserves blocked case compatibility")
	var ready: Dictionary = fixture.progression_view("ready")
	t.check(ready.target.status == "ready" and ready.target.requirements[2].current == 1,"ready wing-cut has one seal")
	t.check(ready.active_offer.options[0].option_id == "evolution:evo_wing_cut","ready option is semantic evolution ID")
	var evolved: Dictionary = fixture.progression_view("evolved")
	t.check(evolved.target.status == "evolved" and not evolved.target.can_evolve and evolved.active_offer.is_empty(),"evolved card cannot masquerade as another choice")
	t.check(fixture.progression_view("missing_case").is_empty(),"unknown view stays absent")
func _supply(t,fixture,packet: Dictionary) -> void:
	t.check(_exact_keys(packet,["affordable","insufficient","owned","full"]),"four supplied shop views only")
	for case_id in packet:
		var view: Dictionary = fixture.supply_view(case_id)
		t.check(_exact_keys(view,["view_revision","store_revision","balance","items","loadout","can_shop","lock_reason","legacy_checkpoint_present","loadout_options","can_start","start_blocked_reason"]),"complete shop consumer DTO: "+case_id)
		t.check(view.items.size() == 3 and view.loadout_options.doctrines.size() == 3 and view.loadout_options.targets.size() == 2 and view.loadout_options.supplies.size() == 2,"no fabricated empty loadout options: "+case_id)
		var seen := {}
		for row in view.items:
			t.check(not seen.has(row.item_id),"shop row semantic IDs unique")
			seen[row.item_id] = true
			t.check(row.price == (15 if row.item_id == "field_bandage" else 40),"hand-authored current price")
			t.check(not row.description.is_empty() and not row.tradeoff_text.is_empty(),"cost benefit and tradeoff present")
			t.check(row.balance_after == (view.balance-row.price if row.can_purchase else view.balance),"after balance is authoritative unchanged when blocked")
			t.check(row.can_purchase == row.blocked_reason.is_empty(),"button and reason agree")
	var affordable: Dictionary = fixture.supply_view("affordable")
	var mobile: Dictionary = _row(affordable,"doctrine_mobile")
	t.check(affordable.balance == 40 and mobile.can_purchase and mobile.balance_after == 0,"40 minus40 is0 and affordable")
	mobile = _row(fixture.supply_view("insufficient"),"doctrine_mobile")
	t.check(not mobile.can_purchase and mobile.blocked_reason == "insufficient_funds" and mobile.balance_after == 39,"39 cannot buy40 and stays39")
	mobile = _row(fixture.supply_view("owned"),"doctrine_mobile")
	t.check(mobile.owned == 1 and mobile.blocked_reason == "already_owned" and mobile.balance_after == 40,"owned doctrine cannot debit again")
	var bandage: Dictionary = _row(fixture.supply_view("full"),"field_bandage")
	t.check(bandage.owned == 9 and bandage.blocked_reason == "inventory_full" and bandage.balance_after == 40,"inventory9 is capped without debit")
	t.check(_row(affordable,"field_bandage").balance_after == 25,"40 minus15 is25")
	affordable.loadout_options.targets[0].requirements[0].required = 99
	t.check(fixture.supply_view("affordable").loadout_options.targets[0].requirements[0].required == 5,"nested shop requirements do not alias")
func _attacks(t,fixture,packet: Dictionary) -> void:
	t.check(_exact_keys(packet,["blade","wing_cut","crossfire"]),"three attack cases only; no claimed projectile binding yet")
	t.check(fixture.has_method("attack_reservations"),"new helper exposes saved cast-time records")
	if not fixture.has_method("attack_reservations"): return
	var event_ids := {}
	for case_id in packet:
		for event in fixture.attack_events(case_id):
			t.check(event.type == "player_attack" and str(event.event_id).begins_with(RUN_ID+":"),"event uses run identity and correct type")
			t.check(not event_ids.has(event.event_id),"event IDs unique across illustrative sequence")
			event_ids[event.event_id] = true
			var p: Dictionary = event.payload
			for key in ["cast_id","attack_id","base_item_id","evolution_id","origin","direction","attack_started_tick","execute_tick","stage_index","stage_count","phase","pose_tag","geometry"]:
				t.check(p.has(key),"required attack payload field: "+key)
			t.check(p.attack_id == p.cast_id+":"+str(int(p.stage_index)),"attack stage ID derives from cast")
			t.check(p.geometry.origin == p.origin and p.geometry.direction == p.direction and p.geometry.shape == p.shape,"event geometry matches actual record fields")
			t.check(event.tick == (p.execute_tick if p.phase == "executed" else p.attack_started_tick),"event tick follows scheduled/executed phase")
	var blade: Array = fixture.attack_events("blade")
	t.check(blade.size() == 1 and blade[0].payload.phase == "executed" and blade[0].tick == 100,"base immediate blade emits one actual executed event")
	t.check(blade[0].payload.damage == 12 and blade[0].payload.geometry.radius == 54,"base blade hand values")
	var wing: Array = fixture.attack_reservations("wing_cut")
	t.check(wing.size() == 2 and wing[0].execute_tick == 100 and wing[1].execute_tick == 112,"two wing stages reserve t,t+12")
	t.check(wing[0].damage == 27 and wing[1].damage == 36,"wing damage36*.75=27 then36")
	t.check(wing[0].direction == wing[1].direction and wing[1].origin_binding == "player","wing direction locked and second origin player-bound")
	var wing_events: Array = fixture.attack_events("wing_cut")
	t.check(_point_equal(wing_events[3].payload.origin,[12,0]) and _point_equal(wing[1].origin,[0,0]),"second stage executes from current player position without rewriting cast sample")
	var cross: Array = fixture.attack_reservations("crossfire")
	t.check(cross.size() == 2 and cross[0].execute_tick == 136 and cross[1].execute_tick == 166,"crossfire reserves t+36,t+66")
	t.check(is_equal_approx(cross[0].damage,44.8) and is_equal_approx(cross[1].damage,44.8),"crossfire64*.7=44.8 each")
	t.check(_point_equal(cross[0].origin,[100,-24]) and _point_equal(cross[1].origin,[100,24]),"locked perpendicular offsets are ±24 from100,0")
	for i in 2:
		var executed: Dictionary = fixture.attack_events("crossfire")[i+2].payload
		t.check(executed.origin == cross[i].origin and executed.geometry.radius == 56,"scheduled/executed crossfire contact region agrees")
	cross[0].origin[0] = -999
	t.check(_point_equal(fixture.attack_reservations("crossfire")[0].origin,[100,-24]),"reservation reads deep-copy nested positions")
	wing_events[0].payload.geometry.radius = 999
	t.check(fixture.attack_events("wing_cut")[0].payload.geometry.radius == 88,"event reads deep-copy nested geometry")
func _hostile_agreement_mutations(t,fixture) -> void:
	# This local checker exercises agreement boundaries, not runtime validation.
	var state: Dictionary = fixture.run_state()
	for mutation in ["future_schema","future_revision","missing_field","fraction","nan","overflow","unsupported_item","duplicate_id","impossible_seals"]:
		var bad := state.duplicate(true)
		match mutation:
			"future_schema": bad.schema_version = 3
			"future_revision": bad.content_revision = "ch01.999"
			"missing_field": bad.erase("run_config")
			"fraction": bad.attack_seq = 0.5
			"nan": bad.player.position[0] = NAN
			"overflow": bad.attack_seq = 2147483648
			"unsupported_item": bad.equipment["future_thunder_spear"] = 1
			"duplicate_id": bad.reward_ids_claimed = ["boss:ch01_b05","boss:ch01_b05"]
			"impossible_seals": bad.tactical_seals = 1
		t.check(not _run_agreement(bad).is_empty(),"R0 local agreement rejects mutation: "+mutation)
	var save: Dictionary = fixture.game_save("started")
	save.checkpoint = null
	t.check(not _save_agreement(save).is_empty(),"started authority cannot silently drop unsupported checkpoint to null")
	var receipt := {"request_id":"purchase:"+CAREER+":7:doctrine_mobile","item_id":"doctrine_mobile","expected_revision":7,"price":40,"balance_after":0,"owned_after":1}
	t.check(_purchase_receipt_agreement(receipt,8),"hand receipt refers to prior committed revision7 in authority8")
	receipt.expected_revision = 9
	t.check(not _purchase_receipt_agreement(receipt,8),"stale/conflicting receipt revision and request ID are rejected by local agreement")
	t.check(not _request_is_current("purchase:"+CAREER+":7:doctrine_mobile",7,8,"doctrine_mobile"),"old unrecorded request cannot be minted as a revision8 purchase")
func _shape_fake_scope(t,fixture) -> void:
	print("R0a explicitly exercising SHAPE-ONLY fixture.make_run/validate_checkpoint, not production validation.")
	var state: Dictionary = fixture.run_state()
	var config: Dictionary = state.run_config.duplicate(true)
	config.run_serial = 2
	config.run_id = CAREER+":2"
	var made: Dictionary = fixture.make_run({},73,config)
	t.check(made.run_id == config.run_id and made.run_serial == 2 and made.seed == 73,"test-only make_run adapts supplied identity/seed")
	config.doctrine_id = "changed_after_call"
	t.check(made.run_config.doctrine_id == "doctrine_standard","test factory copies supplied config")
	t.check(not fixture.validate_checkpoint({}).ok,"shape fake rejects missing shape")
	var result: Dictionary = fixture.validate_checkpoint(state)
	t.check(result.ok,"shape fake accepts reference shape, no real validity claim")
	result.state.player.hp = 1
	t.check(state.player.hp == 100,"shape fake returns independent state")
func _row(view: Dictionary,id: String) -> Dictionary:
	for row in view.items:
		if row.item_id == id: return row
	return {}
func _run_agreement(value: Dictionary) -> Array[String]:
	if not _exact_keys(value,RUN_FIELDS): return ["fields"]
	if not _json_safe(value): return ["finite_json"]
	if value.schema_version != 2 or value.content_revision != REVISION: return ["identity"]
	for key in ["active_tick","survival_tick","next_entity_id","event_seq","run_serial","attack_seq","offer_seq","view_revision","tactical_seals"]:
		if not _counter(value[key]): return ["counter"]
	if value.run_id != CAREER+":"+str(int(value.run_serial)) or value.run_config.run_id != value.run_id: return ["run_identity"]
	for kind in ["equipment","passives"]:
		if value[kind].size() > 4: return ["slots"]
		for id in value[kind]:
			if not id in (EQUIPMENT if kind == "equipment" else PASSIVES) or not _counter(value[kind][id]) or value[kind][id] < 1 or value[kind][id] > 5: return ["item"]
	var seen := {}
	var bosses := 0
	for id in value.reward_ids_claimed:
		if seen.has(id): return ["duplicate_id"]
		seen[id] = true
		if str(id).begins_with("boss:"): bosses += 1
	if value.tactical_seals+value.evolutions.size() != bosses or bosses != value.stats.minibosses_defeated or bosses > 5: return ["seal_total"]
	return []
func _save_agreement(value: Dictionary) -> Array[String]:
	if not _exact_keys(value,SAVE_FIELDS) or not _json_safe(value): return ["shape"]
	for key in ["store_revision","next_run_serial","settled_through_serial"]:
		if not _counter(value[key]): return ["counter"]
	if value.checkpoint == null:
		if value.next_run_serial == 1 and value.settled_through_serial == 0: return []
		return ["dropped_checkpoint"]
	if not value.checkpoint is Dictionary or value.checkpoint.run_serial != value.next_run_serial-1 or value.checkpoint.run_id != value.career_id+":"+str(int(value.checkpoint.run_serial)): return ["binding"]
	return []
func _purchase_receipt_agreement(receipt: Dictionary,store_revision: int) -> bool:
	return _counter(receipt.expected_revision) and receipt.expected_revision < store_revision and receipt.request_id == "purchase:%s:%d:%s" % [CAREER,int(receipt.expected_revision),receipt.item_id] and receipt.item_id == "doctrine_mobile" and receipt.price == 40 and receipt.balance_after == 0 and receipt.owned_after == 1
func _request_is_current(id: String,expected: int,current: int,item: String) -> bool:
	return expected == current and id == "purchase:%s:%d:%s" % [CAREER,expected,item]
func _counter(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value >= 0 and value <= 2147483647 and value == floor(value)
func _exact_keys(value: Dictionary,expected: Array) -> bool:
	if value.size() != expected.size(): return false
	for key in expected:
		if not value.has(key): return false
	return true
func _json_safe(value: Variant) -> bool:
	if value == null or value is String or value is bool or value is int: return true
	if value is float: return is_finite(value)
	if value is Array:
		for child in value:
			if not _json_safe(child): return false
		return true
	if value is Dictionary:
		for key in value:
			if not (key is String or key is StringName) or not _json_safe(value[key]): return false
		return true
	return false

func _point_equal(a: Array,b: Array) -> bool:
	return a.size() == 2 and b.size() == 2 and a[0] == b[0] and a[1] == b[1]
