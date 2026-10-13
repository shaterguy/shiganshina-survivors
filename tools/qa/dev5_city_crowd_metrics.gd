extends SceneTree
# Independent QA only. Original city/runtime/Controller/Core/store classes.
# Writes only fresh /tmp QA saves and an optional external report. No real saves,
# HP refill, offer selection, enemy replenishment, tuning or product edits.
const Core = preload("res://game/core/run_simulation.gd")
const Controller = preload("res://game/app/run_controller.gd")
const City = preload("res://game/director/streamed_chapter_provider.gd")
const Runtime = preload("res://game/app/prepared_city_runtime.gd")
const Disk = preload("res://game/persistence/world_delta_store.gd")
const Save = preload("res://game/persistence/game_save_store.gd")
const NativeDirector = preload("res://game/director/spawn_director.gd")
const Streamed = preload("res://game/core/streamed_run_world.gd")
const S = preload("res://tools/qa/dev5_city_crowd_support.gd")
const CAREER := "0123456789abcdef0123456789abcdef"
const QA_BASE := "/tmp/wings-dev5-crowd-city-qa"
var options := {"mode":"smoke","probe":"controller","counts":[0,32],"seeds":[42],"warm":2,"samples":3,"repeats":1,"families":["walker","runner","brute"],"radius":290.0,"input":"idle","max-trial-seconds":60,"width":800,"height":450,"build-label":"unspecified","pair-order":"unspecified","pair-leg":"unspecified","output":"","raw-series":false}
var argument_error := ""
var run_directory := ""
var trial_sequence := 0

# One setup tick adds QA actors to the real Director's normal planned commands.
# The original Director is restored before any warm or measured tick.
class SetupDirector:
	extends RefCounted
	var native
	var additional: Array[Dictionary] = []
	func plan(state: Dictionary, chapter: Dictionary) -> Array[Dictionary]:
		var result: Array[Dictionary] = native.plan(state,chapter)
		result.append_array(additional)
		return result

