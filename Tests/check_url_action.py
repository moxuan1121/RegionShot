from pathlib import Path

for source in ("Input/RSInputInterface.m", "KeyboardAI/RSKAInterface.m"):
    text = Path(source).read_text(encoding="utf-8")
    assert 'button:@"访问" action:@selector(visitResult)' in text
    assert "RSContainedWebURL(self.result)" in text or "RSContainedWebURL(panel.result)" in text
    assert "openURL:url options:@{}" in text

print("URL action is wired into both input panel implementations")
