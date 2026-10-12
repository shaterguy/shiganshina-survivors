extends RefCounted
func run(t) -> void:
 var script = load("res://tools/build/production_export_filter.gd")
 var paths = script.get_script_constant_map().get("UI_FONT_FILES",[])
 t.check(paths == ["res://assets/fonts/NotoSansKR-wght.ttf","res://assets/fonts/NotoSansKR-OFL.txt"],"export pins exactly the bundled font and its OFL, not an entire directory")
 t.check(FileAccess.get_sha256("res://assets/fonts/NotoSansKR-wght.ttf")=="194018e6b2b293a7964f037b25c0249ce1418bc9ab3c971060a03aa57861e252","font bytes are the unmodified official source")
 t.check(FileAccess.get_sha256("res://assets/fonts/NotoSansKR-OFL.txt")=="1c05c68c34f9708415aada51f17e1b0092d2cea709bf4a94cd38114f9e73d7d9","bundled OFL preserves official copyright and license")
 var manifest = JSON.parse_string(FileAccess.get_file_as_string("res://assets/manifest.json"))
 t.check(manifest.art_revision_status.final_export_allowed==false,"font addition leaves the final art gate closed")
 var blocked: Array = []
 for id in manifest.assets:
  if manifest.assets[id].get("export_blocked",false): blocked.append(id)
 blocked.sort()
 t.check(blocked==["boss_abnormal","boss_charger","boss_leaper","titan_runner","titan_sweeper"],"five rejected character IDs stay blocked")
