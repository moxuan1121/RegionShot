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

ShellX 中的许可校验、网络、录屏、OCR、二维码、翻译、长截图、标记和插件系统均不属于本项目，
没有移植。
