extends RefCounted
# QA-only observers. None of these functions run inside a Core/Controller timer.

static func observe(state: Dictionary) -> Dictionary:
	if state.is_empty(): return {"state_empty":true}
	var alive := 0
	for actor in state.entities:
		if float(actor.hp) > 0.0: alive += 1
	return {"state_empty":false,"tick":int(state.active_tick),"phase":state.phase,"pause":state.pause_reasons.duplicate(),"upgrade":not state.upgrade_offer.is_empty(),"hp":state.player.hp,"position":state.player.position.duplicate(),"active_records":state.entities.size(),"actual_alive":alive,"dormant_entities":state.get("world",{}).get("dormant",{}).get("entities",[]).size(),"projectiles":state.projectiles.size(),"drops":state.drops.size(),"telegraphs":state.telegraphs.size(),"player_pending":state.player_attack_instances.size(),"enemy_pending":state.enemy_attack_instances.size(),"kills":state.stats.kills,"damage_dealt":state.stats.damage_dealt,"origin_revision":state.get("world",{}).get("origin_revision",-1)}

static func halt(state: Dictionary) -> String:
	if state.is_empty(): return "state_empty"
	if state.phase in ["dead","won","abandoned"]: return "terminated:"+str(state.phase)
	if not state.upgrade_offer.is_empty(): return "upgrade_paused"
	if not state.pause_reasons.is_empty(): return "paused"
	return ""

static func controller_gate(app) -> Dictionary:
	var pending: Dictionary = app._pending_city_tick.duplicate(true)
	if pending.get("move") is Vector2: pending.move = [pending.move.x,pending.move.y]
	return {"startup":not app._startup_view.is_empty(),"transaction":not app._pending_transaction.is_empty(),"worker_recovery":app._worker_recovery_active(),"worker_reserved":app._worker_reserved(),"worker_blocker":app._autosave_blocker,"worker_unknown":not app._autosave_unknown.is_empty(),"worker_intent":not app._autosave_intent.is_empty(),"final_intent":not app._final_intent.is_empty(),"final_error":app._final_error,"city_step_error":app._city_step_error,"city_render_error":app._city_render_error,"pending_city_tick":not pending.is_empty(),"pending_city_tick_detail":pending,"foreground":app._foreground,"lifecycle_blocked":app._lifecycle_blocked(),"shop":app._shop_open,"accumulator":app._accumulator,"worker_enabled":app.autosave_worker_enabled,"store_revision":app.game_save.get("store_revision",-1)}

static func blocking_gate(gate: Dictionary) -> String:
	for key in ["startup","transaction","worker_recovery","final_intent","lifecycle_blocked","shop"]:
		if gate[key]: return key
	for key in ["final_error","city_step_error","city_render_error"]:
		if not str(gate[key]).is_empty(): return key+":"+str(gate[key])
	return ""

static func distribution(values: Array, wall_usec: bool = false) -> Dictionary:
	if values.is_empty(): return {"n":0,"min":null,"mean":null,"p50":null,"p95":null,"p99":null,"max":null}
	var ordered := values.duplicate()
	ordered.sort()
	var sum := 0.0
	var bins := {"over_16667us":0,"over_33333us":0,"over_50000us":0}
	for value in values:
		sum += float(value)
		if value > 16667: bins.over_16667us += 1
		if value > 33333: bins.over_33333us += 1
		if value > 50000: bins.over_50000us += 1
	var result := {"n":values.size(),"min":ordered[0],"mean":sum/values.size(),"p50":ordered[int(ceil(values.size()*0.5))-1],"p95":ordered[int(ceil(values.size()*0.95))-1],"p99":ordered[int(ceil(values.size()*0.99))-1],"max":ordered[-1]}
	if wall_usec: result.merge(bins)
	return result

static func first_difference(left: Variant, right: Variant, path: String = "state") -> Dictionary:
	if typeof(left) != typeof(right): return {"path":path,"reason":"type_mismatch","left_type":typeof(left),"right_type":typeof(right)}
	if left is Dictionary:
		for key in left:
			if not right.has(key): return {"path":path+"."+str(key),"reason":"right_missing"}
			var found := first_difference(left[key],right[key],path+"."+str(key))
			if not found.is_empty(): return found
		for key in right:
			if not left.has(key): return {"path":path+"."+str(key),"reason":"left_missing"}
	elif left is Array:
		if left.size() != right.size(): return {"path":path,"reason":"array_size","left":left.size(),"right":right.size()}
		for index in left.size():
			var found := first_difference(left[index],right[index],path+"[%d]"%index)
			if not found.is_empty(): return found
	elif left != right:
		return {"path":path,"left":String.num(left,17) if left is float else left,"right":String.num(right,17) if right is float else right}
	return {}

static func inside(path: String, directory: String) -> bool:
	var base := directory.trim_suffix("/")
	return path == base or path.begins_with(base+"/")

static func external_json_path(path: String) -> bool:
	var normalized := path.simplify_path()
	return normalized.is_absolute_path() and not normalized.begins_with("res://") and not normalized.begins_with("user://") and normalized.ends_with(".json") and not inside(normalized,ProjectSettings.globalize_path("res://").simplify_path()) and not inside(normalized,ProjectSettings.globalize_path("user://").simplify_path())

static func source_identity(options: Dictionary) -> Dictionary:
	var files := {}
	for directory in ["res://game","res://data","res://chapters"]:
		_hash_tree(directory,files)
	for path in ["res://project.godot","res://tools/qa/dev5_city_crowd_metrics.gd","res://tools/qa/dev5_city_crowd_support.gd"]:
		files[path] = FileAccess.get_sha256(path)
	return {"build_label":options["build-label"],"external_order":options["pair-order"],"external_leg":options["pair-leg"],"project_root":ProjectSettings.globalize_path("res://"),"project_version":ProjectSettings.get_setting("application/config/version","unspecified"),"godot":Engine.get_version_info(),"os":OS.get_name(),"architecture":Engine.get_architecture_name(),"display_server":DisplayServer.get_name(),"engine_arguments":OS.get_cmdline_args(),"processor":"not queried on Termux/proot; host model belongs to the outer MANUAL receipt","processor_metadata_status":"intentionally unqueried","source_file_sha256":files,"source_map_sha256":JSON.stringify(files,"",true,true).sha256_text(),"source_digest_scope":"all gd/json/tscn/tres files below game/data/chapters plus project and both QA scripts; art bytes and binary engine need the outer receipt","recorded_unix_time":Time.get_unix_time_from_system()}

static func _hash_tree(directory: String, files: Dictionary) -> void:
	var opened := DirAccess.open(directory)
	if opened == null: return
	var names := opened.get_files()
	names.sort()
	for file in names:
		if file.get_extension() in ["gd","json","tscn","tres"]:
			var path := directory.path_join(file)
			files[path] = FileAccess.get_sha256(path)
	var folders := opened.get_directories()
	folders.sort()
	for folder in folders:
		_hash_tree(directory.path_join(folder),files)
