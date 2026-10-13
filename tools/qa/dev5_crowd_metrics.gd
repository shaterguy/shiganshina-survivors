extends SceneTree
## Independent QA probe. Run verify-pair and measure-only in separate processes.
## No product edits, gameplay tuning, HP refill, automatic offer selection, save
## routing, rendering or device FPS claims. Timed samples contain one Core.step.
const Core = preload("res://game/core/run_simulation.gd")
const TimedCore = preload("res://tools/qa/dev5_crowd_timed_core.gd")
const F = preload("res://tests/core/new_current_regression_fixture.gd")
const WORLD := {"bounds":[-4096.0,-4096.0,8192.0,8192.0],"obstacles":[]}
const MAX_COMMANDS := 1024
var options := {"mode":"measure-only","engine":"original","counts":[0,32,64,128,180,256],"seeds":[42,77],"warm":60,"samples":120,"repeats":5,"families":["walker","runner","brute"],"workloads":["movement"],"layout":"ring","radius":180.0,"input":"idle","build-label":"unspecified","pair-order":"unspecified","pair-leg":"unspecified","output":"","raw-series":false}
var argument_error := ""

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	if "--help" in OS.get_cmdline_user_args():
		print("dev5_crowd_metrics: --mode=verify-pair|measure-only --engine=original|timed --counts=0,32,64,128,180,256 --stage=180 --seeds=42,77 --seed=42 --warm=60 --samples=120 --repeats=5 --families=walker,runner,brute --workloads=movement,combat --layout=ring|dense --radius=180 --input=idle|right --build-label=dev4|dev5 --pair-order=AB|BA --pair-leg=A|B --output=/tmp/crowd.json --raw-series=0|1. Exit 0=complete, 1=argument/setup/pair failure, 2=partial/refused/paused/terminated. AB/BA are external-process labels, not automatic cross-repository execution.")
		quit(0)
		return
	_parse_arguments()
	if not argument_error.is_empty():
		print("CROWD_ARGUMENT_ERROR ",argument_error)
		quit(1)
		return
	var identity := _identity()
	var trials: Array = []
	var exit_code := 0
	for count in options.counts:
		for seed in options.seeds:
			for workload in options.workloads:
				for repeat in options.repeats:
					var trial: Dictionary = _verify_pair(count,seed,workload,repeat) if options.mode == "verify-pair" else _measure(count,seed,workload,repeat)
					trials.append(trial)
					if trial.get("fatal",false): exit_code = 1
					elif not trial.get("complete",false) and exit_code == 0: exit_code = 2
					print("CROWD_TRIAL ",JSON.stringify({"mode":options.mode,"engine":options.engine,"requested":count,"seed":seed,"workload":workload,"repeat":repeat+1,"result":trial.get("result"),"complete":trial.get("complete",false),"sample_count":trial.get("sample_count",0),"actual_spawned":trial.get("actual_spawned",0),"total_step_us":trial.get("total_step_us",{})}))
	var report := {"schema_version":1,"identity":identity,"options":options,"scope":{"world":"explicit finite_test current-content empty-ground geometry","measurement":"CPU wall microseconds per public Core.step, not FPS","rendered":false,"controller_measured":false,"android_measured":false,"cross_version_state_equality_claimed":false,"AB_BA":"parent must run separate baseline/candidate processes in both orders; labels alone prove no comparison","verify_pair":"same-version original and timer-derived Core raw state/events/status equality; never included in timing mode","timer_totals":"inclusive; instrumentation overhead and derived normalization path prevent treating stage totals as original Core cost","observer":"count/status reads and array appends occur outside step interval; no JSON, snapshot, deep copy or oracle Core inside the measurement loop","load":"real actors may die, pause or terminate; no replenishment or hidden immunity","thresholds":"16.667/33.333/50ms bins are descriptive CPU budgets, not performance acceptance or device FPS"},"trials":trials,"exit_code":exit_code}
	if not options.output.is_empty():
		var file := FileAccess.open(options.output,FileAccess.WRITE)
		if file == null:
			print("CROWD_OUTPUT_ERROR ",options.output," ",FileAccess.get_open_error())
			exit_code = 1
		else:
			file.store_string(JSON.stringify(report,"\t")+"\n")
			if file.get_error() != OK:
				print("CROWD_OUTPUT_ERROR ",options.output," ",file.get_error())
				exit_code = 1
	report.exit_code = exit_code
	print("CROWD_REPORT ",JSON.stringify(report))
	quit(exit_code)

