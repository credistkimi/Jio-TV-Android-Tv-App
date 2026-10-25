package com.jio.tvplus.jio_tv_plus_flutter.tif

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.media.tv.TvContract
import android.util.Log

/**
 * BroadcastReceiver triggered by Fire TV upon app install or system broadcast:
 * android.media.tv.action.INITIALIZE_PROGRAMS
 *
 * Can also be triggered via ADB during development/testing:
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

        if (action == ACTION_INITIALIZE_PROGRAMS || action == Intent.ACTION_BOOT_COMPLETED) {
            Log.i(TAG, "Initializing Fire TV channels and scheduling periodic EPG sync")
            EpgSyncWorker.enqueueOneTime(context)
            EpgSyncWorker.enqueuePeriodic(context)
        }
    }
}
