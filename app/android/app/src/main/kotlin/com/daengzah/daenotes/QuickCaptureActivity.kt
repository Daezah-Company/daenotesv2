package com.daengzah.daenotes

import android.app.Activity
import android.content.ContentValues
import android.database.sqlite.SQLiteDatabase
import android.os.Bundle
import android.view.Gravity
import android.view.View
import android.view.Window
import android.view.WindowManager
import android.widget.EditText
import android.view.inputmethod.InputMethodManager
import android.widget.TextView
import android.widget.Toast
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import java.util.UUID

/** Compact native capture surface so a widget tap never opens the full app. */
class QuickCaptureActivity : Activity() {
    companion object {
        const val EXTRA_KIND = "daenotes.capture.kind"
        private const val KIND_NOTE = "note"
        private const val KIND_TODO = "todo"
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val kind = intent.getStringExtra(EXTRA_KIND)
        if (kind != KIND_NOTE && kind != KIND_TODO) {
            finish()
            return
        }

        window?.requestFeature(Window.FEATURE_NO_TITLE)
        val isNote = kind == KIND_NOTE
        setContentView(R.layout.daenotes_quick_capture)

        val title = findViewById<EditText>(R.id.capture_title)
        val body = findViewById<EditText>(R.id.capture_body)
        val error = findViewById<TextView>(R.id.capture_error)
        val bodyLabel = findViewById<TextView>(R.id.capture_body_label)
        val titleLabel = findViewById<TextView>(R.id.capture_title_label)
        val heading = findViewById<TextView>(R.id.capture_heading)
        val saveButton = findViewById<TextView>(R.id.capture_save)

        heading.setText(if (isNote) R.string.capture_new_note else R.string.capture_new_todo)
        titleLabel.setText(if (isNote) R.string.capture_note_title else R.string.capture_todo_title)
        body.visibility = if (isNote) View.VISIBLE else View.GONE
        bodyLabel.visibility = if (isNote) View.VISIBLE else View.GONE
        findViewById<TextView>(R.id.capture_save).setText(
            if (isNote) R.string.capture_save_note else R.string.capture_save_todo,
        )
        title.hint = getString(
            if (isNote) R.string.capture_note_hint else R.string.capture_todo_hint,
        )

        findViewById<View>(R.id.capture_cancel).setOnClickListener { finish() }
        findViewById<View>(R.id.capture_close).setOnClickListener { finish() }
        saveButton.setOnClickListener {
            error.visibility = View.GONE
            val text = title.text.toString().trim()
            if (text.isEmpty()) {
                error.visibility = View.VISIBLE
                title.requestFocus()
                return@setOnClickListener
            }
            if (save(kind, text, if (isNote) body.text.toString().trim() else "")) {
                DaeNotesOverviewWidgetProvider.refreshAll(this)
                Toast.makeText(
                    this,
                    if (isNote) R.string.capture_note_saved else R.string.capture_todo_saved,
                    Toast.LENGTH_SHORT,
                ).show()
                finish()
            }
        }

        title.setOnEditorActionListener { _, actionId, _ ->
            if (actionId == android.view.inputmethod.EditorInfo.IME_ACTION_NEXT && isNote) {
                body.requestFocus()
                true
            } else {
                false
            }
        }

        window?.apply {
            setBackgroundDrawableResource(android.R.color.transparent)
            setGravity(Gravity.CENTER)
            setDimAmount(0.58f)
            val margin = (32 * resources.displayMetrics.density).toInt()
            val maxWidth = (500 * resources.displayMetrics.density).toInt()
            setLayout(minOf(resources.displayMetrics.widthPixels - margin, maxWidth), WindowManager.LayoutParams.WRAP_CONTENT)
            setSoftInputMode(
                WindowManager.LayoutParams.SOFT_INPUT_STATE_ALWAYS_VISIBLE or
                    WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE,
            )
        }
        title.post {
            title.requestFocus()
            (getSystemService(INPUT_METHOD_SERVICE) as InputMethodManager)
                .showSoftInput(title, InputMethodManager.SHOW_IMPLICIT)
        }
    }

