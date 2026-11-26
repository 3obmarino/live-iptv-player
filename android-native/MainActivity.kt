package dk.livetvplayer.live_tv_player

import android.content.ContentValues
import android.content.Intent
import android.net.Uri
import android.os.Environment
import android.provider.MediaStore
import java.io.File
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "livetv/boot")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    // Android 10+ only lets an app start itself after boot when
                    // it may "display over other apps".
                    "canStartFromBackground" -> result.success(
                        Build.VERSION.SDK_INT < Build.VERSION_CODES.Q ||
                            Settings.canDrawOverlays(this)
                    )
                    "openPermissionSettings" -> {
                        val ok = try {
                            startActivity(
                                Intent(
                                    Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                                    Uri.parse("package:$packageName")
                                )
                            )
                            true
                        } catch (e: Exception) {
                            try {
                                startActivity(
                                    Intent(
                                        Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                                        Uri.parse("package:$packageName")
                                    )
                                )
                                true
                            } catch (e2: Exception) {
                                false
                            }
                        }
                        result.success(ok)
                    }
                    // Player log: hand it to another app (mail, Telegram, Drive …)
                    "shareText" -> {
                        val send = Intent(Intent.ACTION_SEND).apply {
                            type = "text/plain"
                            putExtra(Intent.EXTRA_SUBJECT, call.argument<String>("subject") ?: "")
                            putExtra(Intent.EXTRA_TEXT, call.argument<String>("text") ?: "")
                        }
                        val ok = send.resolveActivity(packageManager) != null && try {
                            startActivity(Intent.createChooser(send, call.argument<String>("subject")))
                            true
                        } catch (e: Exception) {
                            false
                        }
                        result.success(ok)
                    }
                    // Player log: save a copy in the public Download folder (TV boxes,
                    // signage screens). Returns the path, or null.
                    "saveToDownloads" -> {
                        val name = call.argument<String>("name") ?: "LiveTV-Player-log.txt"
                        val text = call.argument<String>("text") ?: ""
                        result.success(saveToDownloads(name, text))
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun saveToDownloads(name: String, text: String): String? = try {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val values = ContentValues().apply {
                put(MediaStore.Downloads.DISPLAY_NAME, name)
                put(MediaStore.Downloads.MIME_TYPE, "text/plain")
                put(MediaStore.Downloads.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS)
            }
            val uri = contentResolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
            if (uri == null) null else {
                contentResolver.openOutputStream(uri)?.use { it.write(text.toByteArray()) }
                Environment.DIRECTORY_DOWNLOADS + "/" + name
            }
        } else {
            @Suppress("DEPRECATION")
            val dir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
            dir.mkdirs()
            File(dir, name).writeText(text)
            File(dir, name).absolutePath
        }
    } catch (e: Exception) {
        null
    }
}
