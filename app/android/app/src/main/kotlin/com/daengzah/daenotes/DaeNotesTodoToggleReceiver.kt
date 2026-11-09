package com.daengzah.daenotes

import android.content.BroadcastReceiver
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.database.sqlite.SQLiteDatabase
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

/** Completes an open todo from the glance widget and queues it for sync. */
class DaeNotesTodoToggleReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ACTION_COMPLETE) return
        val uuid = intent.getStringExtra(EXTRA_UUID)?.takeIf { it.isNotBlank() } ?: return
        val databaseName = context.getSharedPreferences("daenotes_widget", Context.MODE_PRIVATE)
            .getString("database_name", "")
            ?.takeIf { Regex("daenotes(?:_user_[0-9]+)?").matches(it) }
            ?: return
        val file = java.io.File(context.applicationInfo.dataDir, "app_flutter/$databaseName.sqlite")
        if (!file.exists()) return

        runCatching {
            SQLiteDatabase.openDatabase(file.absolutePath, null, SQLiteDatabase.OPEN_READWRITE)
        }.getOrNull()?.use { db -> complete(db, uuid) }
        DaeNotesOverviewWidgetProvider.refreshAll(context)
    }

    private fun complete(db: SQLiteDatabase, uuid: String) {
        val row = db.rawQuery(
            "SELECT title, notes, group_name, done, done_at, priority, due_at, remind_at, archived_at, can_edit " +
                "FROM todos WHERE uuid = ? AND deleted_at IS NULL LIMIT 1",
            arrayOf(uuid),
        ).use { cursor ->
            if (!cursor.moveToFirst()) return
            if (cursor.getInt(3) != 0 || cursor.getInt(9) == 0) return
            TodoRow(
                title = cursor.getString(0).orEmpty(),
                notes = cursor.nullableString(1),
                groupName = cursor.nullableString(2),
                doneAt = cursor.nullableLong(4),
                priority = cursor.getString(5) ?: "normal",
                dueAt = cursor.nullableLong(6),
                remindAt = cursor.nullableLong(7),
                archivedAt = cursor.nullableLong(8),
            )
        }
        val now = System.currentTimeMillis()
        val iso = isoDate(now)
        db.beginTransaction()
        try {
            val values = ContentValues().apply {
                put("done", 1)
                put("done_at", now)
                put("updated_at", now)
            }
            val updatedRows = db.update(
                "todos",
                values,
                "uuid = ? AND done = 0 AND can_edit != 0",
                arrayOf(uuid),
            )
            if (updatedRows == 0) {
                return
            }
            val payload = JSONObject().apply {
                put("uuid", uuid)
                put("title", row.title)
                putNullable("notes", row.notes)
                putNullable("group_name", row.groupName)
                put("done", true)
                put("done_at", iso)
                put("priority", row.priority)
                putNullable("due_at", row.dueAt?.let(::isoDate))
                putNullable("remind_at", row.remindAt?.let(::isoDate))
                putNullable("archived_at", row.archivedAt?.let(::isoDate))
                put("updated_at", iso)
            }
            val change = ContentValues().apply {
                put("change_table", "todos")
                put("uuid", uuid)
                put("operation", "upsert")
                put("payload", payload.toString())
                put("queued_at", now)
                put("attempts", 0)
                putNull("last_error")
            }
            db.insertWithOnConflict(
                "pending_changes",
                null,
                change,
                SQLiteDatabase.CONFLICT_REPLACE,
            )
            db.setTransactionSuccessful()
        } finally {
            db.endTransaction()
        }
    }

    private fun isoDate(epochMs: Long): String = SimpleDateFormat(
        "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'",
        Locale.US,
    ).apply { timeZone = TimeZone.getTimeZone("UTC") }.format(Date(epochMs))

    private fun JSONObject.putNullable(name: String, value: String?) {
        put(name, value ?: JSONObject.NULL)
    }

    private fun android.database.Cursor.nullableString(index: Int): String? =
        if (isNull(index)) null else getString(index)

    private fun android.database.Cursor.nullableLong(index: Int): Long? =
        if (isNull(index)) null else getLong(index)

    private data class TodoRow(
        val title: String,
        val notes: String?,
        val groupName: String?,
        val doneAt: Long?,
        val priority: String,
        val dueAt: Long?,
        val remindAt: Long?,
        val archivedAt: Long?,
    )

    companion object {
        const val ACTION_COMPLETE = "com.daengzah.daenotes.action.COMPLETE_TODO"
        const val EXTRA_UUID = "daenotes.todo.uuid"
    }
}
