extends RefCounted
const PATH := "res://game/presentation/combat_vfx_bridge.gd"
const Fixture = preload("res://tests/core/new_current_regression_fixture.gd")
const CatalogTests = preload("res://tests/presentation_vfx/test_catalog.gd")
const DirectorTests = preload("res://tests/presentation_vfx/test_director.gd")
# Removing successful-tick ingest, snapshot checks, origin synchronization or the
# byte/approval boundary must fail behavior assertions here, not source searches.
func run(t) -> void:
	t.check(FileAccess.file_exists(PATH), "runtime VFX bridge exists")
	var view = load("res://game/presentation/world_view.gd").new()
	t.check(view.has_method("consume_combat_events"), "WorldView accepts successful-tick combat events and snapshot")
	view.free()
	if not FileAccess.file_exists(PATH): return
	var script = load(PATH)
	t.check(script != null and script.can_instantiate(), "runtime VFX bridge loads")
	if script == null or not script.can_instantiate(): return
	var metadata := raster_metadata()
	_real_core(t,script,metadata)
	_freshness_and_lifecycle(t,script,metadata)
	_origin_before_ingest(t,script,metadata)
	_art_boundary(t,script,metadata)
	_projectile_contact(t,script,metadata)
func raster_metadata() -> Dictionary:
	var catalog = load("res://game/presentation/combat_vfx_catalog.gd").new()
	var metadata: Dictionary = CatalogTests.new().manifest_fixture(catalog).assets
	var directory := "/tmp/shiganshina-vfx-bridge-fixtures"
	DirAccess.make_dir_recursive_absolute(directory)
	for id in metadata:
		var asset: Dictionary = metadata[id]
		var image := Image.create(int(asset.width),int(asset.height),false,Image.FORMAT_RGBA8)
		image.fill(Color(0.3,0.8,1.0,0.7))
		asset.path = directory.path_join(id+".png")
		image.save_png(asset.path)
		asset.sha256 = FileAccess.get_sha256(asset.path)
	return metadata
func snapshot(tick: int, seq := 1, run := "run") -> Dictionary:
	var s: Dictionary = DirectorTests.new().snapshot(tick)
	s.event_seq = seq
	s.run_id = run
	s.seed = 42
	s.chapter_id = "chapter_01_shiganshina"
	s.content_revision = "test"
	return s
func attack(seq: int, tick: int, base := "blade_slash", origin := [20,30], run := "run") -> Dictionary:
	var e: Dictionary = DirectorTests.new().attack(seq,base,"",tick,tick,"executed",{"shape":"circle" if base == "spin_slash" else "sector","origin":origin,"direction":[1,0],"radius":54.0,"arc_degrees":150.0})
	e.event_id = run+":"+str(seq)
	e.payload.attack_id = run+":attack:"+str(seq)+":0"
	return e
