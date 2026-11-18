package com.example.epd_controller

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * 主 Activity。
 *
 * 除了标准的 FlutterActivity，只额外提供一条很小的原生通道 `epd_controller/storage`：
 * 把 App 私有目录（`filesDir`）告诉 Dart 侧，让它能往那里写设置文件。
 *
 * 之所以自己写这条通道，是为了避免引入 `path_provider` / `shared_preferences`
 * 这类插件 —— 它们的 Android 实现要求更高的 AGP / Kotlin 版本，和本项目的
 * AGP 8.11.1 / Kotlin 2.2.20 有冲突风险。
 */
class MainActivity : FlutterActivity() {
    private companion object {
        const val STORAGE_CHANNEL = "epd_controller/storage"
        const val METHOD_GET_FILES_DIR = "getFilesDir"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, STORAGE_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    METHOD_GET_FILES_DIR -> result.success(filesDir.absolutePath)
                    else -> result.notImplemented()
                }
            }
    }
}
