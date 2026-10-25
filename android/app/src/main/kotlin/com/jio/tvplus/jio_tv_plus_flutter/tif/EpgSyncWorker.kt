package com.jio.tvplus.jio_tv_plus_flutter.tif

import android.content.Context
import android.util.Log
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import java.util.concurrent.TimeUnit

/**
 * Background WorkManager worker ensuring regular EPG schedule updates for Fire TV Guide.
 */
class EpgSyncWorker(
    appContext: Context,
    workerParams: WorkerParameters
) : CoroutineWorker(appContext, workerParams) {

    companion object {
        private const val TAG = "EpgSyncWorker"
        private const val WORK_NAME_ONE_TIME = "jio_epg_sync_one_time"
        private const val WORK_NAME_PERIODIC = "jio_epg_sync_periodic"

        fun enqueueOneTime(context: Context) {
            val request = OneTimeWorkRequestBuilder<EpgSyncWorker>().build()
            WorkManager.getInstance(context).enqueueUniqueWork(
                WORK_NAME_ONE_TIME,
                ExistingWorkPolicy.REPLACE,
                request
            )
        }

        fun enqueuePeriodic(context: Context) {
            val request = PeriodicWorkRequestBuilder<EpgSyncWorker>(12, TimeUnit.HOURS).build()
            WorkManager.getInstance(context).enqueueUniquePeriodicWork(
                WORK_NAME_PERIODIC,
                ExistingPeriodicWorkPolicy.KEEP,
                request
            )
        }
    }

    override suspend fun doWork(): Result {
        Log.i(TAG, "Starting background Fire TV EPG Sync Work...")
        return try {
            val epgManager = JioTvEpgManager(applicationContext)
            val count = epgManager.syncChannels()
            Log.i(TAG, "Background Fire TV EPG Sync completed ($count channels)")
            Result.success()
        } catch (e: Exception) {
            Log.e(TAG, "Background Fire TV EPG Sync failed: ${e.message}", e)
            Result.retry()
        }
    }
}
