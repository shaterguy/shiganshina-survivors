extends RefCounted
# Historical fixture bytes remain verifiable independently from current content.
func run(t) -> void:
 var hashes:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/a4_prior_fixture_hashes.json"))
 for path in hashes:t.check(FileAccess.get_sha256("res://"+path)==hashes[path],"Source21 historical fixture unchanged: "+path)
 var old:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/c4/finite_chapter_definition.json"))
 var a4:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/c4/finite_chapter_definition_a4.json"))
 t.check(a4.content_revision=="ch01.3-rebuild.5-preparation97","historical Source22 .5 catalog stays preserved")
 var current:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/c4/finite_chapter_definition_recovery.json"))
 t.check(old.content_revision=="ch01.3-rebuild.2" and current.content_revision=="ch01.3-rebuild.6-harmless-recovery","old/new physical content identities are explicitly distinct")
 for key in old:
  if key in ["content_revision","content_fingerprint","content_definition_hashes","enemy_catalog"]:continue
  t.check(old[key]==current[key],"finite fixture retains unrelated authored field: "+key)
 for id in old.enemy_catalog:
  if id!="armored_titan":t.check(old.enemy_catalog[id]==current.enemy_catalog[id],"A4 fixture keeps non-final enemy definition: "+id)
 var actual:Dictionary=load("res://game/director/chapter_catalog.gd").new().load_chapter("chapter_01_shiganshina").chapter
 var grabber:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/c4/finite_chapter_definition_grabber.json"))
 for id in grabber.enemy_catalog:
  t.check(actual.enemy_catalog.get(id)==grabber.enemy_catalog[id],"current content preserves exact historical enemy definition: "+id)
 for id in grabber.enemy_role_catalog.roles:
  t.check(actual.enemy_role_catalog.roles.get(id)==grabber.enemy_role_catalog.roles[id],"current content preserves exact historical role profile: "+id)
 t.check(actual.enemy_catalog.has("quadruped") and actual.enemy_catalog.has("stone_thrower") and actual.content_fingerprint != grabber.content_fingerprint,"new roles have a distinct current content identity; historical fixture is not current")
 for id in current.enemy_catalog:
  if id != "grabber": t.check(current.enemy_catalog[id] == grabber.enemy_catalog[id],"grabber revision keeps every unrelated enemy definition: "+id)
 t.check(grabber.enemy_catalog.grabber.speed == 50 and current.enemy_catalog.grabber.speed == 30,"grabber speed change is explicit and old definition preserved")
 var prior:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/grabber_prior_recovery_hashes.json"))
 for path in prior:t.check(FileAccess.get_sha256("res://"+path)==prior[path],"Source23 .6 fixture remains byte-identical: "+path)
 var provider=load("res://tests/core/finite_chapter_provider.gd").new()
 var chapter:Dictionary=provider.load_chapter("chapter_01_shiganshina").chapter
 var core=load("res://game/core/run_simulation.gd").new(provider)
 var config:Dictionary=load("res://tests/core/core_fixture.gd").run_config()
 var state:Dictionary=core.new_run(chapter,42,config)
 t.check(not state.has("error_code") and core.restore(state).get("ok",false),"historical finite_test provider constructs and restores its own bound content with current Core")
