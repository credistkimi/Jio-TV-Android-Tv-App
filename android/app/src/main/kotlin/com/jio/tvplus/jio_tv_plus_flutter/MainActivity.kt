package com.jio.tvplus.jio_tv_plus_flutter

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.util.Log
import com.jio.tvplus.jio_tv_plus_flutter.tif.EpgSyncWorker
import com.jio.tvplus.jio_tv_plus_flutter.tif.JioTvEpgManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class MainActivity : FlutterActivity() {

    companion object {
        private const val TAG = "MainActivity"
        private const val CHANNEL_FIRE_TV_EPG = "com.jio.tvplus/fire_tv_epg"
    }

    private var methodChannel: MethodChannel? = null
    private var pendingChannelId: String? = null
    private val activityScope = CoroutineScope(Dispatchers.Main + Job())
    private lateinit var epgManager: JioTvEpgManager

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        epgManager = JioTvEpgManager(applicationContext)

        // Pre-populate Fire TV Guide database immediately on app startup
        activityScope.launch(Dispatchers.IO) {
            try {
                epgManager.syncChannels()
            } catch (e: Exception) {
                Log.w(TAG, "Initial Fire TV channel sync on app startup: ${e.message}")
            }
        }

        // Schedule background EPG syncing
        EpgSyncWorker.enqueuePeriodic(applicationContext)

        // Handle initial launch intent from Fire TV Channel Guide
        handleIntent(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_FIRE_TV_EPG).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "getInitialChannelId" -> {
                        val chId = pendingChannelId
                        pendingChannelId = null
                        result.success(chId)
                    }
                    "syncChannels" -> {
                        val channelsJson = call.argument<String>("channelsJson")
                        activityScope.launch {
                            val count = epgManager.syncChannels(channelsJson)
                            result.success(count)
                        }
                    }
                    "syncDefaultPrograms" -> {
                        activityScope.launch {
                            epgManager.syncDefaultProgramsForAllChannels()
                            result.success(true)
                        }
                    }
                    "getSyncStatus" -> {
                        val status = epgManager.getSyncStatus()
                        result.success(status)
                    }
                    "triggerSystemSync" -> {
                        EpgSyncWorker.enqueueOneTime(applicationContext)
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
        }

        // If there was a pending channel from an intent prior to engine attachment
        pendingChannelId?.let { chId ->
            methodChannel?.invokeMethod("onChannelSelectedFromFireTv", chId)
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIntent(intent)
    }

    private fun handleIntent(intent: Intent?) {
        if (intent == null) return
        val action = intent.action
        val data: Uri? = intent.data

        Log.i(TAG, "Handling Intent: action=$action, data=$data")

        if (Intent.ACTION_VIEW == action && data != null) {
            val scheme = data.scheme
            val host = data.host

            var channelIdToOpen: String? = null

            // 1. App deep link format: jiotv://channel/{channelId}
            if ("jiotv" == scheme && "channel" == host) {
                channelIdToOpen = data.lastPathSegment
            }
            // 2. Android TvContract channel URI: content://android.media.tv/channel/{id}
            else if ("content" == scheme && data.authority == "android.media.tv") {
                val pathSegments = data.pathSegments
                if (pathSegments.isNotEmpty() && pathSegments[0] == "channel") {
                    val info = epgManager.getChannelByUri(data)
                    channelIdToOpen = info?.internalId ?: data.lastPathSegment
                }
            }

            if (!channelIdToOpen.isNullOrEmpty()) {
                Log.i(TAG, "Tuning channel requested by Fire TV Guide: $channelIdToOpen")
                pendingChannelId = channelIdToOpen
                methodChannel?.invokeMethod("onChannelSelectedFromFireTv", channelIdToOpen)
            }
        }
    }
}
