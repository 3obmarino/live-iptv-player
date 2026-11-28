package dk.livetvplayer.live_tv_player

import android.app.AlertDialog
import android.content.ContentValues
import android.text.InputType
import android.view.WindowManager
import android.view.inputmethod.EditorInfo
import android.widget.EditText
import android.widget.FrameLayout
import android.content.Intent
import android.net.Uri
import android.os.Environment
import android.provider.MediaStore
import android.speech.RecognizerIntent
import java.io.File
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var voiceResult: MethodChannel.Result? = null
    private val voiceRequest = 4711
    private var pickResult: MethodChannel.Result? = null
    private val pickRequest = 4712
    private var openedFile: String? = null // backup opened from a file manager

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        takeViewIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        takeViewIntent(intent)
    }

    private fun takeViewIntent(i: Intent?) {
        if (i?.action == Intent.ACTION_VIEW && i.data != null) {
            openedFile = readText(i.data!!)
        }
    }

    private fun readText(uri: Uri): String? = try {
        contentResolver.openInputStream(uri)?.use { s ->
            // backups are small; refuse anything big
            val bytes = s.readBytes()
            if (bytes.size > 5_000_000) null else String(bytes)
        }
    } catch (e: Exception) {
        null
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == pickRequest) {
            val uri = data?.data
            pickResult?.success(if (resultCode == RESULT_OK && uri != null) readText(uri) else null)
            pickResult = null
            return
        }
        if (requestCode == voiceRequest) {
            val text = data?.getStringArrayListExtra(RecognizerIntent.EXTRA_RESULTS)?.firstOrNull()
            voiceResult?.success(if (resultCode == RESULT_OK) text else null)
            voiceResult = null
            return
        }
        super.onActivityResult(requestCode, resultCode, data)
    }

    private fun voiceIntent(language: String?, prompt: String?) =
        Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
            if (!language.isNullOrEmpty()) putExtra(RecognizerIntent.EXTRA_LANGUAGE, language)
            if (!prompt.isNullOrEmpty()) putExtra(RecognizerIntent.EXTRA_PROMPT, prompt)
        }

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
                        result.success(saveToDownloads(name, text, call.argument<String>("mime") ?: "text/plain"))
                    }
                    // TV text entry in a plain Android dialog: the TV keyboard and
                    // remote work with it like in any native TV app (Flutter sees
                    // remote keys before the keyboard, so they never reached it).
                    "editText" -> editText(
                        call.argument<String>("label") ?: "",
                        call.argument<String>("text") ?: "",
                        call.argument<String>("kind") ?: "text",
                        result
                    )
                    // Voice search with the device's speech recognizer (Google on
                    // phones and Google TV). Returns the text, or null.
                    "voiceAvailable" -> result.success(
                        voiceIntent(null, null).resolveActivity(packageManager) != null
                    )
                    "voiceSearch" -> {
                        val intent = voiceIntent(call.argument<String>("language"), call.argument<String>("prompt"))
                        if (intent.resolveActivity(packageManager) == null) {
                            result.success(null)
                        } else {
                            voiceResult?.success(null)
                            voiceResult = result
                            try {
                                @Suppress("DEPRECATION")
                                startActivityForResult(intent, voiceRequest)
                            } catch (e: Exception) {
                                voiceResult = null
                                result.success(null)
                            }
                        }
                    }
                    // Backup files: the app's own ones in Download, a picked file,
                    // or one opened with "Open with LiveTV Player".
                    "listBackups" -> result.success(listBackups(call.argument<String>("prefix") ?: ""))
                    "readUri" -> result.success(
                        call.argument<String>("uri")?.let { readText(Uri.parse(it)) }
                    )
                    "pickFile" -> {
                        val i = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                            addCategory(Intent.CATEGORY_OPENABLE)
                            type = "*/*"
                            putExtra(Intent.EXTRA_MIME_TYPES, arrayOf("application/json", "text/plain", "application/octet-stream"))
                        }
                        if (i.resolveActivity(packageManager) == null) {
                            result.success("") // no picker on this device
                        } else {
                            pickResult?.success(null)
                            pickResult = result
                            try {
                                @Suppress("DEPRECATION")
                                startActivityForResult(i, pickRequest)
                            } catch (e: Exception) {
                                pickResult = null
                                result.success("")
                            }
                        }
                    }
                    "takeOpenedFile" -> {
                        result.success(openedFile)
                        openedFile = null
                    }
                    // Programme reminders: an alarm brings the app to the front.
                    "scheduleReminder" -> {
                        ReminderReceiver.schedule(
                            this,
                            call.argument<Int>("id") ?: 0,
                            (call.argument<Number>("at") ?: 0).toLong()
                        )
                        result.success(null)
                    }
                    "cancelReminder" -> {
                        ReminderReceiver.cancel(this, call.argument<Int>("id") ?: 0)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun saveToDownloads(name: String, text: String, mime: String = "text/plain"): String? = try {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val values = ContentValues().apply {
                put(MediaStore.Downloads.DISPLAY_NAME, name)
                put(MediaStore.Downloads.MIME_TYPE, mime)
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

    private fun editText(label: String, text: String, kind: String, result: MethodChannel.Result) {
        var answered = false
        fun answer(v: String?) {
            if (!answered) {
                answered = true
                result.success(v)
            }
        }
        val input = EditText(this).apply {
            setText(text)
            setSelection(text.length)
            isSingleLine = true
            imeOptions = EditorInfo.IME_ACTION_DONE or EditorInfo.IME_FLAG_NO_EXTRACT_UI
            inputType = when (kind) {
                "password" -> InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_VISIBLE_PASSWORD
                "url" -> InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_URI
                else -> InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS
            }
        }
        val pad = (24 * resources.displayMetrics.density).toInt()
        val box = FrameLayout(this).apply {
            setPadding(pad, pad / 2, pad, 0)
            addView(input)
        }
        val dlg = AlertDialog.Builder(this, android.R.style.Theme_DeviceDefault_Dialog_Alert)
            .setTitle(label)
            .setView(box)
            .setPositiveButton(android.R.string.ok) { _, _ -> answer(input.text.toString()) }
            .setNegativeButton(android.R.string.cancel) { _, _ -> answer(null) }
            .setOnCancelListener { answer(null) }
            .setOnDismissListener { answer(null) }
            .create()
        input.setOnEditorActionListener { _, actionId, _ ->
            if (actionId == EditorInfo.IME_ACTION_DONE) {
                answer(input.text.toString())
                dlg.dismiss()
                true
            } else false
        }
        dlg.window?.setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_STATE_ALWAYS_VISIBLE)
        dlg.show()
        input.requestFocus()
    }

    private fun listBackups(prefix: String): List<Map<String, String>> {
        val out = mutableListOf<Map<String, String>>()
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            @Suppress("DEPRECATION")
            val dir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
            dir.listFiles()?.filter { it.name.startsWith(prefix) }?.forEach {
                out.add(mapOf("name" to it.name, "uri" to Uri.fromFile(it).toString()))
            }
            return out
        }
        try {
            val col = MediaStore.Downloads.EXTERNAL_CONTENT_URI
            contentResolver.query(
                col,
                arrayOf(MediaStore.Downloads._ID, MediaStore.Downloads.DISPLAY_NAME),
                "${MediaStore.Downloads.DISPLAY_NAME} LIKE ?",
                arrayOf("$prefix%"),
                "${MediaStore.Downloads.DATE_ADDED} DESC"
            )?.use { c ->
                while (c.moveToNext()) {
                    val uri = android.content.ContentUris.withAppendedId(col, c.getLong(0))
                    out.add(mapOf("name" to c.getString(1), "uri" to uri.toString()))
                }
            }
        } catch (e: Exception) {
        }
        return out
    }
}
