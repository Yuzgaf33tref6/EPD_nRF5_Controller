# R8/ProGuard 规则（release 构建开启 isMinifyEnabled 后生效）。
#
# Flutter 引擎与插件注册表依赖反射：GeneratedPluginRegister 会用
# Class.forName("io.flutter.plugins.GeneratedPluginRegistrant") 找到自动生成的
# 注册表类，被裁掉就会在运行时直接崩。这里保守地整包保留 io.flutter.*。

-keep class io.flutter.app.** { *; }
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.plugins.GeneratedPluginRegistrant { *; }

# 保留注解元数据（插件里的 @Keep / 运行时校验会用到）。
-keepattributes *Annotation*

# Play Core 相关类只在「延迟组件（deferred components）」里被 Flutter 引擎引用，
# 而延迟组件是上架 Google Play 才需要的可选特性，本项目不用，也没有引入
# com.google.android.play:core 依赖。R8 检查到这些「被引用但不存在的类」会直接
# 报 Missing class 并中断构建，所以显式关掉对这些类的警告。
-dontwarn com.google.android.play.core.**
