extends RefCounted
const Disk = preload("res://game/persistence/world_delta_store.gd")
const Codec = preload("res://game/world/world_delta_codec.gd")
func run(t) -> void:
	var directory := "/tmp/world_prepare_freshness_%s" % Crypto.new().generate_random_bytes(12).hex_encode()
	var disk := Disk.new(directory)
	var records := []
	for i in 24:
		records.append({"chunk":[str(i),"0"],"props":[{"slot_id":"test_slot","hp":1,"destroyed":false}]})
	var initial := disk.prepare(Codec.empty_root(),records,1)
	t.check(initial.get("ok",false),"fresh prepare fixture publishes a real multi-page root")
	if not initial.get("ok",false): return
	var root: Dictionary = initial.receipt.candidate_root
	var root_path := _path(directory,root.root_hash)
	var root_bytes := FileAccess.get_file_as_bytes(root_path)
	var decoded: Dictionary = Codec.decode(root_bytes,root.root_hash)
	t.check(decoded.get("ok",false) and decoded.page.kind == "branch","fresh prepare fixture really contains child pages")
	if not decoded.get("ok",false) or decoded.page.kind != "branch": return
	var child_path := _path(directory,decoded.page.children.back().hash)
	var child_bytes := FileAccess.get_file_as_bytes(child_path)
	t.check(disk.hydrate(root,[["0","0"]]).get("ok",false),"fresh prepare fixture warms root page and delta caches")
	_write(child_path,"{}".to_utf8_buffer())
	var rejected := disk.prepare(root,[],2)
	t.check(not rejected.get("ok",false) and not rejected.has("receipt"),"fresh direct prepare rejects a corrupted warm descendant without publishing receipt")
	t.check(FileAccess.get_file_as_bytes(root_path) == root_bytes and FileAccess.get_file_as_string(child_path) == "{}","fresh failed prepare preserves root and corrupt evidence bytes")
	_write(child_path,child_bytes)
	var retry := disk.prepare(root,[],2)
	t.check(retry.get("ok",false) and retry.receipt.base_root == root and retry.receipt.candidate_root == root,"fresh same-input prepare retries after repairing source without changing root")
func _path(directory: String, hash: String) -> String:
	return directory.path_join("pages").path_join(hash.substr(0,2)).path_join(hash+".json")
func _write(path: String, value: PackedByteArray) -> void:
	var file := FileAccess.open(path,FileAccess.WRITE)
	file.store_buffer(value)
	file.close()
