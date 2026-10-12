"""NEW title identity regression; does not validate gameplay or APK readiness."""
import json,re,unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
class TitleIdentityTests(unittest.TestCase):
 def test_app_title_covers_the_series(self):
  text=(ROOT/'project.godot').read_text()
  self.assertIn('config/name="진격의 거인: 인류의 날개"',text)
 def test_chapter_title_is_separate(self):
  chapter=json.loads((ROOT/'chapters/chapter_01/manifest.json').read_text())
  self.assertEqual(chapter.get('display_name'),'시간시나구 탈출')
  self.assertEqual(chapter['chapter_id'],'chapter_01_shiganshina')
  self.assertEqual(chapter['story_year'],845)
 def test_readme_starts_with_product_title(self):
  self.assertEqual((ROOT/'README.md').read_text().splitlines()[0],'# 진격의 거인: 인류의 날개')
 def test_android_display_name_uses_product_title(self):
  text=(ROOT/'addons/chapter_export/plugin.gd').read_text()
  self.assertIn('preset.set("package/name","진격의 거인: 인류의 날개 개발검증판" if export_mode == "development-validation" else "진격의 거인: 인류의 날개")',text)
 def test_android_identity_is_not_renamed(self):
  config=json.loads((ROOT/'tools/build/toolchain.json').read_text())
  self.assertEqual(config['android']['package'],'com.shaterguy.shiganshina.dev')
if __name__=='__main__':unittest.main()
