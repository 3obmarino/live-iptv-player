package dk.livetvplayer.live_tv_player

import android.content.Intent
import android.net.Uri
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
                    else -> result.notImplemented()
                }
            }
    }
}
