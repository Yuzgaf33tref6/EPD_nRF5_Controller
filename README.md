# EPD Controller

EPD-nRF5 墨水屏的 **Android 客户端**（Flutter）。把原项目
[tsl0922/EPD-nRF5](https://github.com/tsl0922/EPD-nRF5) 的 Web 上位机功能搬到手机上：
手机直接通过 BLE 连墨水屏，选图、裁剪、抖动、传图、刷新，全在手机上完成，不需要电脑。

固件不用改，协议与 Web 版**逐字节对齐**。

---

## 功能

**连接与设备控制**

- BLE 扫描 / 连接 / 断开，意外断开会自动重连
- 连接后自动读固件版本、协商 MTU、接收固件推送的引脚与驱动配置
- 时间同步（日历模式 / 时钟模式）、清屏、刷新、睡眠，指令按钮直接标注命令字（0x20 / 0x02 / 0x05 / 0x06）
- 设备信号强度（RSSI）实时显示，可手动刷新
- 「设备指令 · 调试」页：0x03 发送命令、0x04 写数据、0x21 周起始日、0x90 自定义配置、
  0x91 系统重启、0x92 系统睡眠、0x99 恢复默认配置，全部十六进制输入并有参数校验提示；
  其中 0x92 会按配置里的唤醒引脚做安全判定（未配置唤醒脚直接禁用）
- 「权限检查」页：集中查看 / 申请本应用需要的全部系统权限
- 「蓝牙诊断」页：适配器状态、纯色测试（排查平面极性）、原始通知查看、详细传输日志

**图像处理（全部与 Web 版 golden 对拍）**

- 6 种抖动算法：Floyd–Steinberg / Atkinson / Stucki / Jarvis / Bayer / 无抖动
- 强度、对比度可调
- 4 种色彩模式：黑白 / 三色（黑白红）/ 四色 / 六色
- 位打包与 UC8159 合并写入（低分屏驱动）
- RLE 压缩（是否启用由固件通知决定，与 Web 版一致）

**画布**

- 从相册导入图片（原图最长边上限 4096）→ 拖动/双指缩放裁剪（0.1~5 倍）→ 旋转 90°
- 裁剪取景框就是画布比例：框里看到什么就发什么；可以缩到比取景框小，
  四周按底色（白 / 黑）补齐
- 手绘画布：画笔、橡皮、撤销/重做、填白、粗细、6 种颜色
- 文字工具：输入文字后可拖动定位，再合成进画布
- 双缓冲分层重绘 + 后台 isolate 算抖动，滑动参数时预览不卡

**传图**

- 分块档位：稳定 / 正常 / 快速 / 最大 / 自定义（自定义可单独指定每块字节数）
- 每条写指令都等设备确认，超时/失败自动重试，意外断开自动重连
- 设置持久化到 App 私有目录：主题、驱动、分块档位、交错块数、RLE、详细日志都会记住

---

## 下载与安装

到 [Releases](../../releases) 下载最新的安装包，文件名格式为
`EPDController-<版本号>-<ABI>.apk`：

| 文件 | 适用 |
| --- | --- |
| `EPDController-0.2.1-arm64-v8a.apk` | 绝大多数手机（推荐） |
| `EPDController-0.2.1-armeabi-v7a.apk` | 较老的 32 位设备 |
| `EPDController-0.2.1-x86_64.apk` | 模拟器 |

发布页同时给出每个文件的 SHA-256（也在 `SHA256SUMS.txt` 里），可自行校验。

- 首次安装需要允许「安装未知来源应用」。
- 从 0.1.0 起签名固定，**同版本线内可以直接覆盖安装升级**；如果你装过 0.1.0 之前的临时构建，需要先卸载一次。
- 打开应用会自动申请蓝牙权限，也可以到 **设置 → 权限检查** 查看每一项的授权状态。

---

## 兼容性

- **固件**：[EPD-nRF5](https://github.com/tsl0922/EPD-nRF5) nRF51822 / nRF51802 系列。
  RLE 支持以固件连接后推送的通知为准（Web 版同规则），不是按版本号猜的。
- **驱动**：内置 17 种驱动型号（`01`~`11`），覆盖 4.2" / 5.83" / 7.5" 的黑白、三色、四色屏。
  连上设备后会自动按固件上报的驱动号匹配；也可以手动指定。
- **画布尺寸**：26 种预设（1.54" ~ 7.5"），选中驱动会自动联动颜色模式与画布尺寸。
- **Android**：`minSdk` 由 Flutter 默认值决定（本项目构建环境为 Flutter 3.44.9），需要蓝牙 4.0+。

---

## 使用流程（最短路径）

1. 首次打开会自动申请蓝牙权限（Android 12+ 的「附近的设备」）。
   没给的话到 **设置 → 权限检查** 重新申请，或去系统设置里打开。
2. **首页 → 连接设备** → 扫描 → 点设备连接。连上后状态卡会显示固件版本、驱动、画布与信号强度。
3. **发送** → 「图像发送」→ 用「导入图片」选图并裁剪，或进「画布编辑」手绘/加字。
4. 调抖动算法、强度、对比度，看预览满意后 → **发送到设备**。
5. 屏幕会闪烁几秒完成整屏刷新（墨水屏 2~10 秒属正常，别急着断电）。

---

## 与 Web 版的关系

这不是"重新实现一遍"，而是**把 Web 版的字节级行为原样搬到 Dart**：

- 协议命令字、RLE 编解码、传图分块与 flag、通知解析：用 Node 直接 eval 原仓库的
  `html/js/rle.js` / `main.js` 生成 golden 向量，Dart 侧逐字节对拍。
- 抖动算法、调色板、Lab 色差、位打包、UC8159 转换：同样用 golden 对拍，
  包含 400×300 真实尺寸用例。
- 裁剪几何（`crop.js`）也对拍过，缩放范围 0.1~5 倍与原版一致。

目前共 **897 个测试**，全部是"跟原 JS 实现对比"，而不是自己跟自己对。

在这之上补了 Web 版没有的东西：分块档位、写入重试、自动重连、通知缓冲、
设置持久化、手绘画布、图像导入裁剪、纯色诊断。

---

## 项目结构

```
lib/
├── devices/   驱动表（17 种）与画布尺寸表（26 种）
├── image/     调色板 / Lab 色差 / 抖动 / 位打包 / 裁剪几何 / 画笔 / 文字 / 变换
├── models/    分块档位等枚举
├── protocol/  命令字、RLE、传图编排（生成完整写指令序列）
├── services/  BLE 链路、图片选择、设置存储
├── state/     AppState（ChangeNotifier）—— 唯一的业务状态源
├── screens/   首页 / 连接 / 画布 / 画布编辑 / 裁剪 / 设置 / 蓝牙诊断
└── widgets/   预览、日志面板、卡片
third_party/reactive_ble_mobile/   内置的插件源码（打了 1 处补丁，见其 PATCH.md）
test/                              单元测试 + golden 向量
```

BLE 链路层（`services/ble_service.dart`）只负责"连上、读写、收发通知"；
协议语义全在 `protocol/` 与 `state/app_state.dart`，所以测试不需要真机。

---

## 构建

本地构建需要 Flutter 3.44.9（Material 拆成 `material_ui` 独立包之前的最后一条 stable 线）：

```bash
flutter --version   # 需要 3.44.9
flutter pub get
flutter analyze     # 注意：info 级问题也会返回非 0
flutter test
flutter build apk --release --split-per-abi \
  --target-platform android-arm,android-arm64,android-x64
```

仓库也提供了两条 CI（都在 GitHub Actions 上跑，本机不需要 Android SDK）：

| workflow | 触发 | 内容 |
| --- | --- | --- |
| `ci.yml` | push / PR 到 `v0.3.x`、`v0.2.x_main`、`main` | analyze + test + debug & release（仅 arm64），上传 APK 产物 |
| `release.yml` | 打 `v*` tag | analyze + test + **全 ABI 仅 release**，生成 `SHA256SUMS.txt` 并发布 Release |

发版流程：

```bash
# 改 pubspec.yaml 的 version，提交后打 tag
git tag v0.3.0 && git push origin v0.3.0
```

### 分支模型

| 分支 | 用途 |
| --- | --- |
| `v0.3.x` | 当前开发分支（0.3 系列） |
| `v0.2.x_main` | 0.2 系列稳定主线，只做补丁修复 |
| `main` | 最初的手搓代码，只作考古参考 |

版本线和分支一一对应：在哪个分支上打 tag，就出哪个系列的包。

release 签名从仓库 Secrets 读取（`ANDROID_KEYSTORE_BASE64` 等 4 个），
所以每次发布签名一致；keystore 不进仓库。

---

## 已知限制 / 待办

- 三色屏整屏刷新需要 2~10 秒，期间闪烁/变灰是正常现象。
- 传图依赖固件应答，链路偶发不稳时靠重试与自动重连兜底；日志里能看到每条写指令。
- 待办：**UI 打磨**（现在功能齐了，界面还比较朴素）、**功能补齐**（更多 Web 版细节、字体/字号选项、模板等）。

---

## 许可证

[GPL-3.0](LICENSE)，与上游 [EPD-nRF5](https://github.com/tsl0922/EPD-nRF5) 保持一致。

内置的 `third_party/reactive_ble_mobile` 为 BSD-3-Clause（Signify Holding），其 `LICENSE` 随源码保留。

---

## 致谢

- [tsl0922/EPD-nRF5](https://github.com/tsl0922/EPD-nRF5)：固件与 Web 上位机，本项目的协议与算法来源。
- [flutter_reactive_ble](https://pub.dev/packages/flutter_reactive_ble)：BLE 链路。
- [image_picker](https://pub.dev/packages/image_picker)：相册选图。