    private fun save(kind: String, title: String, body: String): Boolean {
        val databaseName = getSharedPreferences("daenotes_widget", MODE_PRIVATE)
            .getString("database_name", "")
            ?.takeIf { Regex("daenotes(?:_user_[0-9]+)?").matches(it) }
        if (databaseName == null) {
            Toast.makeText(
                this,
                "Masuk ke DaeNotes untuk memakai widget ini.",
                Toast.LENGTH_LONG,
            ).show()
            return false
        }
        val dbFile = java.io.File(applicationInfo.dataDir, "app_flutter/$databaseName.sqlite")
        if (!dbFile.exists()) {
            Toast.makeText(
                this,
                "Buka DaeNotes sekali untuk menyiapkan penyimpanan widget.",
                Toast.LENGTH_LONG,
            ).show()
            return false
        }

        val table = if (kind == KIND_NOTE) "notes" else "todos"
        val db = try {
            SQLiteDatabase.openDatabase(
                dbFile.absolutePath,
                null,
                SQLiteDatabase.OPEN_READWRITE,
            )
        } catch (_: Exception) {
            Toast.makeText(this, "Penyimpanan DaeNotes sedang sibuk. Coba lagi.", Toast.LENGTH_LONG).show()
            return false
        }

        return try {
            if (!hasTable(db, table) || !hasTable(db, "pending_changes")) {
                Toast.makeText(
                    this,
                    "Buka DaeNotes sekali untuk menyiapkan penyimpanan widget.",
                    Toast.LENGTH_LONG,
                ).show()
                return false
            }

            val uuid = UUID.randomUUID().toString()
            val now = System.currentTimeMillis()
            val updatedAt = SimpleDateFormat(
                "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'",
                Locale.US,
            ).apply { timeZone = TimeZone.getTimeZone("UTC") }.format(Date(now))

            db.beginTransaction()
            try {
                val item = ContentValues().apply {
                    put("uuid", uuid)
                    put("title", title)
                    put("group_name", null as String?)
                    put("updated_at", now)
                    if (kind == KIND_NOTE) {
                        put("body", body)
                        put("color", null as String?)
                        put("pinned", 0)
                    } else {
                        put("notes", null as String?)
                        put("done", 0)
                        put("priority", "normal")
                    }
                }
                check(db.insertOrThrow(table, null, item) != -1L)

                val payload = JSONObject().apply {
                    put("uuid", uuid)
                    put("title", title)
                    put("group_name", JSONObject.NULL)
                    put("updated_at", updatedAt)
                    if (kind == KIND_NOTE) {
                        put("body", body)
                        put("color", JSONObject.NULL)
                        put("pinned", false)
                    } else {
                        put("notes", JSONObject.NULL)
                        put("done", false)
                        put("priority", "normal")
                    }
                }
                val change = ContentValues().apply {
                    put("change_table", table)
                    put("uuid", uuid)
                    put("operation", "upsert")
                    put("payload", payload.toString())
                    put("queued_at", now)
                    put("attempts", 0)
                    put("last_error", null as String?)
                }
                val queued = db.insertWithOnConflict(
                    "pending_changes", null, change, SQLiteDatabase.CONFLICT_REPLACE,
                )
                check(queued != -1L) { "Could not queue the widget capture" }
                db.setTransactionSuccessful()
            } finally {
                db.endTransaction()
            }
            true
        } catch (_: Exception) {
            Toast.makeText(this, "Catatan belum tersimpan. Coba lagi.", Toast.LENGTH_LONG).show()
            false
        } finally {
            db.close()
        }
    }

    private fun hasTable(db: SQLiteDatabase, table: String): Boolean =
        db.rawQuery(
            "SELECT 1 FROM sqlite_master WHERE type='table' AND name=?",
            arrayOf(table),
        ).use { it.moveToFirst() }
}
