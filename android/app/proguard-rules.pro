# Flutter 与通知插件需要保留的类（R8 混淆开启后本地通知回调易被裁剪）
-keep class io.flutter.** { *; }
-keep class com.dexterous.flutterlocalnotifications.** { *; }
-keep class cn.leanpath.app.** { *; }

# 保留注解与签名信息，避免插件反射失效
-keepattributes *Annotation*
-keepattributes Signature
-keepattributes SourceFile,LineNumberTable

# 序列化模型（计划数据落 SharedPreferences 用 JSON，字段不参与反射但保留更安全）
-keepclassmembers class cn.leanpath.app.** { *; }

-dontwarn io.flutter.**
-dontwarn com.dexterous.flutterlocalnotifications.**
