package com.example.cheq

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.widget.RemoteViews
import android.widget.RemoteViewsService
import org.json.JSONArray

/** Intent action stamped onto the fill-in intent of an interactive checkbox. */
const val ACTION_MARK_DONE = "MARK_DONE"
const val WIDGET_BACKGROUND_SCHEME = "cheqwidget"
const val WIDGET_BACKGROUND_HOST = "mark_done"
const val TODO_WIDGET_DATA_KEY = "widget_data_todo"

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
    private var userUid = ""
    private val PREFS_NAME = "HomeWidgetPreferences"

    override fun onCreate() { loadData() }
    override fun onDataSetChanged() { loadData() }
    override fun onDestroy() { tasksArray = JSONArray() }

    private fun loadData() {
        tasksArray = JSONArray() // Clear old cache
        try {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            // Cached by Dart (FirestoreService._pushAllWidgetData) so the native
            // widget can build a mark_done intent without FirebaseAuth state.
            userUid = prefs.getString("widget_user_uid", "") ?: ""
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
        val taskId = task.optString("id", "")
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

        if (widgetDataKey != TODO_WIDGET_DATA_KEY && taskId.isNotEmpty() && userUid.isNotEmpty()) {
            // Today + Planner widgets: the checkbox fires the Dart background
            // completion engine. The URI (merged into the template broadcast)
            // carries the exact task id + uid, so coins/stats are credited
            // exactly like the in-app checkbox.
            val markDoneUri = Uri.Builder()
                .scheme(WIDGET_BACKGROUND_SCHEME)
                .authority(WIDGET_BACKGROUND_HOST)
                .appendQueryParameter("taskId", taskId)
                .appendQueryParameter("uid", userUid)
                .build()
            val markDoneIntent = Intent().apply {
                action = ACTION_MARK_DONE
                data = markDoneUri
                putExtra("taskId", taskId)
                putExtra("uid", userUid)
            }
            views.setOnClickFillInIntent(R.id.row_check_icon, markDoneIntent)
        } else {
            // To-Do widget: todo items are not planner tasks, so it keeps the
            // existing local toggle (synced by syncWidgetChangesToFirestore).
            val checkboxToggleIntent = Intent().apply {
                putExtra("action", "TOGGLE_DONE")
                putExtra("task_position", position)
            }
            views.setOnClickFillInIntent(R.id.row_check_icon, checkboxToggleIntent)
        }

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