func _identity() -> Dictionary:
	var source: String = FileAccess.get_file_as_string("res://game/core/run_simulation.gd")
	var derived_guards := "get_script() == load(\"res://game/core/run_simulation.gd\")" in source or "get_script() != load(\"res://game/core/run_simulation.gd\")" in source
	var definitions := {}
	for path in Core.GAMEPLAY_PATHS:
		definitions[path] = FileAccess.get_file_as_string("res://"+path).sha256_text()
	return {"build_label":options["build-label"],"external_order":options["pair-order"],"external_leg":options["pair-leg"],"project_root":ProjectSettings.globalize_path("res://"),"project_version":ProjectSettings.get_setting("application/config/version","unspecified"),"godot":Engine.get_version_info(),"os":OS.get_name(),"architecture":Engine.get_architecture_name(),"processor":"not queried on Termux/proot; host model belongs to the outer MANUAL receipt","processor_metadata_status":"intentionally unqueried; no performance sample omitted","core_sha256":source.sha256_text(),"timer_sha256":FileAccess.get_file_as_string("res://tools/qa/dev5_crowd_timed_core.gd").sha256_text(),"probe_sha256":get_script().source_code.sha256_text(),"fixture_sha256":FileAccess.get_file_as_string("res://tests/core/new_current_regression_fixture.gd").sha256_text(),"gameplay_file_sha256":definitions,"max_entities":Core.MAX_ENTITIES,"max_spawn_commands_per_step":MAX_COMMANDS,"engine_identity":"original-plus-derived verification pair" if options.mode == "verify-pair" else ("original RunSimulation" if options.engine == "original" else "QA derived timer Core"),"original_script_identity":options.mode == "measure-only" and options.engine == "original","source_has_script_identity_normalization_guard":derived_guards,"normalization_path":"verify-pair covers both paths without timing claims" if options.mode == "verify-pair" else ("no explicit script-identity guard found" if not derived_guards else ("original initializer fast path" if options.engine == "original" else "derived callback normalization path; diagnostic stages only")),"recorded_unix_time":Time.get_unix_time_from_system()}

func _new_fixture(script, seed: int, workload: String, count: int) -> Dictionary:
	var provider = F.GeometryProvider.new(WORLD,[0.0,0.0])
	var chapter: Dictionary = provider.load_chapter("chapter_01_shiganshina").get("chapter",{})
	var sim = script.new(provider)
	var state: Dictionary = sim.new_run(chapter,seed,F.run_config())
	if state.has("error_code"): return {"ok":false,"error":"new_run","detail":state}
	for family in options.families:
		if not state.rules.enemy_catalog.has(family) or family.begins_with("boss_") or family == Core.FINAL_ENEMY_ID:
			return {"ok":false,"error":"unavailable_or_nonordinary_family","detail":family}
	# Explicit enemy-movement-only arrangement. Standard Lv1 build is retained;
	# only its ready tick is delayed, then accepted by the real restore validator.
	if workload == "movement":
		for id in state.equipment: state.player.attack_ready_ticks[id] = Core.MAX_COUNTER
	var checked: Dictionary = sim.restore(state)
	if not checked.get("ok",false): return {"ok":false,"error":"arrangement_restore","detail":checked}
	var commands: Array[Dictionary] = []
	for index in count:
		var position := Vector2(options.radius,0.0)
		if options.layout == "ring": position = position.rotated(TAU*float(index)/float(maxi(count,1)))
		commands.append(F.spawn("crowd:%d"%index,[position.x,position.y],options.families[index%options.families.size()]))
	var before := int(state.active_tick)
	var events: Array[Dictionary] = sim.step(state,Vector2.ZERO,commands)
	var status: Dictionary = sim.step_status()
	if not status.get("ok",false) or int(state.active_tick) != before+1:
		return {"ok":false,"error":"spawn_step_refused","detail":status,"observed":_observe(state)}
	return {"ok":true,"sim":sim,"state":state,"spawn_events":events,"spawn_status":status,"spawned":state.entities.size(),"fingerprint":chapter.content_fingerprint,"definition_hashes":chapter.content_definition_hashes.duplicate(),"initial_equipment":state.equipment.duplicate(),"initial_passives":state.passives.duplicate(),"suppressed_player_attacks":workload == "movement"}

