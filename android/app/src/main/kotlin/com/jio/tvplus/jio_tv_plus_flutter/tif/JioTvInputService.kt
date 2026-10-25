package com.jio.tvplus.jio_tv_plus_flutter.tif

import android.media.tv.TvInputService
import android.util.Log

/**
 * TV Input Service integrating JioTV+ channels into Amazon Fire TV Live TV framework.
 * Reference: Amazon Fire TV Linear TV Integration Guide
 * - developer.amazon.com/docs/fire-tv/set-up-tvinputservice.html
 * - developer.amazon.com/docs/fire-tv/tv-input-framework-on-fire-tv.html
 */
class JioTvInputService : TvInputService() {

    companion object {
        private const val TAG = "JioTvInputService"
    }

    override fun onCreateSession(inputId: String): Session? {
        Log.i(TAG, "Creating new TvInputSession for inputId: $inputId")
        return JioTvInputSession(this, inputId).apply {
            setOverlayViewEnabled(false)
        }
    }
}
