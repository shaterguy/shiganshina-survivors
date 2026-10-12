extends Node2D
## One actor needs premultiplied blending. Preserve the parent's ordinary MIX
## draws before it; redirect only later commands into the last ordinary child.
## Commands are submitted synchronously and retained for CanvasItem redraws.
## Godot clears RID commands before _draw, including after visibility changes.
## Headless can verify ownership/order/replay, never GPU pixels.
class DrawSurface:
 extends Node2D
 var commands: Array = []
 var redraws := 0
 var replayed_commands := 0
 func clear_commands() -> void:
  commands.clear()
  RenderingServer.canvas_item_clear(get_canvas_item())
 func submit(command: Array) -> void:
  commands.append(command)
  _apply(command)
 func _draw() -> void:
  # The engine's own clear is conditional. Always replace, never append a
  # second copy on the first visible callback after direct RID submission.
  RenderingServer.canvas_item_clear(get_canvas_item())
  redraws+=1
  replayed_commands=commands.size()
  for command in commands: _apply(command)
 func _apply(command: Array) -> void:
  var rid := get_canvas_item()
  match command[0]:
   "transform": RenderingServer.canvas_item_add_set_transform(rid,command[1])
   "rect": RenderingServer.canvas_item_add_texture_rect(rid,command[1],command[2].get_rid(),command[3],command[4])
   "region": RenderingServer.canvas_item_add_texture_rect_region(rid,command[1],command[2].get_rid(),command[3],command[4],false,true)
var _actor: DrawSurface
var _tail: DrawSurface
var _inserted := false
var _tail_commands := 0
func _ready() -> void:
 _actor=DrawSurface.new(); _actor.name="ArmoredPremultiplied"
 var material := CanvasItemMaterial.new()
 material.blend_mode=CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
 _actor.material=material
 _tail=DrawSurface.new(); _tail.name="OrdinaryForeground"
 for item in [_actor,_tail]:
  item.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
  item.texture_repeat=CanvasItem.TEXTURE_REPEAT_DISABLED
  item.use_parent_material=false
  add_child(item)
 begin_frame()
func begin_frame() -> void:
 _inserted=false; _tail_commands=0
 for item in [_actor,_tail]:
  if is_instance_valid(item):
   item.clear_commands()
   item.visible=false
func routing_tail() -> bool: return _inserted
func insert_actor(texture: Texture2D, transform: Transform2D, rect: Rect2, color:=Color.WHITE) -> bool:
 if _inserted or texture==null or not is_instance_valid(_actor) or not transform.is_finite() or not rect.position.is_finite() or not rect.size.is_finite() or not rect.has_area(): return false
 _actor.submit(["transform",transform])
 _actor.submit(["rect",rect,texture,false,color])
 _actor.visible=true; _tail.visible=true; _inserted=true
 return true
func append_transform(transform: Transform2D) -> void:
 if not _inserted: return
 _tail.submit(["transform",transform])
 _tail_commands+=1
func append_region(texture: Texture2D, rect: Rect2, region: Rect2, color:=Color.WHITE) -> void:
 if not _inserted or texture==null: return
 _tail.submit(["region",rect,texture,region,color])
 _tail_commands+=1
func append_rect(texture: Texture2D, rect: Rect2, tiled: bool, color:=Color.WHITE) -> void:
 if not _inserted or texture==null: return
 _tail.submit(["rect",rect,texture,tiled,color])
 _tail_commands+=1
func debug_stats() -> Dictionary:
 return {"actor_commands":1 if _inserted else 0,"tail_commands":_tail_commands,"native_gpu_verified":false,
  "actor_redraws":_actor.redraws,"tail_redraws":_tail.redraws,
  "actor_replayed_commands":_actor.replayed_commands,"tail_replayed_commands":_tail.replayed_commands,
  "retained_commands":_actor.commands.size()+_tail.commands.size()}
