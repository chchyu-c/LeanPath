package cn.leanpath.app

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.TimeZone

/**
 * 提供两个平台能力给 Dart 层（不引入额外第三方插件）：
 * 1. getTimeZone   —— 返回设备 IANA 时区 ID，用于精确调度本地通知；
 * 2. openBatterySettings —— 引导关闭电池优化，保证国内厂商 ROM 上闹铃准时。
 */
class MainActivity : FlutterActivity() {

    companion object {
        private const val CHANNEL = "cn.leanpath.app/device"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getTimeZone" -> result.success(TimeZone.getDefault().id)
                    "openBatterySettings" -> {
                        openBatterySettings()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun openBatterySettings() {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
                if (!pm.isIgnoringBatteryOptimizations(packageName)) {
                    val intent =
                        Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                            data = Uri.parse("package:$packageName")
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                    startActivity(intent)
                    return
                }
            }
            val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                data = Uri.parse("package:$packageName")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
        } catch (e: Exception) {
            // 部分厂商 ROM 未提供对应设置页：静默降级，Dart 层会提示用户手动设置。
            val intent = Intent(Settings.ACTION_SETTINGS)
            startActivity(intent)
        }
    }
}
