class_name WorldDeltaIndex
extends RefCounted
const Codec = preload("res://game/world/world_delta_codec.gd")
const Address = preload("res://game/world/world_address.gd")
var _read: Callable
var _write: Callable
var _hasher: Callable
const WRITE_SEQUENCE_DOMAIN := "world_delta_write_sequence_v1\n"
var _write_sequence: HashingContext
var _page_write_calls := 0
var _collision_pages_scanned := 0
var _peak_collision_window_records := 0
func _init(read_page: Callable, write_page: Callable, key_hasher: Callable = Callable()) -> void:
	_read = read_page
	_write = write_page
	_hasher = key_hasher
func lookup(root: Dictionary, chunk: Array) -> Dictionary:
	var valid := Codec.valid_root(root)
	if not valid.ok: return valid
	if not Address.parse(chunk).ok: return Codec.fail("world_page_invalid")
	var digest := _key_hash(chunk)
	if not Codec.valid_hash(digest): return Codec.fail("world_page_invalid")
	var hash: String = root.root_hash
	var depth := 0
	while true:
		var loaded: Dictionary = _read.call(hash)
		if not loaded.ok: return loaded
		var page: Dictionary = loaded.page
		if page.kind == "branch":
			if page.depth != depth or depth >= 64: return Codec.fail("world_page_invalid")
			var child := _child(page,_nibble(digest,depth))
			if child == "": return {"ok":true,"props":[]}
			hash = child
			depth += 1
		else:
			if page.kind == "collision" and depth != 64: return Codec.fail("world_page_invalid")
			for record in page.records:
				if record.chunk == chunk: return {"ok":true,"props":record.props.duplicate(true)}
			if page.kind == "leaf" or page.next_hash == "": return {"ok":true,"props":[]}
			hash = page.next_hash
	return Codec.fail("world_page_invalid")
func prepare_patch(root: Dictionary, changes: Array) -> Dictionary:
	_write_sequence = HashingContext.new()
	_write_sequence.start(HashingContext.HASH_SHA256)
	_write_sequence.update(WRITE_SEQUENCE_DOMAIN.to_utf8_buffer())
	_page_write_calls = 0
	_collision_pages_scanned = 0
	_peak_collision_window_records = 0
	var valid := Codec.valid_root(root)
	if not valid.ok: return valid
	var normalized := Codec.normalize_records(changes)
	if not normalized.ok: return normalized
	var hash: String = root.root_hash
	var existing: Dictionary = _read.call(hash)
	if not existing.ok: return existing
	for record in normalized.records:
		var digest := _key_hash(record.chunk)
		if not Codec.valid_hash(digest): return Codec.fail("world_page_invalid")
		var updated := _patch(hash,record,digest,0)
		if not updated.ok: return updated
		hash = updated.hash
	var summary := {"page_write_calls":_page_write_calls,"sequence_digest":_write_sequence.finish().hex_encode()}
	_write_sequence = null
	return {"ok":true,"root":{"format_revision":1,"root_hash":hash},"write_summary":summary}
func _patch(hash: String, record: Dictionary, digest: String, depth: int) -> Dictionary:
	var loaded: Dictionary = _read.call(hash)
	if not loaded.ok: return loaded
	var page: Dictionary = loaded.page
	if page.kind == "branch":
		if page.depth != depth or depth >= 64: return Codec.fail("world_page_invalid")
		var nibble := _nibble(digest,depth)
		var previous := _child(page,nibble)
		var updated: Dictionary
		if previous == "": updated = _save({"format_revision":1,"kind":"leaf","records":[record]})
		else: updated = _patch(previous,record,digest,depth+1)
		if not updated.ok: return updated
		if updated.hash == previous: return {"ok":true,"hash":hash}
		var children: Array = page.children.duplicate(true)
		var found := false
		for child in children:
			if child.nibble == nibble:
				child.hash = updated.hash
				found = true
		if not found: children.append({"nibble":nibble,"hash":updated.hash})
		return _save({"format_revision":1,"kind":"branch","depth":depth,"children":children})
	if page.kind == "collision":
		if depth != 64: return Codec.fail("world_page_invalid")
		return _collision_patch(hash,record)
	var records: Array = page.records.duplicate(true)
	var found := false
	for i in records.size():
		if records[i].chunk == record.chunk:
			if records[i] == record: return {"ok":true,"hash":hash}
			records[i] = record
			found = true
	if not found: records.append(record)
	return _build(records,depth)