# Render mode advances from real Node process callbacks, not a synchronous loop.
class RenderDriver:
	extends Node
	var probe
	var app
	var rows: Array = []
	var warm_completed := 0
	var callbacks := 0
	var draw_sequence := 0
	var done := false
	var stop := ""
	var previous_usec := -1
	var latest: Dictionary = {}
	func _process(delta: float) -> void:
		if done: return
		var now := Time.get_ticks_usec()
		var interval := -1 if previous_usec < 0 else now-previous_usec
		previous_usec = now
		var sample: Dictionary = probe._controller_frame(app,delta)
		sample.callback_interval_us = interval
		sample.draw_sequence_before = draw_sequence
		sample.draw_sequence_after = draw_sequence
		sample.callback_wall_usec = now
		latest = sample
		callbacks += 1
		if callbacks <= int(probe.options.warm): warm_completed += 1
		else: rows.append(sample)
		stop = str(sample.stop)
		if not stop.is_empty() or callbacks >= int(probe.options.warm)+int(probe.options.samples):
			done = true
			set_process(false)
	func after_draw() -> void:
		draw_sequence += 1
		if not latest.is_empty() and latest.draw_sequence_after == latest.draw_sequence_before:
			latest.draw_sequence_after = draw_sequence
			latest.callback_to_post_draw_us = Time.get_ticks_usec()-int(latest.callback_wall_usec)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	if "--help" in OS.get_cmdline_user_args():
		print("dev5_city_crowd_metrics --mode=smoke|measure|verify --probe=core|controller|render --stage=32 --seed=42 --warm=2 --samples=3 --repeats=1 --families=walker,runner,brute --radius=290 --input=idle|right --max-trial-seconds=60 --width=800 --height=450 --build-label=dev4|dev5 --pair-order=AB|BA --pair-leg=A|B --raw-series=0|1 --output=/tmp/unique.json. Measure defaults: counts0,32,64,128,180,256 seeds42,77 warm60 sample120 repeats5. Verify is a separate same-version pair of original city Cores. Render requires a real display and post-draw signals. Exit0=complete protocol,1=setup/argument/pair failure,2=partial/paused/refused/terminated; none is a performance acceptance gate.")
		quit(0)
		return
	_parse_arguments()
	if not argument_error.is_empty():
		print("CITY_CROWD_ARGUMENT_ERROR ",argument_error)
		quit(1)
		return
	if options.probe == "render" and DisplayServer.get_name() == "headless":
		print("CITY_CROWD_RENDER_REFUSED headless display has no real display/render evidence")
		quit(1)
		return
	if options.probe == "render": root.size = Vector2i(options.width,options.height)
	run_directory = QA_BASE.path_join("%d-%d"%[OS.get_process_id(),Time.get_ticks_usec()])
	if DirAccess.dir_exists_absolute(run_directory) or DirAccess.make_dir_recursive_absolute(run_directory) != OK:
		print("CITY_CROWD_SETUP_ERROR fresh QA root unavailable ",run_directory)
		quit(1)
		return
	var identity := S.source_identity(options)
	var trials: Array = []
	var exit_code := 0
	for count in options.counts:
		for seed in options.seeds:
			for repeat in options.repeats:
				var trial: Dictionary = {}
				if options.mode == "verify": trial = await _verify(count,seed,repeat)
				else: trial = await _measure(count,seed,repeat)
				trials.append(trial)
				if trial.get("fatal",false): exit_code = 1
				elif not trial.get("complete",false) and exit_code == 0: exit_code = 2
				print("CITY_CROWD_TRIAL ",JSON.stringify({"probe":options.probe,"mode":options.mode,"requested":count,"seed":seed,"repeat":repeat+1,"result":trial.result,"actual_spawned":trial.get("actual_spawned",0),"sample_count":trial.get("sample_count",0),"complete":trial.complete,"advance_frame_us":trial.get("advance_frame_us",{}),"core_attempts_us":trial.get("core_attempts_us",{})}))
	var ending_identity := S.source_identity(options)
	var stable_sources: bool = identity.source_map_sha256 == ending_identity.source_map_sha256
	if not stable_sources: exit_code = 1
	var report := {"schema_version":1,"identity":identity,"ending_source_map_sha256":ending_identity.source_map_sha256,"source_files_stable_during_process":stable_sources,"options":options,"isolated_QA_root":run_directory,"trials":trials,"exit_code":exit_code,"scope":{"world":"actual streamed city; original terrain/navigation/spawn policy","core_identity":"only original RunSimulation, including coverage replacement; no timer subclass","controller_identity":"original Controller/PreparedRuntime/CityProvider/stores, default worker=true","setup":"normal Save initialize + Controller start; one extra setup Director command batch; native Director thereafter","core_probe":"Controller discarded after normal start/spawn; original Core steps with natural Director; coverage preparation is separately timed; no ongoing Controller/autosave/render in core probe","controller_probe":"one original advance_frame(1/60) per observation, includes snapshot/presentation/audio/coverage/autosave CPU; fixed tick input sequence, not FPS","render_probe":"one original advance_frame(actual delta) per real Node process callback; WorldView/audio process normally; actual frame_post_draw recorded; no GPU fence/present-latency claim","load":"actual actors can die/retire, Director adds normal waves, HP/gear/passives unchanged, no offer choice/refill/replenishment","timing":"CPU wall microseconds, observer and JSON costs excluded from timed calls; observer affects real callback intervals and is separately reported","determinism":"verify mode only, same-version original Core pair raw state/events/status equality; never inside measurement","AB_BA":"external-process labels only; parent runs baseline/candidate both orders with fixed source receipts","acceptance":"no performance/FPS PASS threshold; complete only means this bounded protocol finished","save_scope":"new isolated /tmp QA authorities only, never user/project saves","bounds":"deadline checked between original synchronous calls; outer MANUAL process timeout remains required for a stuck call"}}
	if not options.output.is_empty():
		if FileAccess.file_exists(options.output):
			print("CITY_CROWD_OUTPUT_REFUSED existing report ",options.output)
			exit_code = 1
		else:
			var file := FileAccess.open(options.output,FileAccess.WRITE)
			if file == null: exit_code = 1; print("CITY_CROWD_OUTPUT_ERROR ",FileAccess.get_open_error())
			else:
				file.store_string(JSON.stringify(report,"\t")+"\n")
				if file.get_error() != OK: exit_code = 1; print("CITY_CROWD_OUTPUT_ERROR ",file.get_error())
	report.exit_code = exit_code
	print("CITY_CROWD_REPORT ",JSON.stringify(report))
	quit(exit_code)

