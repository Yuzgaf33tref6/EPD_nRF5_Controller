# AGENTS.md — EPD nRF5 Controller (Flutter/Android)

本文件给接手本仓库的 AI 助手与人类协作者看，用来说明这个项目要做什么、边界在哪、怎么验证。

## 项目定位

把 [tsl0922/EPD-nRF5](https://github.com/tsl0922/EPD-nRF5) 的 Web 上位机（`html/` 目录下的纯前端蓝牙控制器）本地化为 **Android Flutter 应用**。

目标是功能对等：用手机通过 BLE 控制 EPD-nRF5 固件的墨水屏，完成传图、抖动处理、清屏、校时等操作，不依赖 Web BLE。

## 分支模型

| 分支 | 用途 |
| --- | --- |
| `v0.3.x` | **当前开发分支**（0.3 系列），新功能、新特性都在这里 |
| `v0.2.x_main` | 0.2 系列的稳定主线，只为 0.2.x 的补丁修复而存在 |
| `main` | 最初的手搓代码，结构混乱，只留作考古参考 |
| `Old` | 已封存为 tag `archive/old-branch`，分支已删除 |

规则：**不要直接往 `v0.2.x_main` 或 `main` 提功能改动**。
功能开发提交到 `v0.3.x`；修 0.2 系列的 bug 才动 `v0.2.x_main`，并同步回 `v0.3.x`。

版本线对应关系：`vX.Y.x` 分支 ↔ `X.Y` 版本号。发版时从对应分支打 tag `vX.Y.Z`，由 `release.yml` 出包。

## 硬件与协议事实（必须严格遵守）

这些值来自固件源码，改动前请先核对上游。

### BLE UUID

- Service: `62750001-d828-918d-fb46-b6c11c675aec`
- 主特征（读写 + 通知）: `62750002-d828-918d-fb46-b6c11c675aec` — 所有命令都写这里
- 版本特征（只读）: `62750003-d828-918d-fb46-b6c11c675aec` — `byte[0]` 是 appVersion
- 命令特征支持的最大长度 = `NRF_SDH_BLE_GATT_MAX_MTU_SIZE - 3`；固件配 247，因此是 **244**

### 命令字（EpdCmd）

| 名称 | 值 |
| --- | --- |
| SET_PINS | 0x00 |
| INIT | 0x01 |
| CLEAR | 0x02 |
| SEND_CMD | 0x03 |
| SEND_DATA | 0x04 |
| REFRESH | 0x05 |
| SLEEP | 0x06 |
| SET_TIME | 0x20 |
| SET_WEEK_START | 0x21 |
| WRITE_IMG | 0x30 |
| SET_CONFIG | 0x90 |
| SYS_RESET | 0x91 |
| SYS_SLEEP | 0x92 |
| CFG_ERASE | 0x99 |

### 连接流程

1. 连接设备后读取版本特征，`byte[0]` = appVersion。
2. 若 `appVersion < 0x16`，提示使用旧版上位机，不要继续。
3. 订阅主特征通知。**注意时序**：固件在 CCCD（0x2902）被写成「开启通知」的瞬间就推配置，
   Android 侧若是「先写 CCCD 再注册本地路由」会丢掉这第一包 —— 本项目在
   `third_party/reactive_ble_mobile` 里把 `NotificationSetupMode.DEFAULT` 改成了
   `QUICK_SETUP` 来解决，不要回退这个补丁。
4. 自动发送 `INIT`（0x01）。
5. 连接后第一条通知是**配置通知**（13 字节）：`bytes[0..7)` 为 7 字节引脚，`bytes[7]` 为驱动 id，
   `bytes[8]` = wakeup_pin，`bytes[9]` = led_pin，`bytes[10]` = en_pin，
   `bytes[11]` = display_mode，`bytes[12]` = week_start。
6. 之后的通知是 UTF-8 文本：`mtu=<n>`、`rle=1`、`t=<unix>`。**`mtu=` 的值其实是 `max_data_len`
   （即 MTU-3），不是协商到的 MTU。**

### RLE 是否启用

**只认固件通知里的 `rle=1`**（与 Web 版 `main.js:404` 同规则），**不要按固件版本号猜**。
固件版本 ≥ 0x16 并不代表它支持 RLE —— 0x19 就不支持。

### WRITE_IMG 分块（最容易写错的地方）

```
chunkSize = mtuSize - 2
// 无 RLE: flag = (step=='bw' ? 0x0F : 0x00) | (i===0 ? 0x00 : 0xF0)
// 有 RLE: flag = (step=='bw' ? 0x00 : 0x01) | (i===0 ? 0x02 : 0x00) | 0x04
// 每 interleavedCount 块用一次带响应写，其余用无响应写
```

固件侧 flag 语义：`BIT0` = 颜色（black/red），`BIT1` = 起始块，`BIT2` = 启用 RLE。

**实测约束**：单条写请求的数据不能超过 `ATT_MTU - 3`。超 1 个字节 Android 就会降级成长写，
固件把碎片当独立命令执行，RLE 流断裂 → 固件卡死 → 30 秒后 GATT 133 断链。
nRF51 链路层 PDU 只有 27 字节，一次灌满 244 字节会让外设来不及应答，所以本 App 默认用
「最大」档 242 字节，并给每条写加间隔。

### RLE 编码

- 重复段（连续 >= 3 字节，最长 130）：`0x80 | (runLen - 3)` + 1 字节值
- 字面段（最长 128）：`litLen - 1` + litLen 字节
- 仅当压缩后总长 < 原长时才启用 RLE

## 目标设备

当前主要目标是 **4.2 寸三色（黑白红）墨水屏**，驱动 id `0x03` 或 `0x02`（SSD1619）。
用户实测固件 0x19、驱动 0x02。

## 开发与验证约束

**本项目的开发机是轻薄笔记本，没有安装 Flutter/Android 构建环境，也无法本地编译。**

这意味着：

1. **所有构建验证必须在 GitHub Actions 上完成**。任何声称「编译通过」的结论都必须有对应的 Actions 运行记录作为证据。
2. 本地只能做：读代码、改代码、写文档、通过 GitHub API 提交。
3. 千万不要建议或假设本地能跑 `flutter build` / `flutter analyze` / `flutter test`。
4. `flutter analyze` 对 **warning / info 也返回 exit 1** —— 未使用的 import、废弃 API 都会挂 CI。

## 工作方式

- CI：`.github/workflows/ci.yml`（analyze → test → build debug APK → build release APK）。
- 发布：`.github/workflows/release.yml`，推 `v*` tag 触发；用 Actions Secrets 里的固定 keystore 签名。
- 涉及 BLE 协议字节序、分块大小、抖动算法的改动，必须说明与 Web 版实现的对应关系。
- 纯 Dart 核心层（协议 / RLE / 抖动 / 位打包 / 传图编排 / 裁剪几何）都有 **golden 对拍测试**，
  期望值由 Node 直接 eval 上游 `html/js/*.js` 生成，不要手写期望值。
- 第三方依赖一律钉死版本（见 `pubspec.yaml` 注释），原生插件的 AGP / Kotlin / compileSdk
  要求必须先核对，本项目固定 Flutter 3.44.9 / AGP 8.11.1 / Kotlin 2.2.20 / compileSdk 36。

## 目录结构

```
lib/
├── devices/   驱动表（17 种）与画布尺寸表（26 种）
├── image/     调色板、Lab 色差、抖动、位打包、UC8159、裁剪、编辑、文字
├── protocol/  RLE、命令字、传图编排、调试指令
├── services/  BLE 链路、模拟 BLE、选图、设置存储、更新检查
├── state/     AppState（全局状态与业务编排）
├── screens/   界面
└── widgets/   通用组件
third_party/reactive_ble_mobile/   内置的补丁插件源码（见其 PATCH.md）
test/         单元测试 + golden 对拍
```

## 上游参考

- 固件与 Web 上位机：<https://github.com/tsl0922/EPD-nRF5>
- Web 版核心文件：`html/js/main.js`（BLE 与业务流程）、`html/js/dithering.js`（抖动与位打包）、`html/js/rle.js`（RLE 压缩）、`html/js/crop.js`（裁剪几何）、`html/index.html`（UI 与全部驱动/尺寸选项）

## 许可证

本仓库沿用 GPL-3.0。提交的代码需与之一致。
