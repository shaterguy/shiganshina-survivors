extends RefCounted
const Contracts = preload("res://game/contracts/game_save_contracts.gd")
const Store = preload("res://game/persistence/game_save_store.gd")
const Fixture = preload("res://tests/fixtures/evolution_supply_fixture.gd")
# Counting the injected boundary is deliberate: a duplicate call is the bug.
# This SHAPE-only fixture tests contract isolation, not Core/world semantics.
func run(t) -> void:
	var fixture := Fixture.new()
	var calls := [0]
	var checked := func(state):
		calls[0] += 1
		return fixture.validate_checkpoint(state)
	var contracts := Contracts.new(checked)
	var source: Dictionary = fixture.game_save("started")
	var before := source.duplicate(true)
	var normalized: Dictionary = contracts.normalize(source)
	t.check(not normalized.is_empty() and source == before,"reuse normalization preserves valid input and canonical output")
	t.check(calls[0] == 1,"reuse normalization validates the checkpoint exactly once")
	var directory := "/tmp/save_validation_reuse_%s" % Crypto.new().generate_random_bytes(12).hex_encode()
	var path := directory.path_join("game_save.json")
	_write(path,JSON.stringify(source,"",true,true))
	calls[0] = 0
	var store := Store.new(directory,checked)
	var loaded: Dictionary = store.read_game()
	t.check(loaded.get("ok",false),"reuse read still accepts complete valid authority")
	t.check(calls[0] == 1,"reuse one disk read validates the checkpoint exactly once")
	t.check(loaded.get("source_sha256","") == FileAccess.get_file_as_string(path).sha256_text(),"reuse read identity remains actual source byte hash")
	# No result, caller object, or failure may seed a cross-call validation cache.
	loaded.game_save.checkpoint.player.hp = -999
	calls[0] = 0
	var again := store.read_game()
	t.check(again.get("ok",false) and again.game_save.checkpoint.player.hp == source.checkpoint.player.hp and calls[0] == 1,"reuse returned mutable authority cannot poison a subsequent read")
	var switched := [false]
	var volatile_validator := func(state):
		return {"ok":false,"error_code":"world_read_failed"} if switched[0] else fixture.validate_checkpoint(state)
	var volatile_contracts := Contracts.new(volatile_validator)
	t.check(not volatile_contracts.normalize(source).is_empty(),"reuse current external validation succeeds")
	switched[0] = true
	t.check(volatile_contracts.normalize(source).is_empty(),"reuse identical checkpoint must revalidate external authority on later calls")
	var fresh := before.duplicate(true)
	var alias_validator := func(state):
		fresh.profile.supply_credits = 9876
		fresh.checkpoint.player.hp = -999
		return fixture.validate_checkpoint(state)
	var isolated := Contracts.new(alias_validator).normalize(fresh)
	t.check(not isolated.is_empty() and isolated.profile.supply_credits == before.profile.supply_credits and isolated.checkpoint.player.hp == before.checkpoint.player.hp,"reuse binds normalization to the fully checked owned snapshot despite caller alias mutation")
	var poison := before.duplicate(true)
	poison.store_revision = -1
	calls[0] = 0
	t.check(contracts.normalize(poison).is_empty() and calls[0] == 0,"reuse changed invalid revision is rejected before checkpoint validation")
	poison = before.duplicate(true)
	poison.next_run_serial += 1
	t.check(contracts.normalize(poison).is_empty(),"reuse changed run serial cannot borrow validation from prior snapshot")
	poison = before.duplicate(true)
	poison.checkpoint.content_revision = "future-content"
	t.check(contracts.normalize(poison).is_empty(),"reuse future content remains fail-closed")
	_write(path,JSON.stringify(poison,"",true,true))
	t.check(store.read_game().get("error_code") == "content_mismatch","reuse changed source bytes remain a compatibility barrier")
	DirAccess.remove_absolute(path)
	t.check(store.read_game().get("error_code") == "not_found","reuse disappeared source is never resurrected by prior validation")
	DirAccess.remove_absolute(directory)
func _write(path: String, value: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path,FileAccess.WRITE)
	file.store_string(value)
	file.close()
