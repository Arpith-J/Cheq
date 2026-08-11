package com.example.cheq

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.net.Uri
import android.widget.RemoteViews
import org.json.JSONArray
import es.antonborri.home_widget.HomeWidgetBackgroundIntent
import es.antonborri.home_widget.HomeWidgetProvider

class PlannerWidgetProvider : HomeWidgetProvider() {

    private val PREFS_NAME = "HomeWidgetPreferences"
    private val WIDGET_DATA_KEY = "widget_data_planner"

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == ACTION_MARK_DONE) {
            forwardMarkDoneToBackground(context, intent)
            return
        }

        val actionType = intent.getStringExtra("action")
        
        when (actionType) {
            "TOGGLE_DONE" -> {
                val position = intent.getIntExtra("task_position", -1)
                if (position != -1) {
                    toggleTaskState(context, position)
                    refreshWidgetList(context)
                }
                return
            }
            "LAUNCH_APP" -> {
                val launchIntent = Intent(context, MainActivity::class.java).apply {
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                }
                context.startActivity(launchIntent)
                return
            }
        }
        
        super.onReceive(context, intent)
    }

    private fun forwardMarkDoneToBackground(context: Context, intent: Intent) {
        val uri = intent.data ?: run {
            val taskId = intent.getStringExtra("taskId")
            val uid = intent.getStringExtra("uid")
            if (taskId == null || uid == null) return
            Uri.Builder()
                .scheme(WIDGET_BACKGROUND_SCHEME)
                .authority(WIDGET_BACKGROUND_HOST)
                .appendQueryParameter("taskId", taskId)
                .appendQueryParameter("uid", uid)
                .build()
        }
        try {
            // Hands off to the plugin's background receiver, which spins up a
            // Dart isolate and runs the registered `backgroundCallback`.
            HomeWidgetBackgroundIntent.getBroadcast(context, uri).send()
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun toggleTaskState(context: Context, position: Int) {
        try {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val tasksJson = prefs.getString(WIDGET_DATA_KEY, null)
            
            if (!tasksJson.isNullOrEmpty()) {
                val tasksArray = JSONArray(tasksJson)
                if (position < tasksArray.length()) {
                    val task = tasksArray.getJSONObject(position)
                    val currentStatus = task.optBoolean("isDone", false)
                    
                    task.put("isDone", !currentStatus)
                    
                    prefs.edit()
                        .putString(WIDGET_DATA_KEY, tasksArray.toString())
                        .apply()
                }
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun refreshWidgetList(context: Context) {
        val appWidgetManager = AppWidgetManager.getInstance(context)
        val thisWidget = ComponentName(context, PlannerWidgetProvider::class.java)
        val allWidgetIds = appWidgetManager.getAppWidgetIds(thisWidget)
        appWidgetManager.notifyAppWidgetViewDataChanged(allWidgetIds, R.id.widget_list_view)
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        val widgetSkin = widgetData.getString("widget_skin", "default") ?: "default"

        for (appWidgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.widget_layout_planner)

            applyWidgetSkin(views, widgetSkin)

            // Setup Header / Empty View Tap to Launch
            val appLaunchIntent = Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            val pendingLaunchIntent = PendingIntent.getActivity(
                context, 0, appLaunchIntent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            views.setOnClickPendingIntent(R.id.widget_title, pendingLaunchIntent)
            views.setOnClickPendingIntent(R.id.empty_view, pendingLaunchIntent)

            // Setup List Adapter (Appended unique URI to bust Android 14 intent caching)
            val serviceIntent = Intent(context, WidgetRemoteViewsService::class.java).apply {
                putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
                putExtra("widget_data_key", WIDGET_DATA_KEY)
                data = Uri.parse("${Intent.URI_INTENT_SCHEME}://widget/id/$appWidgetId")
            }
            views.setRemoteAdapter(R.id.widget_list_view, serviceIntent)
            
            // NATIVE ANDROID MAGIC: Automatically handles the blank state. 
            // If the RemoteViewsService returns 0 items, Android natively displays the empty_view.
            views.setEmptyView(R.id.widget_list_view, R.id.empty_view)
            views.setViewVisibility(R.id.widget_list_view, android.view.View.VISIBLE)

            // Setup List Item Click Interception
            val clickIntent = Intent(context, PlannerWidgetProvider::class.java)
            val pendingIntentTemplate = PendingIntent.getBroadcast(
                context, 1, clickIntent, PendingIntent.FLAG_MUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            )
            views.setPendingIntentTemplate(R.id.widget_list_view, pendingIntentTemplate)

            appWidgetManager.updateAppWidget(appWidgetId, views)
            appWidgetManager.notifyAppWidgetViewDataChanged(appWidgetId, R.id.widget_list_view)
        }
    }

    private fun applyWidgetSkin(views: RemoteViews, widgetSkin: String) {
        when (widgetSkin) {
            "glass" -> {
                // Frosted translucent backdrop over whatever sits behind the widget.
                views.setInt(R.id.widget_root, "setBackgroundColor", 0x80000000.toInt())
            }
            "amoled" -> {
                // Pure black panel for deep power-saving blacks.
                views.setInt(R.id.widget_root, "setBackgroundColor", 0xFF000000.toInt())
                views.setTextColor(R.id.widget_title, 0xFFE0E0E0.toInt())
                views.setTextColor(R.id.empty_view, 0xFF888888.toInt())
            }
            // "default" keeps the existing background_dark layout untouched.
        }
    }
}