func _setup(count: int, seed: int) -> Dictionary:
	trial_sequence += 1
	var directory := run_directory.path_join("trial-%d/saves"%trial_sequence)
	var begin := Time.get_ticks_usec()
	var provider := City.new()
	var disk := Disk.new(directory.path_join("world"))
	var runtime := Runtime.new(provider,disk)
	var initialized: Dictionary = Save.new(directory,Callable(runtime,"validate_checkpoint")).initialize_game({},CAREER)
	if not initialized.get("ok",false): return {"ok":false,"error":"initialize_game_refused","detail":initialized,"directory":directory,"setup_us":Time.get_ticks_usec()-begin}
	var app := Controller.new()
	var configured: Dictionary = app.configure_city_runtime(provider,runtime,disk,directory)
	if not configured.get("ok",false): app.free(); return {"ok":false,"error":"configure_city_refused","detail":configured}
	root.add_child(app)
	app.set_process(false)
	app.start_run(seed)
	var gate := S.controller_gate(app)
	if app.state.is_empty() or not S.blocking_gate(gate).is_empty() or not S.halt(app.state).is_empty():
		var failure := {"ok":false,"error":"normal_start_refused","gate":gate,"observed":S.observe(app.state),"directory":directory,"setup_us":Time.get_ticks_usec()-begin}
		app.free()
		return failure
	if not app.autosave_worker_enabled or app.get_script() != Controller or app.simulation.get_script() != Core or app._city_provider.get_script() != City or app._city_runtime.get_script() != Runtime or app._world_delta_store.get_script() != Disk:
		app.free()
		return {"ok":false,"error":"non_original_identity_or_worker_disabled"}
	var initial_build := {"equipment":app.state.equipment.duplicate(true),"passives":app.state.passives.duplicate(true),"evolutions":app.state.evolutions.duplicate(true),"hp":app.state.player.hp,"position":app.state.player.position.duplicate(),"attack_ready_ticks":app.state.player.attack_ready_ticks.duplicate(true)}
	var commands: Array[Dictionary] = []
	var requested: Array = []
	var origin := Vector2(app.state.player.position[0],app.state.player.position[1])
	for index in count:
		var family: String = options.families[index%options.families.size()]
		if not app.state.rules.enemy_catalog.has(family) or family.begins_with("boss_") or family == Core.FINAL_ENEMY_ID:
			app.free()
			return {"ok":false,"error":"non_ordinary_or_unavailable_family","detail":family}
		var point := origin+Vector2.from_angle(TAU*float(index)/float(maxi(count,1)))*float(options.radius)
		var entity_id := int(app.state.next_entity_id)+index
		var command := {"command_id":"qa-city-crowd:%d"%index,"kind":"spawn_enemy","origin_revision":int(app.state.world.origin_revision),"payload":{"entity_id":entity_id,"enemy_id":family,"position":[point.x,point.y],"spawned_tick":int(app.state.active_tick)+1}}
		commands.append(command)
		requested.append({"entity_id":entity_id,"command_id":command.command_id,"family":family,"requested_position":[point.x,point.y],"radius":app.state.rules.enemy_catalog[family].radius})
	var coverage_start := Time.get_ticks_usec()
	var prepared: Dictionary = runtime.refresh_coverage(app.state,commands)
	var coverage_us := Time.get_ticks_usec()-coverage_start
	if not prepared.get("ok",false): app.free(); return {"ok":false,"error":"setup_coverage_refused","detail":prepared,"setup_coverage_us":coverage_us}
	app.simulation = prepared.simulation
	app.state = prepared.state
	for entry in requested:
		var check: Dictionary = app.simulation._streamed.walkable(Vector2(entry.requested_position[0],entry.requested_position[1]),float(entry.radius))
		entry.requested_walkability = check
		if not check.get("ok",false): app.free(); return {"ok":false,"error":"requested_position_unprepared","entry":entry}
	var native = app.director
	var setup_director := SetupDirector.new()
	setup_director.native = native
	setup_director.additional = commands
	app.director = setup_director
	app.input_router.clear_transient_input()
	app.input_router.set_touch_vector(Vector2.ZERO)
	var before := int(app.state.active_tick)
	var spawn_start := Time.get_ticks_usec()
	app.advance_frame(Controller.TICK_DURATION)
	var spawn_us := Time.get_ticks_usec()-spawn_start
	app.director = native
	var applied := 0
	var actual_spawned := 0
	var actors := {}
	for actor in app.state.entities: actors[str(actor.id)] = actor
	for entry in requested:
		entry.applied = entry.command_id in app.state.command_ids_applied
		if entry.applied: applied += 1
		var actor: Dictionary = actors.get(str(entry.entity_id),{})
		entry.present_after_setup_tick = not actor.is_empty()
		if not actor.is_empty():
			actual_spawned += 1
			entry.post_setup_position = actor.position.duplicate()
			entry.post_setup_hp = actor.hp
	gate = S.controller_gate(app)
	var receipt := {"directory":directory,"requested":count,"actual_spawned":actual_spawned,"commands_applied":applied,"actual_alive_after_setup":S.observe(app.state).get("actual_alive",0),"setup_us":Time.get_ticks_usec()-begin,"setup_coverage_us":coverage_us,"setup_advance_frame_us":spawn_us,"before_tick":before,"after_tick":int(app.state.active_tick),"initial_build":initial_build,"positions":requested,"gate":gate,"step_status":app.simulation.step_status(),"world_status":app.simulation.world_status(),"content_fingerprint":app.chapter.content_fingerprint,"definition_hashes":app.chapter.content_definition_hashes.duplicate(true),"worker_enabled":app.autosave_worker_enabled,"original_core":app.simulation.get_script() == Core,"original_controller":app.get_script() == Controller,"original_director_restored":app.director.get_script() == NativeDirector}
	if int(app.state.active_tick) != before+1 or not app.simulation.step_status().get("ok",false) or not S.blocking_gate(gate).is_empty() or not S.halt(app.state).is_empty() or actual_spawned != count or applied != count or not receipt.original_core or not receipt.original_director_restored:
		app.free()
		return {"ok":false,"error":"setup_tick_or_population_refused","receipt":receipt}
	app.input_router.clear_transient_input()
	app.input_router.set_touch_vector(_movement())
	return {"ok":true,"app":app,"receipt":receipt,"simulation":app.simulation,"state":app.state,"runtime":runtime,"director":native,"chapter":app.chapter,"disk":disk,"provider":provider}

