extends "res://tests/corridor_save_integration/save_fixture.gd"
func run(t) -> void:
	for phase in ["ground","glide","rise","over","land"]:
		_phase(t,phase)
		_phase(t,phase,true)
	_phase(t,"over_interior",true)
	_invalid_legacy(t)
	_changed_source(t)
func _phase(t, phase: String, shipped := false) -> void:
	var capture: Dictionary
	if shipped:
		var city: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/corridor_save_integration/fixtures/legacy_city_"+phase+".json"))
		capture = {"source":city.source,"state":city.game_save.checkpoint,"game_save":city.game_save}
	else:
		capture = packet(phase)
	t.check(capture.get("source") == "dev7:38b0cb1","legacy authority fixture provenance is genuine dev7")
	var f := seed_save(t,capture.state,City.new() if shipped else LegacyFixture.Provider.new(),("city_" if shipped else "custom_")+phase,capture.get("game_save",{}))
	if f.is_empty(): return
	var contracts = Contracts.new(Callable(f.runtime,"validate_checkpoint"))
	var frozen: String = JSON.stringify(f.raw,"",true,true)
	var normalized: Dictionary = contracts.normalize(f.raw)
	t.check(not normalized.is_empty(),phase+": full legacy envelope normalizes through actual world/Core validation")
	if normalized.is_empty(): return
	t.check(JSON.stringify(f.raw,"",true,true) == frozen,phase+": normalize never mutates the supplied old save")
	t.check(same(contracts.normalize(normalized),normalized),phase+": migrated normalization is idempotent")
	var read: Dictionary = f.store.read_game()
	t.check(read.get("ok",false),phase+": real store admits old authority")
	if not read.get("ok",false): return
	t.check(read.source_sha256 == f.sha256 and read.source_sha256 != JSON.stringify(read.game_save,"",true,true).sha256_text(),phase+": source hash still identifies original disk bytes, not migrated representation")
	t.check(same(read.game_save,normalized),phase+": disk read and direct normalization agree")
	t.check(FileAccess.get_file_as_string(f.path) == f.text and not FileAccess.file_exists(f.path+".bak") and not FileAccess.file_exists(f.path+".tmp"),phase+": legacy observation causes no save write, backup, or temporary authority")
	var prepared: Dictionary = f.runtime.prepare_load(f.raw)
	t.check(prepared.get("ok",false),phase+": prepare_load admits original version-one envelope")
	if not prepared.get("ok",false): return
	var confirmed: Dictionary = f.runtime.confirm_candidate(f.store)
	t.check(confirmed.get("ok",false),phase+": confirm_candidate accepts exact normalized authority without mismatch")
	if not confirmed.get("ok",false): return
	t.check(confirmed.source_sha256 == f.sha256 and same(confirmed.game_save,normalized),phase+": confirmed source hash and canonical envelope retain distinct identities")
	assert_migration(t,capture.state,confirmed.state,confirmed.simulation,phase)
	var original_safe: bool = confirmed.simulation._streamed.walkable(Vector2(capture.state.player.position[0],capture.state.player.position[1]),8.0).get("walkable",false)
	if phase == "over_interior":
		t.check(not original_safe,"genuine full-city over-interior source is inside a ground-blocking roof")
		var old_start: Dictionary = capture.state.player_mobility.path[0]
		var relative: Dictionary = load("res://game/world/world_address.gd").relative(old_start.chunk,Vector2(old_start.local[0],old_start.local[1]),capture.state.world.origin_chunk)
		t.check(relative.get("ok",false) and confirmed.state.player.position == [relative.local.x,relative.local.y],"genuine full-city roof-interior migration chooses stored safe start")
	elif original_safe:
		t.check(confirmed.state.player.position == capture.state.player.position,phase+": genuine already-clear coordinate is retained before considering route endpoints")
	t.check(confirmed.game_save.profile.supply_credits == 431 and confirmed.game_save.store_revision == f.raw.store_revision,phase+": coins and durable revision are unchanged by migration read")
	t.check(same(confirmed.simulation.snapshot(confirmed.state),confirmed.game_save.checkpoint),phase+": prepared live state equals canonical checkpoint")
	t.check(FileAccess.get_file_as_string(f.path) == f.text,phase+": preparation and confirmation remain read-only")
func _invalid_legacy(t) -> void:
	for kind in ["structure","geometry"]:
		var old: Dictionary = packet("over").state
		if kind == "structure": old.player_mobility.progress = -1.0
		else: old.player_mobility.anchor.prop_id = "city:city_v1:0:0:missing_roof"
		var f := seed_save(t,old,LegacyFixture.Provider.new(),"invalid_"+kind)
		if f.is_empty(): return
		t.check(not f.store.read_game().get("ok",false),"legacy "+kind+" corruption cannot be normalized into a valid grounded save")
		t.check(not f.runtime.prepare_load(f.raw).get("ok",false),"prepare_load rejects legacy "+kind+" corruption before migration")
		t.check(FileAccess.get_file_as_string(f.path) == f.text,"refused legacy "+kind+" corruption remains recoverable in original bytes")
func _changed_source(t) -> void:
	var f := seed_save(t,packet("over").state,LegacyFixture.Provider.new(),"changed_source")
	if f.is_empty(): return
	var prepared: Dictionary = f.runtime.prepare_load(f.raw)
	t.check(prepared.get("ok",false),"source-race test prepares legacy authority")
	if not prepared.get("ok",false): return
	var changed: Dictionary = f.raw.duplicate(true)
	changed.profile.supply_credits += 1
	var bytes := JSON.stringify(changed,"",true,true)
	var file := FileAccess.open(f.path,FileAccess.WRITE)
	file.store_string(bytes); file.close()
	t.check(f.runtime.confirm_candidate(f.store).get("error_code") == "authority_mismatch","same-revision changed economy cannot confirm a prepared migration")
	t.check(FileAccess.get_file_as_string(f.path) == bytes,"rejected stale confirmation cannot overwrite changed authority")
