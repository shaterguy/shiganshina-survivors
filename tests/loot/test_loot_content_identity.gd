extends RefCounted
# Exact bytes from the approved dev13 tree. No serialized JSON equivalence.
func run(t) -> void:
	var expected = JSON.parse_string(FileAccess.get_file_as_string("res://tests/loot/content_identity.json"))
	t.check(expected is Dictionary and expected.size() == 13,"LOOT all thirteen immutable content inputs are pinned")
	if not expected is Dictionary: return
	for path in expected:
		var bytes := FileAccess.get_file_as_bytes("res://"+path)
		var digest := HashingContext.new()
		digest.start(HashingContext.HASH_SHA1)
		digest.update(("blob "+str(bytes.size())).to_utf8_buffer())
		digest.update(PackedByteArray([0]))
		digest.update(bytes)
		t.check(digest.finish().hex_encode() == expected[path],"LOOT immutable original bytes: "+path)
