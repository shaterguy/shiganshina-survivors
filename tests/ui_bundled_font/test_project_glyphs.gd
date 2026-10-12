extends RefCounted
func _collect(path: String, points: Dictionary) -> void:
 var dir := DirAccess.open(path)
 if dir == null: return
 for filename in dir.get_files():
  if not filename.get_extension() in ["gd","json","tscn"]: continue
  var source := FileAccess.get_file_as_string(path.path_join(filename))
  for i in range(source.length()):
   var cp := source.unicode_at(i)
   if cp > 32: points[cp] = true
 for folder in dir.get_directories(): _collect(path.path_join(folder),points)
func run(t) -> void:
 var theme: Theme = load("res://game/ui/korean_ui_theme.tres")
 var font: Font = theme.default_font
 var ts := TextServerManager.get_primary_interface()
 var rids: Array[RID] = font.get_rids()
 var points := {}
 for path in ["res://game","res://data","res://chapters","res://scenes"]: _collect(path,points)
 t.check(points.size()>400,"coverage includes actual game/data/chapter/scene text, not only one sample")
 for cp in points:
  t.check(ts.font_has_char(rids[0],cp),"bundled RID directly contains source codepoint U+%04X"%cp)
 var samples := ["진격의 거인 인류의 날개", "시간시나구 탈출", "피해량 12.5 → 18.75", "기동 교리 · 보급금 40", "진화 선행조건\n쌍검 5/5 · 충족", "A · 선택   B · 뒤로   Ⅱ", "← ↑ → ↓ ↔ ± 0123456789"]
 for size in [11,12,13,15,16,20,24,28]:
  for text in samples:
   var line := TextLine.new()
   line.add_string(text,font,size)
   var glyphs := ts.shaped_text_get_glyphs(line.get_rid())
   t.check(not glyphs.is_empty(),"actual glyphs shaped at size "+str(size))
   for glyph in glyphs:
    # Newline/control glyphs have a legitimate zero glyph index and no ink.
    if text.unicode_at(int(glyph.start))<=32: continue
    t.check(glyph.font_rid==rids[0] and int(glyph.index)>0,"Korean/arrow/number glyph uses bundled font without system fallback")
