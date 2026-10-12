extends RefCounted
const Core = preload("res://game/core/run_simulation.gd")
const Chapters = preload("res://game/director/chapter_catalog.gd")
const Roles = preload("res://game/combat/enemy_role_catalog.gd")
const City = preload("res://game/director/streamed_chapter_provider.gd")
const F = preload("res://tests/core/core_fixture.gd")
const CLOCKS := ["warning_ticks","active_ticks","recovery_ticks","cooldown_ticks","airborne_ticks","threat_cost"]
# Deliberately returns its owned chapter directly: Core must make its own copy.
class Provider:
	extends RefCounted
	var chapter: Dictionary
	var failure := false
	func _init(value: Dictionary) -> void: chapter = value
	func load_chapter(_id: String) -> Dictionary:
		return {"ok":false,"error_code":"deliberate_failure"} if failure else {"ok":true,"chapter":chapter}
class Derived:
	extends "res://game/core/run_simulation.gd"
	var profile_calls := 0
	func _normalize_saved_numbers(value: Variant, parent_key := "") -> bool:
		if parent_key.is_empty() and value is Dictionary and value.has("kind"):
			profile_calls += 1
			value["callback_sequence"] = profile_calls
			# The historical caller ignores false and returns the callback result.
			return false
		return super(value,parent_key)
func run(t) -> void:
	var catalog := Chapters.new()
	var actual := catalog.load_chapter(Chapters.CHAPTER_ID)
	t.check(actual.get("ok",false),"actual chapter loads before preparation")
	if not actual.get("ok",false): return
	var provider := Provider.new(actual.chapter)
	var original: PackedByteArray = var_to_bytes(provider.chapter)
	var sim := Core.new(provider)
	t.check(sim._content_error.is_empty(),"actual validated provider is accepted")
	var observations := {}
	for id in Core.LIVE_ROLE_IDS:
		var source: Dictionary = Roles.profile(provider.chapter.enemy_role_catalog,id)
		var expected := source.duplicate(true)
		t.check(sim._normalize_saved_numbers(expected),id+" validated profile normalizes successfully")
		var private_profile: Dictionary = sim._chapter.enemy_role_catalog.roles[id].profile
		for field in CLOCKS:
			t.check(typeof(source[field]) == TYPE_FLOAT,id+" authored JSON clock is float: "+field)
			t.check(typeof(private_profile[field]) == TYPE_INT,id+" private clock is prepared once: "+field)
		var first := sim._role_profile(id)
		t.check(var_to_bytes(first) == var_to_bytes(expected),id+" output exactly matches historical normalization and types")
		for index in 12:
			var again := sim._role_profile(id)
			t.check(var_to_bytes(again) == var_to_bytes(expected),id+" repeated profile remains exact")
		first.length = 98765.25
		first["caller_only"] = []
		t.check(var_to_bytes(sim._role_profile(id)) == var_to_bytes(expected),id+" returned profile mutations never alter later copies")
		t.check(not is_same(sim._role_profile(id),sim._role_profile(id)),id+" each result is an independent dictionary")
		observations[id] = expected
	t.check(var_to_bytes(provider.chapter) == original,"private preparation never mutates provider chapter or catalog")
	var private_except_profiles := sim._chapter.duplicate(true)
	for id in Core.LIVE_ROLE_IDS: private_except_profiles.enemy_role_catalog.roles[id].profile = provider.chapter.enemy_role_catalog.roles[id].profile.duplicate(true)
	t.check(var_to_bytes(private_except_profiles) == original,"only live profiles change; unrelated chapter numbers retain exact types")
	t.check(catalog.definition_digest(sim._chapter) == catalog.definition_digest(provider.chapter),"private preparation preserves canonical chapter hash")
	t.check(sim._chapter.content_fingerprint == provider.chapter.content_fingerprint,"authored content fingerprint is unchanged")
	t.check(sim._current_chapter().get("ok",false),"fresh provider validation accepts prepared private chapter")
	for id in ["walker","runner","sweeper","brute","leaper","unknown",""]:
		t.check(sim._role_profile(id).is_empty(),id+" non-live role still returns empty profile")
	var fresh := Core.new(provider)
	var first_clock: int = int(fresh._role_profile("grabber").warning_ticks)
	sim._chapter.enemy_role_catalog.roles.grabber.profile.warning_ticks += 1
	t.check(int(fresh._role_profile("grabber").warning_ticks) == first_clock,"new Core owns independent prepared profiles")
	t.check(var_to_bytes(provider.chapter) == original,"mutating one private chapter never aliases source")
	_typed_and_distinct(t,actual.chapter,observations)
	_invalid_and_boundaries(t,actual.chapter)
	_callbacks(t,actual.chapter)
	_initial_and_restore(t,actual.chapter,observations)
