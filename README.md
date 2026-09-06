# RegionShot

RegionShot 是面向 iPhone 13 Pro Max、iOS 15.6、Dopamine、RootHide 和 arm64e 的 SpringBoard 区域截图 tweak。它拦截 `SpringBoard -takeScreenshot`，冻结当前屏幕，允许框选和二次调整，然后把裁剪结果作为可跨 App 保留的悬浮图片。

## 当前功能

- 统一截图入口、内部捕获保护和重复触发保护
- 冻结图、选区外暗色遮罩、四角调整和选区移动
- Home Indicator 上方的五按钮胶囊工具条
- 从最初 frozenImage 按 CGImage 像素裁剪
- Selection 与 Floating UIWindow 绑定触发时的 UIWindowScene
- 多张悬浮截图、点击提升层级、空白区域触摸穿透
- 单指拖动、双指缩放、左右吸边、双击关闭
- 系统长按菜单：复制、保存、分享、隐藏当前、关闭当前、关闭全部
- Manager 的隐藏全部、恢复全部和关闭全部接口

“标记”“长截图”“扫码”只有按钮和日志占位；没有 OCR、二维码识别、长截图或图片编辑。

ShellX 二进制分析得到的可验证结论及采用范围见 [REVERSE_ENGINEERING.md](REVERSE_ENGINEERING.md)。

## 构建

需要 macOS/Xcode 和 RootHide Theos：

```sh
export THEOS=/path/to/roothide-theos
cc -std=c11 -Wall -Wextra -Werror Tests/test_geometry.c -lm -o /tmp/regionshot-geometry
/tmp/regionshot-geometry
make clean package FINALPACKAGE=1
```

GitHub Actions 工作流使用 `macos-14`，并检查 dylib 的 Mach-O CPU subtype 是否为现代 arm64e `0x80000002`。生成的 deb 位于 `packages/`。

## 实机日志顺序

先安装到具有可恢复环境的测试设备并重启 SpringBoard。用系统组合键和已验证的 `[[UIApplication sharedApplication] takeScreenshot]` 调用分别触发，查看以 `[RegionShot]` 开头的日志。预期入口日志为：

```text
[RegionShot] screenshot trigger
[RegionShot] beginCapture
[RegionShot] frozen image captured
```

如果没有找到 `UICreateScreenUIImage` 或捕获失败，RegionShot 会清理状态并调用原生截图实现。
