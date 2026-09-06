# ShellX 区域截图逆向记录

分析对象是用户提供的 `com.iosdump.shellx_2.9.0_iphoneos-arm64e.deb`。输入包的 SHA-256 为
`D4F8011E586429B1F8D0F7F75807AC44E45A3883901FF4503B9F20A46F2FABCD`。仓库不包含该 deb、
它的二进制文件或反编译源码。

## 已确认的实现证据

- 注入过滤包含 `com.apple.springboard`，主动态库包含现代 arm64e slice。
- `SSAreaCaptureManager` 创建 `SSAreaCaptureWindow` 时，优先调用 `initWithWindowScene:`，没有可用
  scene 时才回退到 `initWithFrame:`，最后通过 `makeKeyAndVisible` 显示选择窗口。
- `SSAreaCaptureWindow -freezeScreen` 直接调用 `UICreateScreenUIImage`，并保存原始截图、捕获时窗口
  bounds 和界面方向；选择界面显示的是冻结图，不会暂停底层 App。
- `-extractCroppedImage` 优先使用保存的原始截图，将选区从 UIKit point 换算到图像像素，与图像边界
  求交后调用 `CGImageCreateWithImageInRect`。冻结图失效时才重新截图。
- 区域选择由 `selectionRect`、`dragStartRect` 和自定义触摸识别器驱动，支持新建、移动及四角调整。
- 浮窗实现明确包含触摸命中、拖动、缩放、复制、保存、分享和删除入口。

## RegionShot 采用的结论

RegionShot 保持独立实现，只复用上述可观察到的系统接口和交互设计：截图入口统一进入 Manager；
Selection UI 创建前只捕获一次原始高清图；确认时只裁剪该图；Selection 与 Floating UIWindow 绑定
触发截图时所在的 `UIWindowScene`；透明浮窗区域继续触摸穿透。

以上是 0.2.0 时的分析范围。用户随后扩展范围为区域截图及相关全部功能，保留排除套壳截图的要求；
OCR、二维码、翻译、长截图、标记、AI 交互等现在属于待实现范围。旧排除项不再作为开发限制。

## ShellX 3.0.1

新包 SHA-256：`191DEBEF2DEBFBC9BCEE38984402D7F60E6D946FA936638540B94C73DC245E8B`。
现代 arm64e slice 为 2,197,488 字节；已建立 1,476 个 Objective-C 方法地址索引，并导出
`__TEXT.__text` 的 406,055 条指令。完整反汇编是分析材料，不代表已经恢复源代码或功能完全还原。

核对过的入口（地址只适用于该包的 arm64e slice）：

| 功能 | 方法 | 实现地址 | 证据 |
| --- | --- | --- | --- |
| 冻结屏幕 | `SSAreaCaptureWindow freezeScreen` | `0x1155e8` | 隐藏叠加层、调用 `UICreateScreenUIImage`、方向修正、保存原图及捕获状态 |
| 裁剪 | `extractCroppedImage` | `0x113744` | 优先原图，读取捕获 bounds/orientation；失败分支才重新截图 |
| 映射裁剪 | `ss_cropImage:inWindow:sel:fill:` | `0x113478` | 展平图像方向、fill 分支使用等比填充及居中偏移、与像素边界求交后裁剪 |
| 回复气泡 | `SSAIChatCardController ss_aiBubbleWithText:` | `0xba578` | `SSAIReplyText`，复制/刷新按钮，刷新标识“重新回答”，横向 `UIStackView` |
| 最小化 | `ss_minimize` | `0xb7b1c` | 状态守卫、停止显示更新、关闭切换器/键盘、卡片收起；此方法不取消网络任务 |
| 发送 | `ss_send` | `0xbbdcc` | 已定位并导出，尚未逐个确认所有分支 |
| 重新生成 | `ss_regenReply:` | `0xbffc0` | 从按钮父链寻找回复行，读取关联提问索引，截断后续历史与行，调用 `ss_fireFromHistory` |

3.0.1 新增相册、文件和相机附件方法以及独立相机控制器；设置包还包含 AI 引擎、人格、悬浮球、窗口主题、
区域激活、菜单顺序/大小/背景、长截图方式、OCR、翻译、历史限额、快捷指令等控制器。
这些元数据证实有相关入口，具体行为必须继续用实现和设备观察核对，不能只靠名称认定已复刻。

RegionShot 的 AI 窗口为独立实现，通过用户配置的服务请求回复，不依赖 ShellX 私有服务。
协议参考：[Chat Completions](https://developers.openai.com/api/reference/resources/chat)。