func events(values: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	result.assign(values)
	return result
func drawable(values: Array) -> Array:
	return values.filter(func(c): return not c.has("diagnostic"))
func _real_core(t,script,metadata: Dictionary) -> void:
	var sim = Fixture.simulation(t)
	var state: Dictionary = sim.new_run(Fixture.chapter(),42,Fixture.run_config())
	var tick_events: Array[Dictionary] = Fixture.step(sim,state,Vector2.ZERO,[Fixture.spawn("target",[45,0],"brute")])
	var current: Dictionary = sim.snapshot(state)
	var before := current.duplicate(true)
	var event_before := tick_events.duplicate(true)
	var bridge = script.new(metadata)
	bridge.consume(tick_events,current)
	var commands: Array = drawable(bridge.present(current))
	t.check(commands.any(func(c): return c.asset_id == "vfx_blade_crescent" and c.role == "cast"), "real Core executed player attack reaches drawable runtime bridge")
	t.check(current == before and tick_events == event_before, "bridge never changes real Core snapshot or event payloads")
	bridge.consume(tick_events,current)
	t.check(drawable(bridge.present(current)).size() == commands.size(), "duplicate successful dispatch cannot duplicate skill commands")
	commands[0].contact_geometry.radius = 999
	t.check(drawable(bridge.present(current))[0].contact_geometry.radius != 999, "runtime commands are caller-isolated copies")
func _freshness_and_lifecycle(t,script,metadata: Dictionary) -> void:
	var bridge = script.new(metadata)
	bridge.consume(events([attack(1,10)]),snapshot(9))
	t.check(drawable(bridge.present(snapshot(9,0))).is_empty(), "previous rendered snapshot cannot accept new-tick cast")
	t.check("event_snapshot_mismatch" in bridge.debug_stats().diagnostics, "stale snapshot refusal is explicit")
	bridge.consume(events([attack(1,10)]),snapshot(10))
	var first: Array = drawable(bridge.present(snapshot(10)))
	t.check(first.size() == 1, "rejected stale batch does not poison valid retry")
	var paused := snapshot(10)
	paused.pause_reasons = ["menu"]
	var frozen: Array = bridge.present(paused)
	t.check(frozen == bridge.present(paused) and drawable(frozen)[0].atlas_region == first[0].atlas_region, "pause age and frame use active tick only")
	t.check(drawable(bridge.present(snapshot(20))).is_empty(), "ordinary cast retires at exclusive active-tick end")
	bridge.consume(events([{"event_id":"run:2","tick":21,"type":"damage","payload":{"target_id":"player","amount":5}}]),snapshot(21,2))
	t.check(not drawable(bridge.present(snapshot(21,2))).any(func(c): return c.role == "cast"), "damage alone never synthesizes a player cast")
	bridge.consume(events([attack(3,22)]),snapshot(22,3))
	t.check(drawable(bridge.present(snapshot(22,3))).any(func(c): return c.role == "cast"), "missed executed attack still displays without a damage event")
	bridge.present(snapshot(10,1))
	t.check(not drawable(bridge.present(snapshot(10,1))).any(func(c): return c.role == "cast"), "decreasing tick clears transient contact effects on restore")
	bridge.consume(events([attack(1,10)]),snapshot(10,1))
	t.check(drawable(bridge.present(snapshot(10,1))).is_empty(), "restore event sequence floor rejects historical replay")
	bridge.consume(events([attack(1,1,"spin_slash",[1,2],"new")]),snapshot(1,1,"new"))
	t.check(drawable(bridge.present(snapshot(1,1,"new")))[0].asset_id == "vfx_spin_double_ring", "new run first batch survives previous run sequence floor")
	bridge.reset()
	t.check(drawable(bridge.present(snapshot(1,1,"new"))).is_empty(), "explicit reset clears all transient casts")
	var present_restored = script.new(metadata)
	present_restored.present(snapshot(10,1))
	present_restored.consume(events([attack(1,10)]),snapshot(10,1))
	t.check(drawable(present_restored.present(snapshot(10,1))).is_empty(), "first restored snapshot establishes historical event floor")
func _origin_before_ingest(t,script,metadata: Dictionary) -> void:
	var bridge = script.new(metadata)
	var old := snapshot(10)
	old.world = {"mode":"streamed_city","stage":"city","origin_chunk":["0","0"],"origin_revision":0}
	bridge.consume(events([attack(1,10)]),old)
	bridge.present(old)
	var current := snapshot(11,2)
	current.world = {"mode":"streamed_city","stage":"city","origin_chunk":["1","0"],"origin_revision":1}
	current.player.position = [-768,0]
	bridge.consume(events([attack(2,11,"spin_slash",[-740,35])]),current)
	var commands: Array = drawable(bridge.present(current))
	t.check(commands.size() == 2, "rebase retains live old cast alongside new-frame cast")
	if commands.size() != 2: return
	t.check(commands.any(func(c): return c.asset_id == "vfx_blade_crescent" and c.world_anchor == Vector2(-748,30)), "cached old effect translates once before new-frame ingest")
	t.check(commands.any(func(c): return c.asset_id == "vfx_spin_double_ring" and c.world_anchor == Vector2(-740,35)), "new origin events never receive old-origin subtraction")
	t.check(commands == drawable(bridge.present(current)), "repeated presentation of same origin cannot double translate")
	t.check(bridge.debug_stats().rebase_count == 1, "one origin revision produces one presentation rebase")
func _art_boundary(t,script,metadata: Dictionary) -> void:
	var source := metadata.duplicate(true)
	source.vfx_spin_double_ring.vfx_approved = false
	source.erase("vfx_cannon_shell")
	var before := source.duplicate(true)
	var bridge = script.new(source)
	bridge.consume(events([attack(1,10),attack(2,10,"spin_slash")]),snapshot(10,2))
	var commands: Array = bridge.present(snapshot(10,2))
	t.check(drawable(commands).size() == 1 and commands.any(func(c): return c.get("diagnostic") == "unapproved_art"), "accepted subset draws while each unapproved art remains diagnostic")
	t.check(source == before, "bridge cannot grant art approval or edit source metadata")
	var corrupt := metadata.duplicate(true)
	corrupt.vfx_blade_crescent.sha256 = "a".repeat(64)
	bridge.set_asset_metadata(corrupt)
	t.check(drawable(bridge.present(snapshot(10,2))).size() == 1 and bridge.present(snapshot(10,2)).any(func(c): return c.get("diagnostic") == "asset_hash_mismatch"), "approved metadata without matching actual bytes cannot draw")
	corrupt.vfx_blade_crescent.path = "/tmp/shiganshina-vfx-missing.png"
	bridge.set_asset_metadata(corrupt)
	t.check(bridge.present(snapshot(10,2)).any(func(c): return c.get("diagnostic") == "missing_raster"), "missing approved raster remains explicit diagnostic")
	bridge.set_asset_metadata(metadata)
	t.check(drawable(bridge.present(snapshot(10,2))).size() == 2, "later accepted art registration actually enables its runtime display")
func _projectile_contact(t,script,metadata: Dictionary) -> void:
	var bridge = script.new(metadata)
	var s := snapshot(10)
	s.projectiles = [{"id":8,"item_id":"wall_cannon","position":[8,0],"velocity":[480,0],"radius":4,"attack_id":"run:attack:1:0"}]
	var launch: Dictionary = DirectorTests.new().attack(1,"wall_cannon","",10,10,"executed",{"shape":"projectile","origin":[0,0],"direction":[1,0],"radius":4,"projectile_id":8})
	bridge.consume(events([launch]),s)
	var shell: Array = drawable(bridge.present(s))
	t.check(shell.size() == 1 and shell[0].world_anchor == Vector2(8,0) and shell[0].projectile_id == 8, "shell follows real projectile and exports exact fallback suppression identity")
	var impact := {"event_id":"run:2","type":"projectile_impact","tick":11,"payload":{"projectile_id":8,"attack_id":"run:attack:1:0","base_item_id":"wall_cannon","position":[12,0],"radius":40}}
	bridge.consume(events([impact]),snapshot(11,2))
	var contact: Array = drawable(bridge.present(snapshot(11,2)))
	t.check(not contact.any(func(c): return c.role == "projectile") and contact.any(func(c): return c.asset_id == "vfx_cannon_contact_blast"), "actual contact removes shell and emits cannon blast on same tick")
	var reduced: Array = drawable(bridge.present(snapshot(11,2),true))
	t.check(reduced.any(func(c): return c.component == "main") and reduced.size() < contact.size(), "reduced mode retains blast identity while omitting dust/detail")
