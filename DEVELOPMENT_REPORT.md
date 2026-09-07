# RegionShot 开发报告

## 0.3.2：设置入口与组合键均失败的后续修复

- 已定位共享捕获路径的符号拼写错误。用户提供的 ShellX 3.0.1 二进制导入 `__UICreateScreenUIImage`，实际 C/dlsym 名称为 `_UICreateScreenUIImage`；此前缺少下划线导致找不到此入口、返回 nil，再退回系统截图。
- 修正共用解析函数，区域截图和长截图均受益。新增可运行检查，在 macOS 导出相同名称的模拟函数，验证正确名称优先、旧名称兼容回退。
- 设置页新增即时诊断：以本次随机请求 ID 核对 SpringBoard 响应，显示开关、符号和挂接入口状态。测试失败不再静默，超时不冒充成功。
- 不把符号修复或构建通过等同于实机修复完成；需要设备确认窗口实际显示及组合键行为。完整功能范围与下述待办保持一致。


## 0.3.1 用户反馈修复

用户实机反馈组合键无效、系统设置无面板。旧版仅拦截 `SpringBoard takeScreenshot`，而且包内没有 PreferenceLoader 注册或设置 bundle。
新版加入组合键动作 `performTakeScreenshotAction`、`takeScreenshotAndEdit:` 和 ScreenshotServices
`takeScreenshotWithPresentationOptions:`，运行时验证 void 返回值及参数签名，所有入口共用捕获与原生回退。
新增独立现代 arm64e 设置组件，提供启用开关、现有工具条定制及 Darwin 通知测试截图入口。
`Tests/check_package.py` 会检查设置注册、实际 bundle 二进制、控制器、版本和签名；旧 0.3.0 包不能通过该检查。
以上是代码及包结构修复，仍需用户设备验证组合键和设置界面。完整 ShellX 功能迁移范围不因本次修复缩减。

## 0.3.0 开发预览进展（2026-09-07）

目标已扩展为 ShellX 3.0.1 的区域截图相关完整功能，明确包括全部详细设置、自定义图标和长截图，排除套壳截图。
当前仍是功能子集，尚未完成完整复刻，也没有 iOS 15.6 RootHide 实机测试结果。

| 范围 | 本轮实现 | 未完成/验证限制 |
| --- | --- | --- |
| AI 对话 | 独立窗口、自定义 HTTPS 服务/模型、钥匙串密钥、图文多轮、SSE、停止、复制、旧回复重生成、最小化/恢复 | 多引擎/人格/主题/详细设置、完整附件相机生命周期、设备网络与键盘测试 |
| 分词 | 刷新旁 `character.textbox`，通过 KeyboardAI 1.4.6 进程内桥接，接受后最小化 | 需要同时安装新版 KeyboardAI；未实机测试 |
| 长截图 | 手动逐段/定时采样、磁盘分段、重叠匹配、完成生成浮图、取消清理 | 自动短滑/持续上滑、固定栏检测、完整三种模式；24 MP/100 段上限 |
| 图标和工具条 | 区域工具条排序、开关、改名、图片/SF Symbol 名称、文字显示、大小、恢复默认 | 其他四类菜单、背景、分割线、可视化 SF Symbols 浏览及全部详细设置 |
| 识别 | 系统 Vision OCR/条码，CoreImage 二维码兜底，结果选择/复制 | 外部 OCR API、识别参数配置、区域/全屏翻译 |
| 标记 | PencilKit 画笔/橡皮/套索/尺子、颜色、撤销/重做、原分辨率合成 | ShellX 独立形状/文字、贴纸、马赛克、叠图、完整编辑状态 |
| 历史/触发 | 保留基础截图和浮图管理 | 截图历史搜索/限额、控制中心/状态栏/音量键、自定义指令和完整插件接口 |

测试覆盖：裁剪几何、SSE 的所有分包边界/UTF-8/BOM/异常截断、合成画面的纵向重叠/重复/反向/噪声/无匹配，
以及生成真实二维码后调用系统识别与兜底路径。macOS 构建验证不能替代 SpringBoard 真机 UI 验证。

本轮发现云端 Vision 旧检测版本对有效二维码返回空观察值，CoreImage 可以识别同图；应用与检查共享二维码兜底函数。
完整分析材料另存于交付目录 `ShellX-3.0.1-analysis`，包含全主库 text 反汇编、方法索引、设置接口和核心路径注释。

以下保留 **0.2.0 的历史报告**，其中固定 72 点工具条、功能排除范围与旧构建信息不代表 0.3.0 的状态。

## 已完成

- 建立 RootHide Theos、arm64e、iOS 15.0 deployment target、SpringBoard 单进程注入工程。
- 实现统一 Manager、截图状态、内部捕获保护、失败清理和重复触发保护。
- 实现冻结图、轻度压暗、矩形框选、四角调整、选区移动和底部工具条。
- 实现从 frozenImage 的 Retina 像素裁剪。
- 实现多悬浮图、层级管理、透明区域触摸穿透、拖动、缩放、左右吸边和双击关闭。
- 实现 iOS 15 系统长按菜单、复制、Photos 保存、系统分享、隐藏和关闭操作。
- 选择窗口与悬浮窗口优先绑定触发截图时所在的 `UIWindowScene`，无 scene 时才使用屏幕 frame 回退。

