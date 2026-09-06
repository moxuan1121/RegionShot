# RegionShot 开发报告

## 已完成

- 建立 RootHide Theos、arm64e、iOS 15.0 deployment target、SpringBoard 单进程注入工程。
- 实现统一 Manager、截图状态、内部捕获保护、失败清理和重复触发保护。
- 实现冻结图、轻度压暗、矩形框选、四角调整、选区移动和底部工具条。
- 实现从 frozenImage 的 Retina 像素裁剪。
- 实现多悬浮图、层级管理、透明区域触摸穿透、拖动、缩放、左右吸边和双击关闭。
- 实现 iOS 15 系统长按菜单、复制、Photos 保存、系统分享、隐藏和关闭操作。

## 系统截图入口

Hook 为 `SpringBoard` 类的实例方法 `-takeScreenshot`。初始化时通过 `NSClassFromString`、`class_getInstanceMethod`、参数数量和 void 返回值检查该方法，只有匹配时才启用 Hook。

用户提供的 statusbar-shot 证据确认：其他 tweak 可以向当前 SpringBoard `UIApplication` 对象发送 `takeScreenshot`，并进入这个接口。该仓库没有证明原生侧边键 + 音量加在 iOS 15.6 上必定经过同一方法，所以实体组合键仍需通过 `[RegionShot] screenshot trigger` 日志实机确认。

## 屏幕捕获

`RSScreenCapture` 用 `dlsym(RTLD_DEFAULT, "UICreateScreenUIImage")` 运行时解析系统函数，不静态链接未知私有符号。调用发生在 Selection Window 创建之前，并保存唯一的原始 `frozenImage`。若符号不存在或结果没有 CGImage，Manager 清理状态，Hook 回退到原生截图。

## Selection UI

`RSSelectionWindow` 的层级是 frozenImage 的全屏 UIImageView、透明 `RSSelectionView` 和最上层 `RSSelectionToolbar`。Selection View 用偶奇填充绘制选区外遮罩，使选区内保留原图亮度；触摸状态区分新选区、四角缩放和整体移动。Toolbar 是固定在安全区上方的 72pt 胶囊容器，覆盖在 Selection View 上，因此工具条触摸不会进入框选逻辑。

## Floating

所有截图由一个 SpringBoard `RSFloatingWindow` 承载。`hitTest:withEvent:` 在命中透明根视图时返回 nil，只让悬浮图片接收触摸。Manager 的数组保留各 `RSFloatingImageView`；点击时同时更新视图层级和数组顺序。每张图保持自己的 UIImage、frame、transform 和手势状态，不在拖动或缩放时重新生成图片。

## 编译结果

GitHub Actions 的 macOS 14 工作流已在提交 `456b936c327f88c68aa893cd9fa102fa9572b169` 成功运行。几何检查、RootHide Theos 安装、全部 Objective-C/Logos 源码编译、链接和 package 阶段均通过；工作流确认 dylib 的 Mach-O CPU subtype 为现代 arm64e `0x80000002`，并确认暂存包包含 `RegionShot.dylib` 和 `RegionShot.plist`。

生成文件为 `com.moxuan.regionshot_0.1.0-roothide_iphoneos-arm64e.deb`，SHA-256 为 `90B92001F5C2F828342138C09CCDA68B59FAE03C75E15AF529FDB8D9B851B083`。解包后的 control 显示 Architecture 为 `iphoneos-arm64e`、Version 为 `0.1.0-roothide`；payload 只有 MobileSubstrate 动态库目录中的 RegionShot dylib 和过滤 plist。

## 仍需实机验证

- 原生侧边键 + 音量加是否进入 `SpringBoard -takeScreenshot`
- `UICreateScreenUIImage` 在 iOS 15.6 RootHide SpringBoard 中的解析和画面内容
- Safari、视频界面和系统 UI 的冻结结果
- iPhone 13 Pro Max 3× 的最终裁剪坐标
- 工具条位置、Home Indicator 间距和横屏表现
- 透明窗口触摸穿透、多浮窗重叠、App 切换后的保留
- Photos 权限提示、保存结果和系统分享 presentation context
- 连续截图的内存释放、SpringBoard crash 与 watchdog 稳定性

## 风险

- `SpringBoard -takeScreenshot` 和 `UICreateScreenUIImage` 都是私有接口。代码只在运行时存在且签名符合预期时使用，但不同系统状态仍可能失败。
- statusbar-shot 只验证主动发送 `takeScreenshot` 的调用；实体截图组合键覆盖范围仍未知。
- 隐藏悬浮窗口后立即捕获依赖 iOS 合成时序，实机需确认旧悬浮图不会进入 frozenImage，也不会产生可见闪烁。
- 从非 key 的悬浮 UIWindow 根控制器弹出 UIActivityViewController 需要在目标环境实测。
- 竖屏是当前优先路径；旋转中的 selectionRect 重映射未增加额外兼容层。
