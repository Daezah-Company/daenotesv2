package com.daengzah.daenotes

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.database.sqlite.SQLiteDatabase
import android.net.Uri
import android.widget.RemoteViews
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/** Compact glanceable view of the most recently edited note and next open tasks. */
class DaeNotesOverviewWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        manager: AppWidgetManager,
        widgetIds: IntArray,
    ) {
        widgetIds.forEach { widgetId -> render(context, manager, widgetId) }
    }

    companion object {
        private val rowIds = intArrayOf(
            R.id.overview_todo_row_1,
            R.id.overview_todo_row_2,
            R.id.overview_todo_row_3,
        )
        private val checkIds = intArrayOf(
            R.id.overview_todo_check_1,
            R.id.overview_todo_check_2,
            R.id.overview_todo_check_3,
        )
        private val titleIds = intArrayOf(
            R.id.overview_todo_title_1,
            R.id.overview_todo_title_2,
            R.id.overview_todo_title_3,
        )
        private val dueIds = intArrayOf(
            R.id.overview_todo_due_1,
            R.id.overview_todo_due_2,
            R.id.overview_todo_due_3,
        )

        fun refreshAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val component = ComponentName(context, DaeNotesOverviewWidgetProvider::class.java)
            val ids = manager.getAppWidgetIds(component)
            if (ids.isNotEmpty()) DaeNotesOverviewWidgetProvider().onUpdate(context, manager, ids)
        }

        private fun render(context: Context, manager: AppWidgetManager, widgetId: Int) {
            val views = RemoteViews(context.packageName, R.layout.daenotes_overview_widget)
            val databaseName = context.getSharedPreferences("daenotes_widget", Context.MODE_PRIVATE)
                .getString("database_name", "")
                ?.takeIf { Regex("daenotes(?:_user_[0-9]+)?").matches(it) }
            val file = databaseName?.let {
                java.io.File(context.applicationInfo.dataDir, "app_flutter/$it.sqlite")
            }
            val db = if (file?.exists() == true) {
                runCatching {
                    SQLiteDatabase.openDatabase(
                        file.absolutePath,
                        null,
                        SQLiteDatabase.OPEN_READONLY,
                    )
                }.getOrNull()
            } else null

            val note = db?.let { readNote(it) }
            val todos = db?.let { readTodos(it) }.orEmpty()
            db?.close()

            views.setViewVisibility(
                R.id.overview_todo_empty,
                if (todos.isEmpty()) android.view.View.VISIBLE else android.view.View.GONE,
            )

            views.setTextViewText(
                R.id.overview_note_title,
                when {
                    databaseName == null -> context.getString(R.string.daenotes_overview_sign_in)
                    note == null -> context.getString(R.string.daenotes_overview_empty_note)
                    else -> note.title.ifBlank { context.getString(R.string.daenotes_overview_empty_note) }
                },
            )
            views.setTextViewText(R.id.overview_note_body, note?.body.orEmpty().replace('\n', ' '))
            if (note != null) {
                views.setOnClickPendingIntent(
                    R.id.overview_note_row,
                    openItem(context, "note", note.uuid),
                )
            } else {
                views.setOnClickPendingIntent(
                    R.id.overview_note_row,
                    openApp(context, widgetId),
                )
            }

            rowIds.indices.forEach { index ->
                val todo = todos.getOrNull(index)
                if (todo == null) {
                    views.setViewVisibility(rowIds[index], android.view.View.GONE)
                    return@forEach
                }
                views.setViewVisibility(rowIds[index], android.view.View.VISIBLE)
                views.setTextViewText(titleIds[index], todo.title.ifBlank { "Tanpa judul" })
                views.setTextViewText(dueIds[index], dueLabel(context, todo.dueAt))
                views.setImageViewResource(
                    checkIds[index],
                    if (todo.done) R.drawable.daenotes_widget_check_done
                    else R.drawable.daenotes_widget_check_outline,
                )
                views.setOnClickPendingIntent(
                    rowIds[index],
                    openItem(context, "todo", todo.uuid),
                )
                if (todo.canEdit) {
                    views.setOnClickPendingIntent(
                        checkIds[index],
                        completeTodo(context, todo.uuid),
                    )
                }
            }
            manager.updateAppWidget(widgetId, views)
        }

        private fun readNote(db: SQLiteDatabase): NoteRow? = runCatching {
            db.rawQuery(
                "SELECT uuid, title, body FROM notes " +
                    "WHERE archived_at IS NULL AND deleted_at IS NULL " +
                    "ORDER BY pinned DESC, updated_at DESC LIMIT 1",
                null,
            ).use { cursor ->
                if (!cursor.moveToFirst()) null else NoteRow(
                    uuid = cursor.getString(0),
                    title = cursor.getString(1).orEmpty(),
                    body = cursor.getString(2).orEmpty(),
                )
            }
        }.getOrNull()

        private fun readTodos(db: SQLiteDatabase): List<TodoRow> = runCatching {
            db.rawQuery(
                "SELECT uuid, title, due_at, done, can_edit FROM todos " +
                    "WHERE archived_at IS NULL AND deleted_at IS NULL AND done = 0 " +
                    "ORDER BY CASE WHEN due_at IS NULL THEN 1 ELSE 0 END, due_at ASC, updated_at DESC LIMIT 3",
                null,
            ).use { cursor ->
                buildList {
                    while (cursor.moveToNext()) {
                        add(
                            TodoRow(
                                uuid = cursor.getString(0),
                                title = cursor.getString(1).orEmpty(),
                                dueAt = if (cursor.isNull(2)) null else cursor.getLong(2),
                                done = cursor.getInt(3) != 0,
                                canEdit = cursor.getInt(4) != 0,
                            ),
                        )
                    }
                }
            }
        }.getOrDefault(emptyList())

        private fun dueLabel(context: Context, dueAt: Long?): String {
            if (dueAt == null) return context.getString(R.string.daenotes_overview_no_due)
            val dueDate = Date(dueAt)
            val now = System.currentTimeMillis()
            if (dueAt < now) return context.getString(R.string.daenotes_overview_overdue)
            val today = SimpleDateFormat("yyyyMMdd", Locale.US).format(Date(now))
            val dueDay = SimpleDateFormat("yyyyMMdd", Locale.US).format(dueDate)
            if (dueDay == today) return context.getString(R.string.daenotes_overview_today)
            return SimpleDateFormat("d MMM", Locale("id", "ID")).format(dueDate)
        }

        private fun openItem(context: Context, type: String, uuid: String): PendingIntent {
            val route = if (type == "note") "/note/$uuid" else "/todo/$uuid"
            val intent = Intent(
                Intent.ACTION_VIEW,
                Uri.parse("daenotes://$route"),
                context,
                MainActivity::class.java,
            ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            return PendingIntent.getActivity(
                context,
                uuid.hashCode(),
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }

        private fun completeTodo(context: Context, uuid: String): PendingIntent {
            val intent = Intent(context, DaeNotesTodoToggleReceiver::class.java).apply {
                action = DaeNotesTodoToggleReceiver.ACTION_COMPLETE
                data = Uri.parse("daenotes-widget://complete/$uuid")
                putExtra(DaeNotesTodoToggleReceiver.EXTRA_UUID, uuid)
            }
            return PendingIntent.getBroadcast(
                context,
                uuid.hashCode(),
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }

        private fun openApp(context: Context, widgetId: Int): PendingIntent {
            val intent = Intent(context, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            return PendingIntent.getActivity(
                context,
                widgetId + 5000,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }
    }

    private data class NoteRow(val uuid: String, val title: String, val body: String)
    private data class TodoRow(
        val uuid: String,
        val title: String,
        val dueAt: Long?,
        val done: Boolean,
        val canEdit: Boolean,
    )
}
