# Kayoko attribution

The anchored menu and clipboard prompt appearance/interaction are adapted from
[moxuan1121/Kayoko-](https://github.com/moxuan1121/Kayoko-), branch
`restore-native-word-selection`, commit `d610468f746d5e49c1e3a92b479e5c094f378c66`.
Original project credits: mlgm / Kayoko contributors. Modifications: moxuan1121.
The copied and derived code is distributed under GNU GPL v3 (see COPYING).
Keyboard AI source is distributed under GPL-3.0 to accompany the combined package.

Adaptation keeps the native anchored menu, spring button feedback, gradient and
size/position/duration settings. Clipboard history, databases, image collection,
and Kayoko runtime hooks are not included. Search and prompt preferences are
stored in Keyboard AI's shared plist. No Kayoko installation is required.

Input modules adapted from KeyboardAI-RootHide commit 23c761ee8ea2d4597ae1b22fee48cc7837b1708b. Symbols namespaced RSInput.

Sileo integration observes public UIView properties. Native Markdown text lookup verified against https://github.com/Sileo/Sileo/blob/main/Sileo/Contrib/CSTextRenderView.swift (accessibilityLabel); no Sileo source is copied.
