package com.example.cheq

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.net.Uri
import android.widget.RemoteViews
import android.view.View
import org.json.JSONArray
import es.antonborri.home_widget.HomeWidgetProvider

class DailyTaskWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        for (appWidgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.widget_layout)
            views.setTextViewText(R.id.widget_title, "Moon Tasks")

            // Binding the background dynamic collection engine
            val serviceIntent = Intent(context, WidgetRemoteViewsService::class.java).apply {
                putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
                data = Uri.parse(toUri(Intent.URI_INTENT_SCHEME))
            }
            views.setRemoteAdapter(R.id.widget_list_view, serviceIntent)

            val tasksJsonString = widgetData.getString("flutter.daily_tasks_key", null)
                ?: widgetData.getString("daily_tasks_key", null)

            if (!tasksJsonString.isNullOrEmpty() && JSONArray(tasksJsonString).length() > 0) {
                // We have data! Show the list, hide the empty text completely
                views.setViewVisibility(R.id.empty_view, View.GONE)
                views.setViewVisibility(R.id.widget_list_view, View.VISIBLE)
            } else {
                // Empty state! Hide the list completely, reveal the empty text
                views.setViewVisibility(R.id.widget_list_view, View.GONE)
                views.setViewVisibility(R.id.empty_view, View.VISIBLE)
                views.setTextViewText(R.id.empty_view, "No tasks scheduled for today!")
            }

            // Click handling template
            val intent = context.packageManager.getLaunchIntentForPackage(context.packageName)
            if (intent != null) {
                val pendingIntent = PendingIntent.getActivity(
                    context, 0, intent, 
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
                views.setPendingIntentTemplate(R.id.widget_list_view, pendingIntent)
                views.setOnClickPendingIntent(R.id.widget_root, pendingIntent)
            }

            appWidgetManager.updateAppWidget(appWidgetId, views)
            appWidgetManager.notifyAppWidgetViewDataChanged(appWidgetId, R.id.widget_list_view)
        }
    }
}