func _base(count: int, seed: int, repeat: int) -> Dictionary:
	return {"requested":count,"seed":seed,"repeat":repeat+1,"legal_active_plus_dormant_cap":Core.MAX_ENTITIES,"requested_within_cap":count <= Core.MAX_ENTITIES,"native_wave_soft_cap":180,"extra_setup_batch":true,"complete":false,"fatal":false,"sample_count":0,"warm_completed":0,"result":"not_started"}

func _measure(count: int, seed: int, repeat: int) -> Dictionary:
	var row := _base(count,seed,repeat)
	var context := _setup(count,seed)
	if not context.get("ok",false): row.merge({"fatal":true,"result":"setup_refused","setup":context},true); return row
	row.setup = context.receipt
	row.actual_spawned = context.receipt.actual_spawned
	if int(context.receipt.setup_us) >= int(options["max-trial-seconds"])*1000000:
		context.app.free()
		row.result = "setup_observation_deadline"
		row.stop = "setup_observation_deadline"
		return row
	var rows: Array = []
	var deadline := Time.get_ticks_usec()+int(options["max-trial-seconds"])*1000000
	var stop := ""
	if options.probe == "core":
		context.app.free()
		context.erase("app")
		for index in int(options.warm)+int(options.samples):
			if Time.get_ticks_usec() >= deadline: stop = "observation_deadline"; break
			stop = S.halt(context.state)
			if not stop.is_empty(): break
			var tick := _core_tick(context)
			if index < int(options.warm): row.warm_completed += int(tick.accepted)
			else: rows.append(tick)
			if not tick.accepted: row.stop_detail = tick; stop = "core_step_refused"; break
			await process_frame
		row.final_observed = S.observe(context.state)
		row.final_world_status = context.simulation.world_status()
		row.final_state_json_sha256 = JSON.stringify(context.state,"",true,true).sha256_text()
		row.final_actor_positions = _actor_positions(context.state)
	elif options.probe == "controller":
		for index in int(options.warm)+int(options.samples):
			if Time.get_ticks_usec() >= deadline: stop = "observation_deadline"; break
			var frame := _controller_frame(context.app,Controller.TICK_DURATION)
			if index < int(options.warm): row.warm_completed += 1
			else: rows.append(frame)
			stop = str(frame.stop)
			if not stop.is_empty() or int(frame.completed_ticks) != 1:
				row.stop_detail = frame
				if stop.is_empty(): stop = "unexpected_fixed_frame_tick_count"
				break
			await process_frame
		row.final_observed = S.observe(context.app.state)
		row.final_gate = S.controller_gate(context.app)
		row.final_world_status = context.app.simulation.world_status()
		row.final_state_json_sha256 = JSON.stringify(context.app.state,"",true,true).sha256_text()
		row.final_actor_positions = _actor_positions(context.app.state)
		row.worker_events = context.app.autosave_events.duplicate(true)
		row.worker_metrics = context.app.autosave_metrics.duplicate(true)
		var cleanup_start := Time.get_ticks_usec()
		context.app.free()
		row.cleanup_us = Time.get_ticks_usec()-cleanup_start
	else:
		var driver := RenderDriver.new()
		driver.probe = self
		driver.app = context.app
		RenderingServer.frame_post_draw.connect(Callable(driver,"after_draw"))
		root.add_child(driver)
		while not driver.done and Time.get_ticks_usec() < deadline:
			await create_timer(0.01).timeout
		driver.set_process(false)
		# Give the last callback's submitted frame its actual post-draw boundary.
		await process_frame
		await process_frame
		rows = driver.rows
		row.warm_completed = driver.warm_completed
		row.real_process_callbacks = driver.callbacks
		row.actual_post_draw_signals = driver.draw_sequence
		stop = driver.stop if driver.done else "observation_deadline"
		if driver.draw_sequence == 0: stop = "no_actual_post_draw_evidence"
		row.final_observed = S.observe(context.app.state)
		row.final_gate = S.controller_gate(context.app)
		row.final_world_status = context.app.simulation.world_status()
		row.final_state_json_sha256 = JSON.stringify(context.app.state,"",true,true).sha256_text()
		row.final_actor_positions = _actor_positions(context.app.state)
		row.worker_events = context.app.autosave_events.duplicate(true)
		RenderingServer.frame_post_draw.disconnect(Callable(driver,"after_draw"))
		driver.free()
		var cleanup_start := Time.get_ticks_usec()
		context.app.free()
		row.cleanup_us = Time.get_ticks_usec()-cleanup_start
	row.stop = stop
	row.sample_count = rows.size()
	row.complete = rows.size() == int(options.samples) and int(row.warm_completed) == int(options.warm) and stop.is_empty() and S.halt({} if not row.has("final_observed") else _halt_projection(row.final_observed)).is_empty()
	row.result = "complete" if row.complete else "halted_or_partial"
	_summarize(row,rows,count)
	if options.probe == "render" and int(row.samples_with_actual_post_draw) != rows.size():
		row.complete = false
		row.stop = "measured_sample_missing_post_draw"
		row.result = "halted_or_partial"
	if options["raw-series"]: row.raw_series = rows
	return row

