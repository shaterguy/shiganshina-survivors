extends RefCounted
func run(t) -> void:
 var path := "res://game/presentation/armored/armored_draw_split.gd"
 t.check(ResourceLoader.exists(path),"actor-only premultiplied compositor exists")
 if not ResourceLoader.exists(path): return
 var world := Node2D.new(); t.root.add_child(world)
 var split = load(path).new(); world.add_child(split)
 var image := Image.create(2,2,false,Image.FORMAT_RGBA8); image.fill(Color(.25,.125,0,.5))
 var texture := ImageTexture.create_from_image(image)
 var actor = split.get_node("ArmoredPremultiplied")
 var tail = split.get_node("OrdinaryForeground")
 t.check(actor.material is CanvasItemMaterial and actor.material.blend_mode==CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA,"only actor uses premultiplied output compositing")
 t.check(world.material==null and tail.material==null and not tail.use_parent_material,"parent and later ordinary atlas preserve MIX semantics")
 t.check(actor.get_index()<tail.get_index() and actor.z_index==0 and tail.z_index==0 and not actor.show_behind_parent and not tail.show_behind_parent,"actor and tail inherit ordered same-depth child submission")
 var ids := [actor.get_instance_id(),tail.get_instance_id(),actor.material.get_instance_id()]
 world.position=Vector2(25,50); world.rotation=.2; world.scale=Vector2(1.25,.75)
 world.modulate=Color(.7,.6,.5,.4)
 t.check(actor.global_transform.is_equal_approx(world.global_transform) and tail.global_transform.is_equal_approx(world.global_transform),"split inherits actual parent translation rotation and scale")
 t.check(split is CanvasItem and actor.get_parent()==split and tail.get_parent()==split and split.get_parent()==world,"modulate has an uninterrupted CanvasItem parent chain")
 actor.visible=true; tail.visible=true; world.visible=false
 t.check(not actor.is_visible_in_tree() and not tail.is_visible_in_tree(),"hidden WorldView cannot leak actor or foreground commands")
 world.visible=true
 for n in 10:
  split.begin_frame()
  t.check(not split.routing_tail() and not actor.visible and not tail.visible,"new frame clears old actor and later commands")
  var transform := Transform2D(0,Vector2(123.5,88.25)).scaled_local(Vector2(-1.5,1.5))
  t.check(split.insert_actor(texture,transform,Rect2(-144,-280,288,288)),"one premult actor insertion accepts exact mirror/scale/anchor")
  t.check(not split.insert_actor(texture,Transform2D.IDENTITY,Rect2(0,0,2,2)),"second actor cannot produce duplicate or reorder")
  split.append_transform(Transform2D(0,Vector2(15,18)))
  split.append_region(texture,Rect2(2,3,4,5),Rect2(0,0,2,2),Color(1,1,1,.7))
  split.append_rect(texture,Rect2(5,6,7,8),false,Color(.4,.8,.2,.6))
  var stats: Dictionary = split.debug_stats()
  t.check(split.routing_tail() and actor.visible and tail.visible and stats.actor_commands==1 and stats.tail_commands==3,"all subsequent transforms and raster commands route above actor")
  t.check([actor.get_instance_id(),tail.get_instance_id(),actor.material.get_instance_id()]==ids,"repeated frame does not allocate new nodes or materials")
 for n in 3:
  split.begin_frame()
  split.insert_actor(texture,Transform2D.IDENTITY,Rect2(0,0,2,2))
  split.append_transform(Transform2D(0,Vector2(4,0)))
  split.append_rect(texture,Rect2(0,0,2,2),false)
  await t.process_frame
  await t.process_frame
  var replay:Dictionary=split.debug_stats()
  t.check(replay.get("actor_redraws",0)>n and replay.get("actor_replayed_commands",0)==2,"actual child redraw restores transform and actor texture after engine clears RID")
  t.check(replay.get("tail_redraws",0)>n and replay.get("tail_replayed_commands",0)==2,"actual child redraw restores every ordinary foreground command")
 split.begin_frame()
 t.check(not split.insert_actor(null,Transform2D.IDENTITY,Rect2(0,0,2,2)) and not split.routing_tail(),"absent texture keeps original draw route")
 await t.process_frame
 t.check(split.debug_stats().get("retained_commands",-1)==0,"absent actor clears retained buffers as well as visible RID commands")
 world.free()
 await t.process_frame