func _trial_base(count: int, seed: int, workload: String, repeat: int) -> Dictionary:
	return {"requested":count,"legal_entity_cap":Core.MAX_ENTITIES,"requested_within_entity_cap":count <= Core.MAX_ENTITIES,"seed":seed,"workload":workload,"repeat":repeat+1,"complete":false,"fatal":false,"sample_count":0,"warm_completed":0}

func _measure(count: int, seed: int, workload: String, repeat: int) -> Dictionary:
	var row := _trial_base(count,seed,workload,repeat)
	var arranged := _new_fixture(Core if options.engine == "original" else TimedCore,seed,workload,count)
	if not arranged.get("ok",false):
		row.merge({"result":"setup_failed","fatal":true,"setup":arranged},true)
		return row
	var sim = arranged.sim
	var state: Dictionary = arranged.state
	row.merge(_setup_receipt(arranged))
	var samples: Array = []
	var real_counts: Array = []
	var projectile_counts: Array = []
	var attack_counts: Array = []
	var event_counts: Array = []
	var role_work: Array = []
	var stages := {}
	var calls := {}
	for stage in TimedCore.TIMER_STAGES:
		stages[stage] = []
		calls[stage] = []
	var stop := {}
	var last_status: Dictionary = arranged.spawn_status
	var start_tick := int(state.active_tick)
	for index in options.warm+options.samples:
		stop = _halt_reason(state)
		if not stop.is_empty(): break
		if options.engine == "timed": sim.begin_timer_tick()
		var before := int(state.active_tick)
		var movement := _movement()
		var no_commands: Array[Dictionary] = []
		var started := Time.get_ticks_usec()
		var events: Array[Dictionary] = sim.step(state,movement,no_commands)
		var elapsed := Time.get_ticks_usec()-started
		last_status = sim.step_status()
		if not last_status.get("ok",false) or int(state.active_tick) != before+1:
			stop = {"reason":"step_refused","before_tick":before,"after_tick":state.active_tick,"refused_step_us":elapsed,"status":last_status}
			break
		if index < options.warm:
			row.warm_completed += 1
		else:
			samples.append(elapsed)
			real_counts.append(state.entities.size()) # Core removes dead actors before return.
			projectile_counts.append(state.projectiles.size())
			attack_counts.append(state.player_attack_instances.size()+state.enemy_attack_instances.size())
			event_counts.append(events.size())
			role_work.append(last_status.get("role_admission",{}).get("work_units",0))
			if options.engine == "timed":
				for stage in TimedCore.TIMER_STAGES:
					stages[stage].append(sim.timer_us.get(stage,0))
					calls[stage].append(sim.timer_calls.get(stage,0))
	row.sample_count = samples.size()
	if stop.is_empty(): stop = _halt_reason(state)
	row.complete = samples.size() == int(options.samples) and int(row.warm_completed) == int(options.warm) and arranged.spawned == count
	row.result = ("complete" if stop.is_empty() else "complete_with_final_halt") if row.complete else ("spawn_count_mismatch" if arranged.spawned != count and stop.is_empty() else "halted_or_partial")
	row.total_step_us = _distribution(samples,true)
	row.real_active_alive_count = _distribution(real_counts)
	row.nominal_load_maintained = not real_counts.is_empty() and real_counts.min() == count and real_counts.max() == count
	row.projectile_count = _distribution(projectile_counts)
	row.pending_attack_count = _distribution(attack_counts)
	row.events_per_step = _distribution(event_counts)
	row.role_admission_work_units = _distribution(role_work)
	row.tick_range = [start_tick,state.active_tick]
	row.stop = stop
	row.final_observed = _observe(state)
	row.final_step_status = last_status
	row.final_state_json_sha256 = JSON.stringify(state,"",true,true).sha256_text()
	row.digest_scope = "final authority only, computed after timing loop; compare within identical content/version/input, not across changed fingerprints"
	if options.engine == "timed":
		row.diagnostic_inclusive_stage_us = {}
		row.stage_calls = {}
		for stage in TimedCore.TIMER_STAGES:
			row.diagnostic_inclusive_stage_us[stage] = _distribution(stages[stage],true)
			row.stage_calls[stage] = _distribution(calls[stage])
	if options["raw-series"]:
		row.raw_series = {"step_us":samples,"real_alive_count":real_counts,"projectiles":projectile_counts,"pending_attacks":attack_counts,"events":event_counts,"role_work_units":role_work}
		if options.engine == "timed": row.raw_series.merge({"stage_us":stages,"stage_calls":calls})
	return row