func _typed_and_distinct(t,chapter: Dictionary,observations: Dictionary) -> void:
	var canonical: Dictionary = Chapters.new()._canonical_numbers(chapter)
	var typed := Core.new(Provider.new(canonical))
	t.check(typed._content_error.is_empty(),"integer-injected chapter remains accepted")
	for id in Core.LIVE_ROLE_IDS:
		var expected := Roles.profile(canonical.enemy_role_catalog,id)
		typed._normalize_saved_numbers(expected)
		t.check(var_to_bytes(typed._role_profile(id)) == var_to_bytes(expected),id+" integer-input output retains historical exact types")
		t.check(typed._same_json(typed._role_profile(id),observations[id]),id+" typed integers and JSON floats are semantically equal")
	var named := chapter.duplicate(true)
	for id in Core.LIVE_ROLE_IDS:
		var keys := {}
		for key in named.enemy_role_catalog.roles[id].profile: keys[StringName(key)] = named.enemy_role_catalog.roles[id].profile[key]
		named.enemy_role_catalog.roles[id].profile = keys
	var named_sim := Core.new(Provider.new(named))
	t.check(named_sim._content_error.is_empty(),"validated StringName profile keys remain accepted")
	for id in Core.LIVE_ROLE_IDS:
		var expected := Roles.profile(named.enemy_role_catalog,id)
		named_sim._normalize_saved_numbers(expected)
		t.check(var_to_bytes(named_sim._role_profile(id)) == var_to_bytes(expected),id+" StringName profile output preserves historical string-key conversion")
		for key in named_sim._role_profile(id): t.check(typeof(key) == TYPE_STRING,id+" returned profile key is canonical String")
	var changed := chapter.duplicate(true)
	changed.enemy_role_catalog.roles.grabber.profile.warning_ticks += 7
	_refresh_role_identity(changed)
	var changed_sim := Core.new(Provider.new(changed))
	t.check(changed_sim._content_error.is_empty(),"separate valid chapter with distinct profile is accepted")
	t.check(changed_sim._role_profile("grabber").warning_ticks == observations.grabber.warning_ticks+7,"separate chapter cannot inherit another Core's profile")
	t.check(changed_sim._chapter.content_fingerprint != typed._chapter.content_fingerprint,"distinct chapter identity remains distinct")
	var legacy := chapter.duplicate(true)
	legacy.enemy_role_catalog.role_revision = "enemy_roles.1"
	legacy.enemy_role_catalog.roles.erase("quadruped")
	legacy.enemy_role_catalog.roles.erase("stone_thrower")
	_refresh_role_identity(legacy)
	var legacy_sim := Core.new(Provider.new(legacy))
	t.check(legacy_sim._content_error.is_empty(),"validated role revision 1 without later live entries remains accepted")
	for id in ["quadruped","stone_thrower"]: t.check(legacy_sim._role_profile(id).is_empty(),id+" absent legacy profile remains empty")
