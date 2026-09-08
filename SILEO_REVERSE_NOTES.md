# ShellX 3.0.1 Sileo 长按翻译分析

分析输入为用户提供的 arm64e 包中的 ScreenshotShell.dylib，使用 ipsw 静态反汇编；未运行或复制其二进制代码。以下地址是该包内的虚拟地址，不用于 RegionShot 的运行时挂接。

- `SSSileoLongPress handle:` (`0x1464dc`)：仅处理长按开始；读取触点并使用 `hitTest:withEvent:`，从命中视图查找控制器与介绍容器。
- `0x146cbc`：触摸过滤，排除按钮，识别 CSText / DepictionTabView，并检查所选介绍标签页。
- `0x147568`：从命中视图及介绍容器提取原生文字；`0x1477f4` / `0x147838` 分别读取 attributedText 与 text；收集结果去重、组合。
- 网页路径查找 Web 容器，使用 JavaScript 读取选中文字，没有选区则读取 document.body.innerText / textContent。
- `0x149498`–`0x1494a8`：允许同时识别，不要求自身或其他识别器先失败。
- `0x149554` 初始化：检查 bundleIdentifier 和 processName 中的 sileo，明确包含 org.coolstar.SileoStore；挂接 viewDidAppear、viewDidLayoutSubviews、didMoveToWindow。

RegionShot 独立实现：每个窗口仅一个长按识别器，触摸按介绍视图过滤；额外做几何命中，覆盖 userInteractionEnabled=NO 的 UILabel/CSText 子视图；提取原生 attributedText/text/accessibilityLabel 或网页选区/正文，提交至已整合的 KeyboardAI 文字回答窗口。保留独立开关与翻译人设设置。不会重新分发 ShellX。

静态分析不能确认具体 Sileo 版本的实际视图树及与其他插件的手势竞争，安装后需在原生 Markdown 和 Web 介绍页分别验证。