## ShellX 逆向结论

对用户提供的 ShellX 2.9.0 arm64e 包进行静态分析后，确认其区域截图链路同样使用
`_UICreateScreenUIImage` 获取冻结图，并持有原始图、捕获 bounds 和界面方向；确认选区后通过
`CGImageCreateWithImageInRect` 从原图裁剪。它创建区域选择窗口时优先使用 `initWithWindowScene:`。
RegionShot 据此保留现有捕获和原图裁剪方案，并补齐 scene 绑定。详细证据和排除范围记录在
`REVERSE_ENGINEERING.md`。

## 系统截图入口

Hook 为 `SpringBoard` 类的实例方法 `-takeScreenshot`。初始化时通过 `NSClassFromString`、`class_getInstanceMethod`、参数数量和 void 返回值检查该方法，只有匹配时才启用 Hook。

用户提供的 statusbar-shot 证据确认：其他 tweak 可以向当前 SpringBoard `UIApplication` 对象发送 `takeScreenshot`，并进入这个接口。该仓库没有证明原生侧边键 + 音量加在 iOS 15.6 上必定经过同一方法，所以实体组合键仍需通过 `[RegionShot] screenshot trigger` 日志实机确认。

## 屏幕捕获

`RSScreenCapture` 用 `dlsym(RTLD_DEFAULT, "_UICreateScreenUIImage")` 运行时解析系统函数，不静态链接未知私有符号。调用发生在 Selection Window 创建之前，并保存唯一的原始 `frozenImage`。若符号不存在或结果没有 CGImage，Manager 清理状态，Hook 回退到原生截图。

## Selection UI

`RSSelectionWindow` 的层级是 frozenImage 的全屏 UIImageView、透明 `RSSelectionView` 和最上层 `RSSelectionToolbar`。Selection View 用偶奇填充绘制选区外遮罩，使选区内保留原图亮度；触摸状态区分新选区、四角缩放和整体移动。Toolbar 是固定在安全区上方的 72pt 胶囊容器，覆盖在 Selection View 上，因此工具条触摸不会进入框选逻辑。

## Floating

所有截图由一个 SpringBoard `RSFloatingWindow` 承载。`hitTest:withEvent:` 在命中透明根视图时返回 nil，只让悬浮图片接收触摸。Manager 的数组保留各 `RSFloatingImageView`；点击时同时更新视图层级和数组顺序。每张图保持自己的 UIImage、frame、transform 和手势状态，不在拖动或缩放时重新生成图片。

## 编译结果

GitHub Actions 的 macOS 14 工作流已在提交 `4fa8607489b3a61d13334b885967e1dd68cc2080` 成功运行。
几何检查、RootHide Theos 安装、Objective-C/Logos 编译、链接、package 和 artifact 上传均通过。

生成文件为 `com.moxuan.regionshot_0.2.0-roothide_iphoneos-arm64e.deb`，SHA-256 为
`669D11E865F0E7C32E5934D98B0061CD3B086558587DD86ECA71FAD843BC31A1`。独立解包确认 control 的
Architecture 为 `iphoneos-arm64e`、Version 为 `0.2.0-roothide`；payload 只有
`RegionShot.dylib` 与 `RegionShot.plist`。dylib 是 thin ARM64 Mach-O，CPU subtype 为现代 arm64e
`0x80000002`。

## 仍需实机验证

- 原生侧边键 + 音量加是否进入 `SpringBoard -takeScreenshot`
- `_UICreateScreenUIImage` 在 iOS 15.6 RootHide SpringBoard 中的解析和画面内容
- Safari、视频界面和系统 UI 的冻结结果
- iPhone 13 Pro Max 3× 的最终裁剪坐标
- 工具条位置、Home Indicator 间距和横屏表现
- 透明窗口触摸穿透、多浮窗重叠、App 切换后的保留
- Photos 权限提示、保存结果和系统分享 presentation context
- 连续截图的内存释放、SpringBoard crash 与 watchdog 稳定性

## 风险

- `SpringBoard -takeScreenshot` 和 `_UICreateScreenUIImage` 都是私有接口。代码只在运行时存在且签名符合预期时使用，但不同系统状态仍可能失败。
- statusbar-shot 只验证主动发送 `takeScreenshot` 的调用；实体截图组合键覆盖范围仍未知。
- 隐藏悬浮窗口后立即捕获依赖 iOS 合成时序，实机需确认旧悬浮图不会进入 frozenImage，也不会产生可见闪烁。
- 从非 key 的悬浮 UIWindow 根控制器弹出 UIActivityViewController 需要在目标环境实测。
- 竖屏是当前优先路径；旋转中的 selectionRect 重映射未增加额外兼容层。