func _build(records: Array, depth: int) -> Dictionary:
	if records.size() <= 16: return _save({"format_revision":1,"kind":"leaf","records":records})
	if depth == 64:
		records.sort_custom(func(a,b): return Address.less(a.chunk,b.chunk))
		var next := ""
		var end := records.size()
		while end > 0:
			var start := maxi(0,end-16)
			var saved := _save({"format_revision":1,"kind":"collision","records":records.slice(start,end),"next_hash":next})
			if not saved.ok: return saved
			next = saved.hash
			end = start
		return {"ok":true,"hash":next}
	var groups := {}
	for record in records:
		var digest := _key_hash(record.chunk)
		if not Codec.valid_hash(digest): return Codec.fail("world_page_invalid")
		var nibble := _nibble(digest,depth)
		if not groups.has(nibble): groups[nibble] = []
		groups[nibble].append(record)
	var children := []
	for nibble in groups:
		var saved := _build(groups[nibble],depth+1)
		if not saved.ok: return saved
		children.append({"nibble":nibble,"hash":saved.hash})
	return _save({"format_revision":1,"kind":"branch","depth":depth,"children":children})
func _collision_patch(head: String, replacement: Dictionary) -> Dictionary:
	# Reverse windows trade CPU for bounded memory and constant continuation stack.
	# The write sequence is streamed into one digest, never retained as a list.
	var cursor: Variant = null
	var next := ""
	while true:
		var selected := []
		var hash := head
		while hash != "":
			var loaded: Dictionary = _read.call(hash)
			if not loaded.ok: return loaded
			var page: Dictionary = loaded.page
			if page.kind != "collision": return Codec.fail("world_page_invalid")
			_collision_pages_scanned += 1
			for record in page.records:
				if record.chunk != replacement.chunk: _select_window(selected,record,cursor)
			hash = page.next_hash
		_select_window(selected,replacement,cursor)
		if selected.is_empty(): break
		var saved := _save({"format_revision":1,"kind":"collision","records":selected,"next_hash":next})
		if not saved.ok: return saved
		next = saved.hash
		cursor = selected[0].chunk
	return {"ok":true,"hash":next}
func _select_window(selected: Array, record: Dictionary, cursor: Variant) -> void:
	if cursor != null and not Address.less(record.chunk,cursor): return
	selected.append(record)
	_peak_collision_window_records = maxi(_peak_collision_window_records,selected.size())
	selected.sort_custom(func(a,b): return Address.less(a.chunk,b.chunk))
	if selected.size() > 16: selected.pop_front()
func _key_hash(chunk: Array) -> String:
	var key := Address.key(chunk)
	return str(_hasher.call(key)) if _hasher.is_valid() else Codec.digest(key.to_utf8_buffer())
func _nibble(digest: String, depth: int) -> int:
	return "0123456789abcdef".find(digest[depth])
func _child(page: Dictionary, nibble: int) -> String:
	for child in page.children:
		if child.nibble == nibble: return child.hash
	return ""
func _save(page: Dictionary) -> Dictionary:
	var saved: Dictionary = _write.call(page)
	if saved.ok:
		if not Codec.valid_hash(saved.get("hash")): return Codec.fail("world_page_invalid")
		# One fixed-width lowercase ASCII hash and LF per successful callback.
		# Includes successful reuse; this is not a unique-page/physical-byte count.
		_page_write_calls += 1
		_write_sequence.update((saved.hash+"\n").to_utf8_buffer())
	return saved
func diagnostics() -> Dictionary:
	return {"retained_write_hashes":0,"write_digest_bytes":32,"page_write_calls":_page_write_calls,"collision_pages_scanned":_collision_pages_scanned,"peak_collision_window_records":_peak_collision_window_records}
