# AGENTS.md — EPD nRF5 Controller (Flutter/Android)

本文件给接手本仓库的 AI 助手与人类协作者看，用来说明这个项目要做什么、边界在哪、怎么验证。

## 项目定位

把 [tsl0922/EPD-nRF5](https://github.com/tsl0922/EPD-nRF5) 的 Web 上位机（`html/` 目录下的纯前端蓝牙控制器）本地化为 **Android Flutter 应用**。

目标是功能对等：用手机通过 BLE 控制 EPD-nRF5 固件的墨水屏，完成传图、抖动处理、清屏、校时等操作，不依赖 Web BLE。

## 仓库状态说明

- `main` 分支：早期尝试的代码，结构混乱，**仅作参考，不再演进**。
- `rebuild` 分支：当前工作分支，从头重写。

新代码一律提交到 `rebuild`，**不要**直接改 `main`。

## 硬件与协议事实（必须严格遵守）

这些值来自固件源码，改动前请先核对上游。

### BLE UUID

- Service: `62750001-d828-918d-fb46-b6c11c675aec`
- 主特征（读写 + 通知）: `62750002-d828-918d-fb46-b6c11c675aec` — 所有命令都写这里
- 版本特征（只读）: `62750003-d828-918d-fb46-b6c11c675aec` — `byte[0]` 是 appVersion

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
3. 订阅主特征通知。
4. 自动发送 `INIT`（0x01）。
5. 连接后第一条通知是**配置通知**：`bytes[0..7)` 为 7 字节引脚，`bytes[7]` 为驱动 id。之后的通知是 UTF-8 文本，含 `mtu=<n>`、`rle=1`、`t=<unix>` 等字段。

### WRITE_IMG 分块（最容易写错的地方）

```
chunkSize = mtuSize - 2
// 无 RLE: flag = (step=='bw' ? 0x0F : 0x00) | (i===0 ? 0x00 : 0xF0)
// 有 RLE: flag = (step=='bw' ? 0x00 : 0x01) | (i===0 ? 0x02 : 0x00) | 0x04
// 每 interleavedCount 块用一次带响应写，其余用无响应写
```

固件侧 flag 语义：`BIT0` = 颜色（black/red），`BIT1` = 起始块，`BIT2` = 启用 RLE。

### RLE 编码

- 重复段（连续 >= 3 字节，最长 130）：`0x80 | (runLen - 3)` + 1 字节值
- 字面段（最长 128）：`litLen - 1` + litLen 字节
- 仅当压缩后总长 < 原长时才启用 RLE

## 目标设备

当前主要目标是 **4.2 寸三色（黑白红）墨水屏**，驱动 id `0x03` 或 `0x02`。

## 开发与验证约束

**本项目的开发机是轻薄笔记本，没有安装 Flutter/Android 构建环境，也无法本地编译。**

这意味着：

1. **所有构建验证必须在 GitHub Actions 上完成**。任何声称「编译通过」的结论都必须有对应的 Actions 运行记录作为证据。
2. 本地只能做：读代码、改代码、写文档、通过 GitHub API 提交。
3. 千万不要建议或假设本地能跑 `flutter build` / `flutter analyze` / `flutter test`。

## 工作方式

- 当前没有 Flutter CI workflow，需要建立（`flutter analyze` + `flutter build apk`）。
- 改动以 PR 形式合入 `rebuild`，由 Actions 提供验证证据。
- 涉及 BLE 协议字节序、分块大小、抖动算法的改动，必须在 PR 描述里说明与 Web 版实现的对应关系。

## 上游参考

- 固件与 Web 上位机：<https://github.com/tsl0922/EPD-nRF5>
- Web 版核心文件：`html/js/main.js`（BLE 与业务流程）、`html/js/dithering.js`（抖动与位打包）、`html/js/rle.js`（RLE 压缩）、`html/index.html`（UI 与全部驱动/尺寸选项）

## 许可证

本仓库沿用 GPL-3.0。提交的代码需与之一致。