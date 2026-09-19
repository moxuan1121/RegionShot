from pathlib import Path

root = Path(__file__).resolve().parents[1]
menu = (root / "Selection/RSMenuSettings.m").read_text(encoding="utf-8")
toolbar = (root / "Selection/RSSelectionToolbar.m").read_text(encoding="utf-8")
window = (root / "Selection/RSSelectionWindow.m").read_text(encoding="utf-8")

assert '@"id":@13' in menu and '@"title":@"识图"' in menu
assert "button.tag == 13" in toolbar and "imageSearchHandler" in toolbar
assert "https://lens.google.com/v3/upload" in window
assert 'components.scheme = @"reynard"' in window
assert 'name=\\"processed_image_dimensions\\"' in window
assert "Chrome/136.0.0.0" in window
assert "gsessionid=" in window and "lsessionid=" in window
assert "NSURLSession" in window
assert "search.app.goo.gl" not in window
print("Google Lens redirect keeps dimensions and both result session IDs")
