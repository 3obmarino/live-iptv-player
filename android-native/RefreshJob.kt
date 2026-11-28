package dk.livetvplayer.live_tv_player

import android.app.job.JobInfo
import android.app.job.JobParameters
import android.app.job.JobScheduler
import android.app.job.JobService
import android.content.ComponentName
import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel

/** Refreshes the channel list and TV guide while the app is closed, about
 *  every hour on any network: runs the app's Dart backgroundMain() in a
 *  headless Flutter engine, which skips the work if the app is open. */
class RefreshJob : JobService() {
    private var engine: FlutterEngine? = null

    override fun onStartJob(params: JobParameters): Boolean {
        Handler(Looper.getMainLooper()).post {
            try {
                val loader = FlutterInjector.instance().flutterLoader()
                loader.startInitialization(applicationContext)
                loader.ensureInitializationComplete(applicationContext, null)
                val e = FlutterEngine(applicationContext)
                engine = e
                MethodChannel(e.dartExecutor.binaryMessenger, "livetv/background")
                    .setMethodCallHandler { call, result ->
                        if (call.method == "done") {
                            result.success(null)
                            finish(params)
                        } else result.notImplemented()
                    }
                e.dartExecutor.executeDartEntrypoint(
                    DartExecutor.DartEntrypoint(loader.findAppBundlePath(), "backgroundMain")
                )
                // safety net
                Handler(Looper.getMainLooper()).postDelayed({ finish(params) }, 9 * 60 * 1000L)
            } catch (e: Exception) {
                jobFinished(params, false)
            }
        }
        return true
    }

    private fun finish(params: JobParameters) {
        val e = engine ?: return
        engine = null
        try {
            e.destroy()
        } catch (_: Exception) {
        }
        jobFinished(params, false)
    }

    override fun onStopJob(params: JobParameters): Boolean {
        engine?.destroy()
        engine = null
        return true
    }

    companion object {
        private const val JOB_ID = 4720

        /** Called on every app start; keeps one periodic job. */
        fun ensureScheduled(context: Context) {
            val js = context.getSystemService(Context.JOB_SCHEDULER_SERVICE) as JobScheduler
            if (js.allPendingJobs.any { it.id == JOB_ID }) return
            val job = JobInfo.Builder(JOB_ID, ComponentName(context, RefreshJob::class.java))
                .setRequiredNetworkType(JobInfo.NETWORK_TYPE_ANY)
                .setPeriodic(60 * 60 * 1000L)
                .setPersisted(true) // survives reboots (RECEIVE_BOOT_COMPLETED)
                .build()
            try {
                js.schedule(job)
            } catch (_: Exception) {
            }
        }
    }
}
