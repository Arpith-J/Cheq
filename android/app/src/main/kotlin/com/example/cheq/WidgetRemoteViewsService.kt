package com.example.cheq

import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import android.widget.RemoteViewsService
import org.json.JSONArray

class WidgetRemoteViewsService : RemoteViewsService() {
    override fun onGetViewFactory(intent: Intent): RemoteViewsFactory {
        return WidgetDataProviderFactory(applicationContext)
    }
}

class WidgetDataProviderFactory(private val context: Context) : RemoteViewsService.RemoteViewsFactory {
    private var tasksArray = JSONArray()

    override fun onCreate() {}

    override fun onDataSetChanged() {
        var prefs = context.getSharedPreferences("${context.packageName}_preferences", Context.MODE_PRIVATE)
        var tasksJson = prefs.getString("flutter.daily_tasks_key", null) ?: prefs.getString("daily_tasks_key", null)
        
        if (tasksJson.isNullOrEmpty()) {
            prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            tasksJson = prefs.getString("flutter.daily_tasks_key", null) ?: prefs.getString("daily_tasks_key", null)
        }
        
        tasksArray = if (!tasksJson.isNullOrEmpty()) JSONArray(tasksJson) else JSONArray()
    }

    override fun onDestroy() {}

    override fun getCount(): Int = tasksArray.length()

    override fun getViewAt(position: Int): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.widget_item_row)
        try {
            val task = tasksArray.getJSONObject(position)
            val title = task.optString("title", "Untitled Task")
            val isDone = task.optBoolean("isDone", false)
            val time = task.optString("time", "--:--")

            views.setTextViewText(R.id.row_check_icon, if (isDone) "✓" else "○")
            views.setTextViewText(R.id.row_task_text, "$time  |  $title")
            
            // Create an explicit broadcast fill-in intent to match the provider template
            val fillInIntent = Intent().apply {
                putExtra("task_id", task.optString("id", ""))
            }
            // Bind the click to the entire item card area or icon
            views.setOnClickFillInIntent(R.id.widget_root, fillInIntent)
            views.setOnClickFillInIntent(R.id.row_check_icon, fillInIntent)
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