func _halt_projection(observed: Dictionary) -> Dictionary:
	if observed.get("state_empty",true): return {}
	return {"phase":observed.phase,"pause_reasons":observed.pause,"upgrade_offer":{"present":true} if observed.upgrade else {}}

func _core_tick(context: Dictionary) -> Dictionary:
	var before := int(context.state.active_tick)
	var plan_start := Time.get_ticks_usec()
	var commands: Array[Dictionary] = context.director.plan(context.state,context.chapter)
	var plan_us := Time.get_ticks_usec()-plan_start
	for command in commands:
		if Streamed.spatial_command(command) and not command.has("origin_revision"): command.origin_revision = int(context.state.world.origin_revision)
	var attempts: Array = []
	var statuses: Array = []
	var started := Time.get_ticks_usec()
	var events: Array[Dictionary] = context.simulation.step(context.state,_movement(),commands)
	attempts.append(Time.get_ticks_usec()-started)
	var status: Dictionary = context.simulation.step_status()
	statuses.append(status)
	var refresh_us := 0
	if status.get("error_code","") == "world_not_ready":
		started = Time.get_ticks_usec()
		var refreshed: Dictionary = context.runtime.refresh_coverage(context.state,commands)
		refresh_us = Time.get_ticks_usec()-started
		if refreshed.get("ok",false):
			started = Time.get_ticks_usec()
			events = refreshed.simulation.step(refreshed.state,_movement(),commands)
			attempts.append(Time.get_ticks_usec()-started)
			status = refreshed.simulation.step_status()
			statuses.append(status)
			if status.get("ok",false): context.simulation = refreshed.simulation; context.state = refreshed.state
		else: status = refreshed; statuses.append(status)
	var total := 0
	for value in attempts: total += int(value)
	return {"accepted":status.get("ok",false) and int(context.state.active_tick) == before+1 and context.simulation.get_script() == Core,"before_tick":before,"after_tick":int(context.state.active_tick),"completed_ticks":int(context.state.active_tick)-before,"core_attempts_us":total,"attempt_us":attempts,"coverage_refresh_us":refresh_us,"director_plan_us":plan_us,"statuses":statuses,"commands":commands,"observed":S.observe(context.state),"events":events,"original_core":context.simulation.get_script() == Core}

