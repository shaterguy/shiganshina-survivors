class_name SaveStore
extends RefCounted
const Simulation = preload("res://game/core/run_simulation.gd")
var _directory: String
func _init(directory: String = "user://saves") -> void:
	_directory = directory
func save_checkpoint(snapshot: Dictionary) -> Dictionary:
	var valid: Dictionary = Simulation.new().restore(snapshot)
	if not valid.ok: return {"ok":false,"error_code":"invalid_checkpoint"}
	return _save("checkpoint.json",snapshot)
func load_checkpoint() -> Dictionary:
	return _load("checkpoint.json","snapshot")
func save_profile(profile: Dictionary) -> Dictionary:
	var result := _profile(profile)
	if not result.ok: return result
	return _save("profile.json",result.profile)
func load_profile() -> Dictionary:
	var result := _load("profile.json","profile")
	if result.ok: return result
	if result.error_code != "not_found": return result
	return {"ok":true,"profile":{"schema_version":1,"settings":{"deadzone":0.20,"audio_master":0.8,"screen_shake":0.4,"reduce_effects":false},"cleared_chapter_ids":[],"unlocked_character_ids":["garrison_01"],"best_runs":{}}}
func _save(name: String, value: Dictionary) -> Dictionary:
	var error := DirAccess.make_dir_recursive_absolute(_directory)
	if error != OK: return {"ok":false,"error_code":"directory_failed"}
	var path := _directory.path_join(name)
	var temp := path + ".tmp"
	var backup := path + ".bak"
	var file := FileAccess.open(temp,FileAccess.WRITE)
	if file == null: return {"ok":false,"error_code":"write_failed"}
	file.store_string(JSON.stringify(value,"",true,true))
	file.flush()
	error = file.get_error()
	file.close()
	if error != OK: return {"ok":false,"error_code":"write_failed"}
	var verification := _read(temp, "snapshot" if name == "checkpoint.json" else "profile")
	if not verification.ok: return {"ok":false,"error_code":"verify_failed"}
	if FileAccess.file_exists(path):
		# Never replace a valid backup with an already-corrupt primary.
		var current := _read(path,"snapshot" if name == "checkpoint.json" else "profile")
		if current.ok:
			if FileAccess.file_exists(backup) and DirAccess.remove_absolute(backup) != OK:
				return {"ok":false,"error_code":"backup_failed"}
			if DirAccess.rename_absolute(path,backup) != OK:
				return {"ok":false,"error_code":"backup_failed"}
		else:
			var preserved := path+".corrupt"
			if FileAccess.file_exists(preserved):
				preserved += "."+str(Time.get_unix_time_from_system())
			if DirAccess.rename_absolute(path,preserved) != OK:
				return {"ok":false,"error_code":"preserve_failed"}
	if DirAccess.rename_absolute(temp,path) != OK:
		return {"ok":false,"error_code":"replace_failed"}
	return {"ok":true}
func _load(name: String, key: String) -> Dictionary:
	var path := _directory.path_join(name)
	var first := _read(path,key)
	if first.ok: return first
	var backup := _read(path+".bak",key)
	if backup.ok:
		backup.recovered = true
		return backup
	return first if first.error_code != "not_found" else backup
func _read(path: String, key: String) -> Dictionary:
	if not FileAccess.file_exists(path): return {"ok":false,"error_code":"not_found"}
	var file := FileAccess.open(path,FileAccess.READ)
	if file == null: return {"ok":false,"error_code":"read_failed"}
	if file.get_length() > 16*1024*1024: return {"ok":false,"error_code":"oversize_save"}
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK or not parser.data is Dictionary:
		return {"ok":false,"error_code":"corrupt_save"}
	var data: Dictionary = parser.data
	if key == "snapshot":
		var restored: Dictionary = Simulation.new().restore(data)
		if not restored.ok: return {"ok":false,"error_code":restored.error_code}
		return {"ok":true,"snapshot":restored.state}
	return _profile(data)
func _profile(value: Dictionary) -> Dictionary:
	if value.get("schema_version",0) != 1: return {"ok":false,"error_code":"unsupported_profile"}
	for key in ["settings","best_runs"]:
		if not value.get(key) is Dictionary: return {"ok":false,"error_code":"invalid_profile"}
	for key in ["cleared_chapter_ids","unlocked_character_ids"]:
		if not value.get(key) is Array: return {"ok":false,"error_code":"invalid_profile"}
		for id in value[key]:
			if not id is String: return {"ok":false,"error_code":"invalid_profile"}
	var profile := value.duplicate(true)
	var defaults := {"deadzone":0.20,"audio_master":0.8,"screen_shake":0.4,"reduce_effects":false}
	for key in defaults:
		if not profile.settings.has(key): profile.settings[key] = defaults[key]
	for key in ["deadzone","audio_master","screen_shake"]:
		var number = profile.settings[key]
		if not (number is float or number is int) or not is_finite(float(number)):
			return {"ok":false,"error_code":"invalid_settings"}
		var low := 0.10 if key == "deadzone" else 0.0
		var high := 0.35 if key == "deadzone" else 1.0
		if float(number) < low or float(number) > high:
			return {"ok":false,"error_code":"invalid_settings"}
	if not profile.settings.reduce_effects is bool: return {"ok":false,"error_code":"invalid_settings"}
	return {"ok":true,"profile":profile}
