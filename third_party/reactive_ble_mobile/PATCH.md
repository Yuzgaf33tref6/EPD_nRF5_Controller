# 本地补丁说明（reactive_ble_mobile 5.5.0）

本目录是 `reactive_ble_mobile` 5.5.0 的源码快照（BSD 许可，见 `LICENSE`），
通过根目录 `pubspec.yaml` 的 `dependency_overrides` 指向这里，用来打一个**必须**的补丁。

升级方式：从 pub.dev 重新取同版本源码覆盖本目录，然后重新应用下面的改动。

## 改动：通知订阅模式 DEFAULT → QUICK_SETUP

文件：`android/src/main/kotlin/com/signify/hue/flutterreactiveble/ble/ReactiveBleClient.kt`
函数：`setupNotificationOrIndication(...)`

```kotlin
val mode =
    if (characteristic.descriptors.isEmpty()) {
        NotificationSetupMode.COMPAT
    } else {
        NotificationSetupMode.QUICK_SETUP   // 上游为 DEFAULT
    }
```

### 为什么必须改

EPD-nRF5 固件在**收到 CCCD（开启通知）写入的那一刻**就把 12/13 字节的
配置结构体（引脚 + 驱动号 + 显示模式等）推送一次 —— 见 `EPD/EPD_service.c:275`。
如果这次没收到，固件之后永远不会再主动发，App 就只能靠人工选驱动。

RxAndroidBle 的 `NotificationSetupMode.DEFAULT` 的官方 javadoc 明确写着：
> The `Observable<byte[]>` is emitted after both the system notification is set and the
> CLIENT_CHARACTERISTIC_CONFIG descriptor was written so the notification is fully set up.
> If a device starts to notify right after CLIENT_CHARACTERISTIC_CONFIG is written then
> **some early notifications may be lost** — see `QUICK_SETUP`

`QUICK_SETUP` 则是在写 CCCD **之前**先把 `Observable<byte[]>` 交给上层，从而能接收
「CCCD 一写完就发」的那条通知。

实测证据（`Logcat/logcat_2026-11-19_03-26-03.txt`）：开关 CCCD 三轮，每轮都只有
`mtu=244`（7 字节）与 `t=...`（12 字节）两条通知，13 字节配置通知一次都没到，
与上面的「early notifications lost」完全一致。
