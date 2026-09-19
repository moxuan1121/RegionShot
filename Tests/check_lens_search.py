from pathlib import Path

root = Path(__file__).resolve().parents[1]
menu = (root / "Selection/RSMenuSettings.m").read_text(encoding="utf-8")
toolbar = (root / "Selection/RSSelectionToolbar.m").read_text(encoding="utf-8")
window = (root / "Selection/RSSelectionWindow.m").read_text(encoding="utf-8")

assert '@"id":@13' in menu and '@"title":@"识图"' in menu
assert "button.tag == 13" in toolbar and "imageSearchHandler" in toolbar
assert "https://searchenginereports.net/reverse-image-search" in window
assert "processImg(f,true)" in window
assert "WKWebsiteDataStore.nonPersistentDataStore" in window
assert "ris-result" in window
assert 'components.scheme = @"reynard"' in window
assert "google.com/search?" in window and "vsrid=" in window
assert "NSURLSession" not in window
assert "search.app.goo.gl" not in window
print("Google Lens search uses the verified aggregator session and hands its result to Reynard")