func _verify_pair(count: int, seed: int, workload: String, repeat: int) -> Dictionary:
	var row := _trial_base(count,seed,workload,repeat)
	var original := _new_fixture(Core,seed,workload,count)
	var instrumented := _new_fixture(TimedCore,seed,workload,count)
	if not original.get("ok",false) or not instrumented.get("ok",false):
		row.merge({"result":"setup_failed","fatal":true,"original_setup":_without_authority(original),"instrumented_setup":_without_authority(instrumented)},true)
		return row
	row.merge(_setup_receipt(original))
	var a: Dictionary = original.state
	var b: Dictionary = instrumented.state
	var verified_event_trace: Array = [original.spawn_events.duplicate(true)]
	if a != b or original.spawn_events != instrumented.spawn_events or original.spawn_status != instrumented.spawn_status:
		row.merge({"result":"spawn_pair_mismatch","fatal":true,"state_difference":_first_difference(a,b,"state"),"event_difference":_first_difference(original.spawn_events,instrumented.spawn_events,"events"),"status_difference":_first_difference(original.spawn_status,instrumented.spawn_status,"status")},true)
		return row
	for index in options.warm+options.samples:
		var halt := _halt_reason(a)
		if not halt.is_empty():
			row.merge({"result":"paired_halt","stop":halt,"final_observed":_observe(a)},true)
			return row
		instrumented.sim.begin_timer_tick()
		var before := int(a.active_tick)
		var no_commands: Array[Dictionary] = []
		var events_a: Array[Dictionary] = original.sim.step(a,_movement(),no_commands)
		var events_b: Array[Dictionary] = instrumented.sim.step(b,_movement(),no_commands)
		var status_a: Dictionary = original.sim.step_status()
		var status_b: Dictionary = instrumented.sim.step_status()
		if a != b or events_a != events_b or status_a != status_b:
			row.merge({"result":"pair_mismatch","fatal":true,"relative_tick":index+1,"state_difference":_first_difference(a,b,"state"),"event_difference":_first_difference(events_a,events_b,"events"),"status_difference":_first_difference(status_a,status_b,"status")},true)
			return row
		if not status_a.get("ok",false) or int(a.active_tick) != before+1:
			row.merge({"result":"paired_refusal","stop":{"before_tick":before,"after_tick":a.active_tick,"status":status_a},"final_observed":_observe(a)},true)
			return row
		verified_event_trace.append(events_a.duplicate(true))
		if index < options.warm: row.warm_completed += 1
		else: row.sample_count += 1
	row.complete = original.spawned == count
	row.result = "exact_pair_verified" if row.complete else "spawn_count_mismatch"
	row.raw_state_events_and_status_equal = true
	row.final_observed = _observe(a)
	row.post_verification_halt = _halt_reason(a)
	row.final_state_json_sha256 = JSON.stringify(a,"",true,true).sha256_text()
	row.verified_events_json_sha256 = JSON.stringify(verified_event_trace,"",true,true).sha256_text()
	row.digest_scope = "same-version pair, spawn plus every completed warm/sample tick; exact equality checked before JSON digests"
	return row

