package com.daengzah.daenotes

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews

class DaeNotesWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        manager: AppWidgetManager,
        widgetIds: IntArray,
    ) {
        widgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.daenotes_widget)
            views.setOnClickPendingIntent(
                R.id.widget_note,
                captureIntent(context, "note", widgetId * 2),
            )
            views.setOnClickPendingIntent(
                R.id.widget_todo,
                captureIntent(context, "todo", widgetId * 2 + 1),
            )
            manager.updateAppWidget(widgetId, views)
        }
    }

    private fun captureIntent(context: Context, kind: String, requestCode: Int): PendingIntent {
        val intent = Intent(context, QuickCaptureActivity::class.java).apply {
            putExtra(QuickCaptureActivity.EXTRA_KIND, kind)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK
        }
        return PendingIntent.getActivity(
            context,
            requestCode,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }
}