func _invalid_and_boundaries(t,chapter: Dictionary) -> void:
	for value in [-1.0,1.5,1000001.0,2147483648.0,NAN,INF,"18",null]:
		var changed := chapter.duplicate(true)
		changed.enemy_role_catalog.roles.grabber.profile.warning_ticks = value
		_refresh_role_identity(changed)
		var provider := Provider.new(changed)
		var before := var_to_bytes(changed)
		var rejected := Core.new(provider)
		t.check(rejected._content_error == "content_mismatch" and rejected._chapter.is_empty(),"invalid profile is rejected before private preparation: "+str(value))
		t.check(var_to_bytes(changed) == before,"rejected content remains unmodified: "+str(value))
		var result := rejected.new_run(changed,42,F.run_config())
		t.check(result.get("error_code") == "content_mismatch","invalid profile preserves public failure: "+str(value))
	var provider := Provider.new(chapter.duplicate(true)); provider.failure = true
	var failed := Core.new(provider)
	t.check(failed._chapter.is_empty() and failed._content_error == "content_mismatch","failed provider never publishes or prepares a chapter")
	provider = Provider.new(chapter.duplicate(true))
	var sim := Core.new(provider)
	provider.failure = true
	t.check(sim._current_chapter().get("error_code") == "content_mismatch","provider failure after construction still rejects new run/restore boundary")
	provider.failure = false
	provider.chapter.enemy_role_catalog.roles.grabber.profile.warning_ticks += 1
	_refresh_role_identity(provider.chapter)
	t.check(sim._current_chapter().get("error_code") == "content_mismatch","post-init valid provider content changes still fail immutable boundary")
	# Profile schema permits only bounded scalar numbers. Every numeric value
	# that normalization casts is integral, nonnegative and <= 1e6 < MAX_COUNTER.
	for value in [1.0,1000000.0]:
		var bounds := chapter.duplicate(true)
		for field in ["warning_ticks","active_ticks","recovery_ticks","cooldown_ticks"]: bounds.enemy_role_catalog.roles.grabber.profile[field] = value
		_refresh_role_identity(bounds)
		t.check(Roles.validate(bounds.enemy_role_catalog).is_empty(),"clock bound is actually VALIDATED: "+str(value))
		var bounded := Core.new(Provider.new(bounds))
		t.check(bounded._content_error.is_empty(),"validated clock bound reaches Core: "+str(value))
		var profile := Roles.profile(bounds.enemy_role_catalog,"grabber")
		t.check(bounded._normalize_saved_numbers(profile),"validated clock bound cannot hit ignored false: "+str(value))
func _callbacks(t,chapter: Dictionary) -> void:
	var provider := Provider.new(chapter.duplicate(true))
	var derived := Derived.new(provider)
	t.check(derived.profile_calls == 0,"derived normalization callback is not moved into constructor")
	t.check(typeof(derived._chapter.enemy_role_catalog.roles.grabber.profile.warning_ticks) == TYPE_FLOAT,"derived private chapter retains legacy numeric representation")
	for index in 3:
		var profile := derived._role_profile("grabber")
		t.check(profile.callback_sequence == index+1,"derived per-call callback ordering is preserved")
		t.check(typeof(profile.warning_ticks) == TYPE_FLOAT,"ignored false still returns callback-modified, unnormalized result")
	t.check(derived.profile_calls == 3,"derived callback still runs once per requested live profile")
func _initial_and_restore(t,chapter: Dictionary,observations: Dictionary) -> void:
	var sim := Core.new(Provider.new(chapter.duplicate(true)))
	var state := sim.new_run(chapter,42,F.run_config())
	t.check(not state.has("error_code"),"prepared profiles preserve actual finite new_run")
	var disk: Dictionary = JSON.parse_string(JSON.stringify(state,"",true,true))
	var restored := Core.new(Provider.new(chapter.duplicate(true))).restore(disk)
	t.check(restored.get("ok",false),"actual cold restore accepts disk-roundtripped state")
	if not restored.get("ok",false): return
	t.check(JSON.stringify(restored.state,"",true,true) == JSON.stringify(state,"",true,true),"cold restore preserves exact initial canonical state")
	var city_provider := City.new()
	var city := city_provider.load_chapter(Chapters.CHAPTER_ID)
	var city_before := var_to_bytes(city.chapter)
	var city_sim := Core.new(Provider.new(city.chapter))
	var city_state := city_sim.new_run(city.chapter,42,F.run_config())
	t.check(not city_state.has("error_code"),"streamed actual chapter initial load succeeds")
	t.check(var_to_bytes(city.chapter) == city_before,"streamed provider input remains unmodified")
	var output := {"finite_initial":state,"finite_restored":restored.state,"city_initial":city_state,"profiles":observations,"finite_fingerprint":chapter.content_fingerprint,"city_fingerprint":city.chapter.content_fingerprint}
	var path := OS.get_environment("PROFILE_TEST_RESULT")
	if not path.is_empty():
		var file := FileAccess.open(path,FileAccess.WRITE)
		file.store_string(JSON.stringify(output,"\t",true,true)+"\n")
func _refresh_role_identity(chapter: Dictionary) -> void:
	chapter.content_definition_hashes["data/enemy_roles_ch01_3.json"] = Chapters.new().definition_digest(chapter.enemy_role_catalog)
	chapter.content_fingerprint = Chapters.new().definition_digest({"definition_hashes":chapter.content_definition_hashes,"purpose":"isolated_profile_preparation_test"})