func _setup_receipt(arranged: Dictionary) -> Dictionary:
	return {"actual_spawned":arranged.spawned,"content_fingerprint":arranged.fingerprint,"definition_hashes":arranged.definition_hashes,"initial_equipment":arranged.initial_equipment,"initial_passives":arranged.initial_passives,"suppressed_player_attacks":arranged.suppressed_player_attacks,"spawn_status":arranged.spawn_status}

func _without_authority(value: Dictionary) -> Dictionary:
	var result := value.duplicate()
	for key in ["sim","state","spawn_events"]: result.erase(key)
	return result

func _movement() -> Vector2:
	return Vector2.RIGHT if options.input == "right" else Vector2.ZERO

func _halt_reason(state: Dictionary) -> Dictionary:
	if state.phase in ["dead","won","abandoned"]: return {"reason":"terminated","phase":state.phase}
	if not state.upgrade_offer.is_empty(): return {"reason":"upgrade_paused","offer_id":state.upgrade_offer.get("offer_id",""),"pause_reasons":state.pause_reasons.duplicate()}
	if not state.pause_reasons.is_empty(): return {"reason":"paused","pause_reasons":state.pause_reasons.duplicate()}
	return {}

func _observe(state: Dictionary) -> Dictionary:
	return {"active_tick":state.active_tick,"phase":state.phase,"player_hp":state.player.hp,"player_position":state.player.position.duplicate(),"actual_active_alive":state.entities.size(),"projectiles":state.projectiles.size(),"drops":state.drops.size(),"telegraphs":state.telegraphs.size(),"player_pending":state.player_attack_instances.size(),"enemy_pending":state.enemy_attack_instances.size(),"pause_reasons":state.pause_reasons.duplicate(),"has_upgrade_offer":not state.upgrade_offer.is_empty(),"kills":state.stats.kills,"damage_dealt":state.stats.damage_dealt,"dormant_entities":state.get("world",{}).get("dormant",{}).get("entities",[]).size()}

func _distribution(values: Array, time_values: bool = false) -> Dictionary:
	if values.is_empty(): return {"n":0,"min":null,"mean":null,"p50":null,"p95":null,"p99":null,"max":null}
	var sorted := values.duplicate()
	sorted.sort()
	var total := 0.0
	var over := {"over_16_667ms":0,"over_33_333ms":0,"over_50ms":0}
	for value in values:
		total += float(value)
		if value > 16667: over.over_16_667ms += 1
		if value > 33333: over.over_33_333ms += 1
		if value > 50000: over.over_50ms += 1
	var result := {"n":values.size(),"min":sorted[0],"mean":total/values.size(),"p50":sorted[int(ceil(values.size()*0.50))-1],"p95":sorted[int(ceil(values.size()*0.95))-1],"p99":sorted[int(ceil(values.size()*0.99))-1],"max":sorted[-1]}
	if time_values: result.merge(over)
	return result