func _controller_frame(app, delta: float) -> Dictionary:
	var before := int(app.state.get("active_tick",-1))
	var actual_input: Vector2 = app.input_router.sample_move()
	var started := Time.get_ticks_usec()
	app.advance_frame(delta)
	var elapsed := Time.get_ticks_usec()-started
	var observer_start := Time.get_ticks_usec()
	var observed := S.observe(app.state)
	var gate := S.controller_gate(app)
	var stop := S.blocking_gate(gate)
	if stop.is_empty(): stop = S.halt(app.state)
	if app.simulation.get_script() != Core and stop.is_empty(): stop = "non_original_core_identity"
	if actual_input != _movement() and stop.is_empty(): stop = "input_mismatch"
	var result := {"delta_seconds":delta,"advance_frame_us":elapsed,"before_tick":before,"after_tick":int(app.state.get("active_tick",-1)),"completed_ticks":int(app.state.get("active_tick",-1))-before,"actual_input":[actual_input.x,actual_input.y],"observed":observed,"gate":gate,"stop":stop,"step_status":app.simulation.step_status(),"world_status":app.simulation.world_status(),"original_core":app.simulation.get_script() == Core,"original_controller":app.get_script() == Controller,"observer_us":0}
	result.observer_us = Time.get_ticks_usec()-observer_start
	return result

