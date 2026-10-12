extends RefCounted
func run(t) -> void:
 var gate = load("res://tools/build/export_readiness.gd").new()
 t.check(gate.has_method("is_runtime_asset_path"),"one shared approved runtime path predicate")
 if not gate.has_method("is_runtime_asset_path"): return
 var record := {"kind":"effect","vfx_approved":true,"path":"res://assets/art/effects/vfx_rebuild_v1/vfx_blade_crescent-v3.png"}
 t.check(gate.is_runtime_asset_path(record),"reviewed nested VFX raw raster retained")
 for path in ["res://assets/art/effects/vfx_rebuild_v1/source/source.png","res://assets/art/effects/vfx_rebuild_v1/../private.png","res://assets/art/effects/other/draft.png","res://assets/art/effects/vfx_rebuild_v1/source.png"]:
  var altered := record.duplicate(true); altered.path = path
  t.check(not gate.is_runtime_asset_path(altered),"nonruntime nested source excluded: "+path)
 for approval in [false,"true",1]:
  var altered := record.duplicate(true); altered.vfx_approved = approval
  t.check(not gate.is_runtime_asset_path(altered),"unreviewed nested VFX excluded")
 t.check(gate.is_runtime_asset_path({"path":"res://assets/art/characters/garrison_01_v2.png"}),"existing flat raster retained")
 t.check(gate.is_runtime_asset_path({"path":"res://assets/audio/hit.wav"}),"existing WAV retained")