func _first_difference(left: Variant, right: Variant, path: String) -> Dictionary:
	if typeof(left) != typeof(right): return {"path":path,"reason":"type_mismatch","left_type":typeof(left),"right_type":typeof(right)}
	if left is Dictionary and right is Dictionary:
		for key in left:
			if not right.has(key): return {"path":path+"."+str(key),"reason":"right_missing"}
			var found := _first_difference(left[key],right[key],path+"."+str(key))
			if not found.is_empty(): return found
		for key in right:
			if not left.has(key): return {"path":path+"."+str(key),"reason":"left_missing"}
	elif left is Array and right is Array:
		if left.size() != right.size(): return {"path":path,"left_size":left.size(),"right_size":right.size()}
		for index in left.size():
			var found := _first_difference(left[index],right[index],path+"[%d]"%index)
			if not found.is_empty(): return found
	elif left != right:
		return {"path":path,"left":String.num(left,17) if left is float else left,"right":String.num(right,17) if right is float else right}
	return {}

func _parse_arguments() -> void:
	for arg in OS.get_cmdline_user_args():
		if not arg.begins_with("--") or not "=" in arg:
			argument_error = "expected --key=value: "+arg
			return
		var key: String = arg.substr(2).get_slice("=",0)
		var value: String = arg.substr(arg.find("=")+1)
		if key in ["stage","seed"]: key = "counts" if key == "stage" else "seeds"
		if not options.has(key):
			argument_error = "unknown option: "+key
			return
		if key in ["counts","seeds"]:
			var values: Array = []
			for text_value in value.split(",",true):
				if not text_value.is_valid_int(): argument_error = "invalid integer: "+value; return
				var number := int(text_value)
				if number < 0 or number > (MAX_COMMANDS if key == "counts" else Core.MAX_COUNTER): argument_error = "out of range: "+value; return
				if number in values: argument_error = "duplicate integer: "+value; return
				values.append(number)
			if values.is_empty(): argument_error = "empty list: "+key; return
			options[key] = values
		elif key in ["warm","samples","repeats"]:
			if not value.is_valid_int() or int(value) < (0 if key == "warm" else 1) or int(value) > 10000: argument_error = "invalid bounded count: "+key; return
			options[key] = int(value)
		elif key in ["families","workloads"]:
			var values: Array = []
			for item in value.split(",",true):
				if item.is_empty() or item in values: argument_error = "empty/duplicate list item: "+key; return
				values.append(item)
			if values.is_empty(): argument_error = "empty list: "+key; return
			options[key] = values
		elif key == "radius":
			if not value.is_valid_float() or not is_finite(float(value)) or float(value) < 40 or float(value) > 3500: argument_error = "radius must be 40..3500"; return
			options[key] = float(value)
		elif key == "raw-series":
			if not value in ["0","1"]: argument_error = "raw-series must be 0 or 1"; return
			options[key] = value == "1"
		else:
			options[key] = value
	for key in ["mode","engine","layout","input","pair-order","pair-leg"]:
		var allowed := {"mode":["verify-pair","measure-only"],"engine":["original","timed"],"layout":["ring","dense"],"input":["idle","right"],"pair-order":["AB","BA","unspecified"],"pair-leg":["A","B","unspecified"]}
		if not options[key] in allowed[key]: argument_error = "invalid enum: "+key; return
	for workload in options.workloads:
		if not workload in ["movement","combat"]: argument_error = "unknown workload: "+str(workload); return
	if options["build-label"].is_empty(): argument_error = "empty build-label"; return
	if not options.output.is_empty():
		var path: String = options.output.simplify_path()
		var project_root := ProjectSettings.globalize_path("res://").simplify_path()
		var user_root := ProjectSettings.globalize_path("user://").simplify_path()
		if not path.is_absolute_path() or path.begins_with("user://") or path.begins_with("res://") or _inside_directory(path,project_root) or _inside_directory(path,user_root) or not path.ends_with(".json"):
			argument_error = "output must be an absolute external QA .json path outside this project and actual user/res save roots"

func _inside_directory(path: String, directory: String) -> bool:
	var base := directory.trim_suffix("/")
	return path == base or path.begins_with(base+"/")
