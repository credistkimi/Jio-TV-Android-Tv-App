package com.jio.tvplus.jio_tv_plus_flutter.tif

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

/**
 * BroadcastReceiver triggered by Fire TV upon app install, reboot, or update:
 * - android.media.tv.action.INITIALIZE_PROGRAMS
 * - android.intent.action.BOOT_COMPLETED
 * - android.intent.action.MY_PACKAGE_REPLACED
 *
 * Can also be triggered manually via ADB during testing:
 * adb shell am broadcast -a android.media.tv.action.INITIALIZE_PROGRAMS -n com.jio.tvplus.jio_tv_plus_flutter/.tif.JioTvInitializeReceiver
 */
class JioTvInitializeReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "JioTvInitReceiver"
        const val ACTION_INITIALIZE_PROGRAMS = "android.media.tv.action.INITIALIZE_PROGRAMS"
    }

    override fun onReceive(context: Context, intent: Intent?) {
        val action = intent?.action
        Log.i(TAG, "Received broadcast action: $action")

        if (action == ACTION_INITIALIZE_PROGRAMS ||
            action == Intent.ACTION_BOOT_COMPLETED ||
            action == Intent.ACTION_MY_PACKAGE_REPLACED) {

            val pendingResult = goAsync()
            val appContext = context.applicationContext

            CoroutineScope(Dispatchers.IO).launch {
                try {
                    Log.i(TAG, "Executing immediate channel sync from broadcast...")
                    val epgManager = JioTvEpgManager(appContext)
                    val count = epgManager.syncChannels()
                    Log.i(TAG, "Broadcast channel sync complete ($count channels). Scheduling periodic background worker.")
                    EpgSyncWorker.enqueuePeriodic(appContext)
                } catch (e: Exception) {
                    Log.e(TAG, "Error in broadcast channel sync: ${e.message}", e)
                } finally {
                    pendingResult.finish()
                }
            }
        }
    }
}
