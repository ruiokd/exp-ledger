package com.yg.ledger

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.widget.RemoteViews

/**
 * 桌面小组件：只显示三个东西——今日净 EXP、等级、待确认数。
 *
 * 刻意不放：连续天数、排行、"你已退步"。
 * 小组件天天在眼前，放什么就等于在暗示什么。
 */
class LedgerWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        for (id in appWidgetIds) {
            appWidgetManager.updateAppWidget(id, buildViews(context))
        }
    }

    companion object {
        fun buildViews(context: Context): RemoteViews {
            val prefs = context.getSharedPreferences(MainActivity.PREFS, Context.MODE_PRIVATE)
            val views = RemoteViews(context.packageName, R.layout.ledger_widget)
            views.setTextViewText(R.id.widget_exp, prefs.getString("exp", "+0.0"))
            views.setTextViewText(R.id.widget_level, "等级 " + prefs.getString("level", "0"))
            views.setTextViewText(
                R.id.widget_pending,
                "待确认 " + prefs.getString("pending", "0")
            )
            return views
        }

        fun updateAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(
                ComponentName(context, LedgerWidgetProvider::class.java)
            )
            val views = buildViews(context)
            for (id in ids) {
                manager.updateAppWidget(id, views)
            }
        }
    }
}
