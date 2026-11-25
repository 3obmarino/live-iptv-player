package dk.livetvplayer.live_tv_player

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import java.io.File

/** Opens Live TV when the device has booted, if "Start on boot" is on. */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action ?: return
        if (action != Intent.ACTION_BOOT_COMPLETED &&
            action != "android.intent.action.QUICKBOOT_POWERON" &&
            action != "com.htc.intent.action.QUICKBOOT_POWERON"
        ) return
        // Flag file written by the app (Settings > Start on boot).
        if (!File(context.filesDir, "autostart_on_boot").exists()) return
        val pending = goAsync()
        // Give the launcher and network a few seconds to come up first.
        Handler(Looper.getMainLooper()).postDelayed({
            try {
                context.packageManager.getLaunchIntentForPackage(context.packageName)?.let {
                    it.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED)
                    context.startActivity(it)
                }
            } catch (_: Exception) {
            } finally {
                pending.finish()
            }
        }, 5000)
    }
}
