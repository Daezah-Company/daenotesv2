package com.daengzah.daenotes

import android.content.Intent
import android.provider.Settings
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "daenotes/settings")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "openNotificationSettings" -> {
                        val intent = Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                            .putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                            .putExtra(Settings.EXTRA_CHANNEL_ID, "daenotes_pengingat")
                        startActivity(intent)
                        result.success(null)
                    }
                    "setWidgetDatabase" -> {
                        val requested = call.argument<String>("name") ?: ""
                        val safeName = if (Regex("daenotes(?:_user_[0-9]+)?").matches(requested)) requested else ""
                        getSharedPreferences("daenotes_widget", MODE_PRIVATE)
                            .edit()
                            .putString("database_name", safeName)
                            .apply()
                        DaeNotesOverviewWidgetProvider.refreshAll(this)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onStop() {
        DaeNotesOverviewWidgetProvider.refreshAll(this)
        super.onStop()
    }
}