func _summarize(row: Dictionary, rows: Array, nominal: int) -> void:
	for field in ["core_attempts_us","coverage_refresh_us","director_plan_us","advance_frame_us","observer_us","callback_interval_us","callback_to_post_draw_us","completed_ticks"]:
		var series: Array = []
		for sample in rows:
			if sample.has(field) and float(sample[field]) >= 0: series.append(sample[field])
		row[field] = S.distribution(series,field.ends_with("_us"))
	var counts: Array = []
	var zero_ticks := 0
	var refused := 0
	var drawn := 0
	var attempted_refusals: Array = []
	var controller_holds: Array = []
	var refreshed_samples := 0
	for index in rows.size():
		var sample: Dictionary = rows[index]
		counts.append(sample.observed.actual_alive)
		if sample.completed_ticks == 0: zero_ticks += 1
		if sample.has("accepted") and not sample.accepted: refused += 1
		if sample.has("stop") and not str(sample.stop).is_empty(): refused += 1
		if sample.get("draw_sequence_after",0) > sample.get("draw_sequence_before",0): drawn += 1
		if sample.has("statuses"):
			if sample.statuses.size() > 1: refreshed_samples += 1
			for status in sample.statuses:
				if not status.get("ok",false): attempted_refusals.append({"sample":index,"before_tick":sample.before_tick,"status":status,"commands":sample.commands})
		if sample.has("gate") and (sample.completed_ticks == 0 or not str(sample.stop).is_empty()): controller_holds.append({"sample":index,"gate":sample.gate,"stop":sample.stop,"step_status":sample.step_status,"observed":sample.observed})
	row.real_active_alive = S.distribution(counts)
	row.nominal_load_maintained = not counts.is_empty() and counts.min() == nominal and counts.max() == nominal
	row.zero_tick_samples = zero_ticks
	row.refused_or_halted_samples = refused
	row.samples_with_actual_post_draw = drawn
	row.non_ok_core_attempts = attempted_refusals
	row.coverage_retry_samples = refreshed_samples
	row.zero_tick_or_halted_controller_samples = controller_holds
	row.final_digest_scope = "final authority after measurement; only compare identical content/input and accepted tick sequences, never changed fingerprints across versions"

func _verify(count: int, seed: int, repeat: int) -> Dictionary:
	var row := _base(count,seed,repeat)
	var left := _setup(count,seed)
	if not left.get("ok",false): row.merge({"fatal":true,"result":"left_setup_refused","setup":left},true); return row
	var right := _setup(count,seed)
	if not right.get("ok",false): left.app.free(); row.merge({"fatal":true,"result":"right_setup_refused","setup":right},true); return row
	left.app.free(); right.app.free()
	left.erase("app"); right.erase("app")
	row.setup = [left.receipt,right.receipt]
	row.actual_spawned = left.receipt.actual_spawned
	var difference := S.first_difference(left.state,right.state)
	var deadline := Time.get_ticks_usec()+int(options["max-trial-seconds"])*1000000
	var completed := 0
	var stop := ""
	for index in int(options.warm)+int(options.samples):
		if not difference.is_empty(): break
		if Time.get_ticks_usec() >= deadline: stop = "observation_deadline"; break
		stop = S.halt(left.state)
		if not stop.is_empty(): break
		var a := _core_tick(left)
		var b := _core_tick(right)
		for field in ["state","events","statuses"]:
			difference = S.first_difference(left.state if field == "state" else a[field],right.state if field == "state" else b[field],field)
			if not difference.is_empty(): break
		if not difference.is_empty(): break
		if not a.accepted or not b.accepted: stop = "core_step_refused"; break
		completed += 1
		await process_frame
	row.warm_completed = mini(completed,int(options.warm))
	row.sample_count = maxi(0,completed-int(options.warm))
	row.first_difference = difference
	row.fatal = not difference.is_empty()
	row.stop = stop if not stop.is_empty() else S.halt(left.state)
	row.complete = difference.is_empty() and row.stop.is_empty() and row.sample_count == int(options.samples)
	row.result = "same_version_original_city_raw_pair_verified" if row.complete else "pair_failed_or_partial"
	row.final_observed = S.observe(left.state)
	row.final_state_json_sha256 = JSON.stringify(left.state,"",true,true).sha256_text()
	row.verification_scope = "raw state, events and all attempted step statuses each accepted tick; same version, no timing claim; initialization/spawn acceptance separately recorded"
	return row

