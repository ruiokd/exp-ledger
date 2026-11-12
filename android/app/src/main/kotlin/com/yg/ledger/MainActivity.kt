package com.yg.ledger

import android.content.Context
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * 唯一一个平台通道：把"今日净 EXP / 等级 / 待确认数"推给桌面小组件。
 *
 * 为什么不让小组件自己算：算法全在 Dart 的 domain 层，
 * 在 Kotlin 里再实现一遍必然会漂移。这里只搬运渲染好的字符串。
 */
class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "push" -> {
                    val prefs = getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                    prefs.edit()
                        .putString("exp", call.argument<String>("exp") ?: "+0.0")
                        .putString("level", call.argument<String>("level") ?: "0")
                        .putString("pending", call.argument<String>("pending") ?: "0")
                        .apply()
                    LedgerWidgetProvider.updateAll(this)
                    result.success(true)
                }
                "clear" -> {
                    getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().clear().apply()
                    LedgerWidgetProvider.updateAll(this)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    companion object {
        const val CHANNEL = "exp_ledger/widget"
        const val PREFS = "ledger_widget"
    }
}
