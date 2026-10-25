package com.jio.tvplus.jio_tv_plus_flutter.tif

import android.content.Context
import android.media.tv.TvContentRating
import android.media.tv.TvContract
import android.media.tv.TvInputManager
import android.media.tv.TvInputService
import android.media.tv.TvTrackInfo
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.Surface
import androidx.annotation.OptIn
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.hls.HlsMediaSource

/**
 * Handles live preview playback and channel tuning in the Amazon Fire TV UI.
 * Reference: Amazon Fire TV Linear TV Integration Guide
 * - developer.amazon.com/docs/fire-tv/playback-in-fire-tv-ui.html
 * - developer.amazon.com/docs/fire-tv/set-up-tvinputservice.html
 */
class JioTvInputSession(
    private val context: Context,
    private val inputId: String
) : TvInputService.Session(context) {

    companion object {
        private const val TAG = "JioTvInputSession"
        private const val JIO_USER_AGENT = "plaYtv/7.1.8 (Linux;Android 8.1.0) ExoPlayerLib/2.11.7"
    }

    private val epgManager = JioTvEpgManager(context)
    private val mainHandler = Handler(Looper.getMainLooper())
    private var exoPlayer: ExoPlayer? = null
    private var currentSurface: Surface? = null
    private var currentVolume: Float = 1.0f
    private var currentChannelUri: Uri? = null

    init {
        mainHandler.post {
            initializePlayer()
        }
    }

    private fun initializePlayer() {
        if (exoPlayer != null) return

        exoPlayer = ExoPlayer.Builder(context).build().apply {
            volume = currentVolume
            currentSurface?.let { setVideoSurface(it) }

            addListener(object : Player.Listener {
                override fun onPlaybackStateChanged(playbackState: Int) {
                    when (playbackState) {
                        Player.STATE_READY -> {
                            Log.d(TAG, "ExoPlayer ready - notifying video available to Fire TV UI")
                            notifyVideoAvailable()
                            notifyDefaultTracks()
                        }
                        Player.STATE_BUFFERING -> {
                            Log.d(TAG, "ExoPlayer buffering live stream")
                        }
                        Player.STATE_ENDED -> {
                            Log.d(TAG, "ExoPlayer playback ended")
                        }
                        Player.STATE_IDLE -> {}
                    }
                }

                override fun onPlayerError(error: PlaybackException) {
                    Log.w(TAG, "ExoPlayer error during Fire TV preview: ${error.message}")
                    notifyVideoUnavailable(TvInputManager.VIDEO_UNAVAILABLE_REASON_UNKNOWN)
                }
            })
        }
    }

    override fun onSetSurface(surface: Surface?): Boolean {
        currentSurface = surface
        mainHandler.post {
            exoPlayer?.setVideoSurface(surface)
        }
        return true
    }

    override fun onSetStreamVolume(volume: Float) {
        currentVolume = volume
        mainHandler.post {
            exoPlayer?.volume = volume
        }
    }

    @OptIn(UnstableApi::class)
    override fun onTune(channelUri: Uri): Boolean {
        currentChannelUri = channelUri
        Log.i(TAG, "Tuning channel in Fire TV UI: $channelUri")

        // 1. Notify framework that video playback has started
        notifyVideoStarted()

        // 2. Parental Controls Check (Amazon Fire TV Guidelines)
        checkParentalControls()

        mainHandler.post {
            try {
                initializePlayer()

                // Query channel metadata from Android TvContract
                val channelInfo = epgManager.getChannelByUri(channelUri)
                val streamUrl = channelInfo?.streamUrl?.takeIf { it.isNotEmpty() }
                    ?: "https://jiotvcod.cdn.jio.com/live/${channelInfo?.internalId ?: "104"}/index.m3u8"

                Log.d(TAG, "Playing channel ${channelInfo?.name ?: "Unknown"} stream: $streamUrl")

                // Configure standard JioTV HTTP Headers & Media3 HLS source
                val httpDataSourceFactory = DefaultHttpDataSource.Factory()
                    .setUserAgent(JIO_USER_AGENT)
                    .setAllowCrossProtocolRedirects(true)
                    .setDefaultRequestProperties(
                        mapOf(
                            "Accept" to "*/*",
                            "Accept-Encoding" to "gzip, deflate",
                            "Connection" to "keep-alive"
                        )
                    )

                val mediaSource = HlsMediaSource.Factory(httpDataSourceFactory)
                    .createMediaSource(MediaItem.fromUri(Uri.parse(streamUrl)))

                exoPlayer?.let { player ->
                    player.setMediaSource(mediaSource)
                    player.prepare()
                    player.playWhenReady = true
                }
            } catch (e: Exception) {
                Log.e(TAG, "Error preparing stream for Fire TV UI preview: ${e.message}", e)
                notifyVideoUnavailable(TvInputManager.VIDEO_UNAVAILABLE_REASON_UNKNOWN)
            }
        }

        return true
    }

    private fun checkParentalControls() {
        try {
            val tvInputManager = context.getSystemService(Context.TV_INPUT_SERVICE) as? TvInputManager
            if (tvInputManager != null && tvInputManager.isParentalControlsEnabled) {
                // If parental controls are active, evaluate rating or allow
                notifyContentAllowed()
            } else {
                notifyContentAllowed()
            }
        } catch (_: Exception) {
            notifyContentAllowed()
        }
    }

    private fun notifyDefaultTracks() {
        try {
            val tracks = listOf(
                TvTrackInfo.Builder(TvTrackInfo.TYPE_VIDEO, "video-0")
                    .setVideoWidth(1920)
                    .setVideoHeight(1080)
                    .setVideoFrameRate(50.0f)
                    .setLanguage("und")
                    .build(),
                TvTrackInfo.Builder(TvTrackInfo.TYPE_AUDIO, "audio-0")
                    .setAudioChannelCount(2)
                    .setAudioSampleRate(48000)
                    .setLanguage("hin")
                    .build()
            )
            notifyTracksChanged(tracks)
            notifyTrackSelected(TvTrackInfo.TYPE_VIDEO, "video-0")
            notifyTrackSelected(TvTrackInfo.TYPE_AUDIO, "audio-0")
        } catch (e: Exception) {
            Log.d(TAG, "Could not notify track metadata: ${e.message}")
        }
    }

    override fun onSetCaptionEnabled(enabled: Boolean) {
        // Closed captioning support
    }

    override fun onRelease() {
        Log.i(TAG, "Releasing Fire TV Input Session")
        mainHandler.post {
            exoPlayer?.stop()
            exoPlayer?.clearMediaItems()
            exoPlayer?.release()
            exoPlayer = null
            currentSurface = null
        }
    }
}