func _actor_positions(state: Dictionary) -> Array:
	var result: Array = []
	for actor in state.entities:
		result.append({"id":actor.id,"enemy_id":actor.enemy_id,"position":actor.position.duplicate(),"hp":actor.hp})
	return result

func _movement() -> Vector2:
	return Vector2.RIGHT if options.input == "right" else Vector2.ZERO

func _parse_arguments() -> void:
	var explicit := {}
	for arg in OS.get_cmdline_user_args():
		if not arg.begins_with("--") or not "=" in arg: argument_error = "expected --key=value: "+arg; return
		var key: String = arg.substr(2).get_slice("=",0)
		var value: String = arg.substr(arg.find("=")+1)
		if key in ["stage","seed"]: key = "counts" if key == "stage" else "seeds"
		if not options.has(key) or explicit.has(key): argument_error = "unknown/duplicate option: "+key; return
		explicit[key] = true
		if key in ["counts","seeds"]:
			var values: Array = []
			for item in value.split(",",true):
				if not item.is_valid_int() or int(item) < 0 or int(item) > (Core.MAX_ENTITIES if key == "counts" else Core.MAX_COUNTER) or int(item) in values: argument_error = "invalid bounded unique list: "+key; return
				values.append(int(item))
			if values.is_empty(): argument_error = "empty list: "+key; return
			options[key] = values
		elif key in ["warm","samples","repeats","max-trial-seconds","width","height"]:
			if not value.is_valid_int() or int(value) < (0 if key == "warm" else 1) or int(value) > 10000: argument_error = "invalid bounded integer: "+key; return
			options[key] = int(value)
		elif key == "radius":
			if not value.is_valid_float() or not is_finite(float(value)) or float(value) < 64 or float(value) > 512: argument_error = "radius must be 64..512 in the actual city's bounded preparation footprint"; return
			options[key] = float(value)
		elif key == "families":
			var families: Array = []
			for item in value.split(",",true):
				if item.is_empty() or item in families: argument_error = "empty/duplicate family"; return
				families.append(item)
			options[key] = families
		elif key == "raw-series":
			if not value in ["0","1"]: argument_error = "raw-series must be 0|1"; return
			options[key] = value == "1"
		else: options[key] = value
	if options.mode == "measure":
		var defaults := {"counts":[0,32,64,128,180,256],"seeds":[42,77],"warm":60,"samples":120,"repeats":5}
		for key in defaults:
			if not explicit.has(key): options[key] = defaults[key]
	var enums := {"mode":["smoke","measure","verify"],"probe":["core","controller","render"],"input":["idle","right"],"pair-order":["AB","BA","unspecified"],"pair-leg":["A","B","unspecified"]}
	for key in enums:
		if not options[key] in enums[key]: argument_error = "invalid enum: "+key; return
	if options.mode == "verify" and options.probe != "core": argument_error = "verify requires probe=core; asynchronous Controller/render scheduling is separately observed"; return
	if options["build-label"].is_empty(): argument_error = "empty build-label"; return
	if not options.output.is_empty() and (not S.external_json_path(options.output) or FileAccess.file_exists(options.output)):
		argument_error = "output must be a new absolute external QA .json outside project and actual user:// roots"
