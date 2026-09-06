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

截图选择界面右上角齿轮打开“区域工具条”设置：排序、按钮开关、改名、图片图标（相册/文件）、
SF Symbol 名称、隐藏文字、图标 16–80 点和文字 8–16 点、恢复默认。大图标工具条支持横向滚动。
目前仅接入区域工具条，尚未覆盖浮窗/标记/编辑菜单、背景样式和 SF Symbols 图形选择器。

“扫码”可选择系统二维码/条码识别或本地 OCR，结果可选中复制；外部 OCR API、识别设置、翻译仍待实现。
“标记”仍为占位，图片编辑尚未完成。

## 长截图（开发中）

框选滚动内容后点“长截图”：先截取一段，手动向上滑动页面并保留至少四分之一的重叠内容，然后点“截取”。
也可点“采样”开启每 0.8 秒一次的采集，再自行滚动；“暂停”停止采样，“完成”生成悬浮长图。
选区应避开固定标题栏和底部栏。重复帧不添加，无法可靠匹配时提示回滚少许后重试。
临时分段保存在磁盘，成功完成或取消后清理；当前最终图最多 2,400 万像素或 100 段。

这还不是 ShellX 的三种完整长截图方式：自动短滑、持续自动上滑、固定栏检测、复杂重复内容及多方向拼接尚待实现。

## 0.3.0 图片问答（开发中）

长按悬浮截图 → 图片问答，点击标题配置支持图片的 Chat Completions 完整 HTTPS 地址、模型和 API Key。
密钥保存在系统钥匙串。支持图片和文字连续提问、流式显示、停止、复制、从旧提问重新生成、最小化和拖动恢复。
每条回复的刷新按钮旁有 `character.textbox` 分词按钮，通过进程内通知连接 KeyboardAI；需要相应新版 KeyboardAI。
图片附件支持系统相册和图片文件；拍照仅在宿主具备相机用途声明时启用，否则提示从相册导入。

这不是 ShellX 3.0.1 的完整复刻。自动滚动长截图、OCR/翻译、完整标记编辑、历史管理、全部详细设置、自定义图片/SF Symbols 图标、菜单排序/改名/显示/大小/背景和插件入口等仍待完成。
SpringBoard 中的系统图片选择器、键盘、相机权限及浮窗触摸需要 iOS 15.6 RootHide 实机验证。

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
