package com.example.cheq

import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import android.widget.RemoteViewsService
import org.json.JSONArray

class WidgetRemoteViewsService : RemoteViewsService() {
    override fun onGetViewFactory(intent: Intent): RemoteViewsFactory {
        // Each widget provider stamps its own prefs key onto the service
        // intent, so this single service can serve Today, Planner & Todo lists.
        val widgetDataKey = intent.getStringExtra("widget_data_key") ?: "widget_data_today"
        return WidgetDataProviderFactory(applicationContext, widgetDataKey)
    }
}

class WidgetDataProviderFactory(
    private val context: Context,
    private val widgetDataKey: String,
) : RemoteViewsService.RemoteViewsFactory {
    private var tasksArray = JSONArray()
    private val PREFS_NAME = "HomeWidgetPreferences"

    override fun onCreate() { loadData() }
    override fun onDataSetChanged() { loadData() }
    override fun onDestroy() { tasksArray = JSONArray() }

    private fun loadData() {
        tasksArray = JSONArray() // Clear old cache
        try {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val tasksJson = prefs.getString(widgetDataKey, null)

            if (!tasksJson.isNullOrEmpty()) {
                tasksArray = JSONArray(tasksJson)
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    override fun getCount(): Int = tasksArray.length()

    override fun getViewAt(position: Int): RemoteViews {
    if (position < 0 || position >= tasksArray.length()) {
        return RemoteViews(context.packageName, R.layout.widget_item_row)
    }

    val views = RemoteViews(context.packageName, R.layout.widget_item_row)
    try {
        val task = tasksArray.getJSONObject(position)
        val title = task.optString("title", "Untitled")
        val isDone = task.optBoolean("isDone", false)
        val time = task.optString("time", "")
        val date = task.optString("date", "")

        views.setTextViewText(R.id.row_check_icon, if (isDone) "✓" else "○")
        views.setTextViewText(
            R.id.row_task_text,
            if (time.isNotEmpty()) "$time | $title" else title
        )
        views.setTextViewText(R.id.row_date_text, date)

        val appLaunchIntent = Intent().apply {
            putExtra("action", "LAUNCH_APP")
        }
        views.setOnClickFillInIntent(R.id.row_root, appLaunchIntent)

        val checkboxToggleIntent = Intent().apply {
            putExtra("action", "TOGGLE_DONE")
            putExtra("task_position", position)
        }
        views.setOnClickFillInIntent(R.id.row_check_icon, checkboxToggleIntent)

    } catch (e: Exception) {
        e.printStackTrace()
    }
    return views
}

    override fun getLoadingView(): RemoteViews? = null
    override fun getViewTypeCount(): Int = 1
    override fun getItemId(position: Int): Long = position.toLong()
    override fun hasStableIds(): Boolean = true
}
