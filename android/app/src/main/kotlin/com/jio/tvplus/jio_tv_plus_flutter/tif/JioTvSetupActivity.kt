package com.jio.tvplus.jio_tv_plus_flutter.tif

import android.app.Activity
import android.graphics.Color
import android.graphics.Typeface
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.Gravity
import android.view.View
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.TextView
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * Setup Activity launched when Fire TV user initiates "Sync Sources" under Settings > Live TV.
 * Matches Amazon reference implementation (RichTvInputSetupActivity).
 * Reference:
 * - developer.amazon.com/docs/fire-tv/set-up-tvinputservice.html
 * - developer.amazon.com/docs/fire-tv/insert-your-first-channel.html
 */
class JioTvSetupActivity : Activity() {

    companion object {
        private const val TAG = "JioTvSetupActivity"
        private const val AUTO_EXIT_DELAY_MS = 2500L
    }

    private val activityScope = CoroutineScope(Dispatchers.Main + Job())
    private val exitHandler = Handler(Looper.getMainLooper())

    private lateinit var titleTextView: TextView
    private lateinit var messageTextView: TextView
    private lateinit var progressBar: ProgressBar

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Leanback 10-foot TV dark UI (No AppCompat dependency)
        val rootLayout = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setBackgroundColor(Color.parseColor("#0A0E1A"))
            setPadding(80, 60, 80, 60)
        }

        titleTextView = TextView(this).apply {
            text = "Updating Channel Info"
            textSize = 28f
            setTextColor(Color.WHITE)
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
            setPadding(0, 0, 0, 16)
        }
        rootLayout.addView(titleTextView)

        messageTextView = TextView(this).apply {
            text = "This may take a few minutes, please do not leave this screen"
            textSize = 18f
            setTextColor(Color.parseColor("#9CA3AF"))
            gravity = Gravity.CENTER
            setPadding(0, 0, 0, 32)
        }
        rootLayout.addView(messageTextView)

        progressBar = ProgressBar(this).apply {
            layoutParams = LinearLayout.LayoutParams(400, 24).apply {
                gravity = Gravity.CENTER
                bottomMargin = 24
            }
        }
        rootLayout.addView(progressBar)

        setContentView(rootLayout)

        startSync()
    }

    private fun startSync() {
        activityScope.launch {
            try {
                val epgManager = JioTvEpgManager(applicationContext)
                val count = withContext(Dispatchers.IO) {
                    epgManager.syncChannels()
                }

                if (count > 0) {
                    showSuccess(count)
                } else {
                    showSuccess(0)
                }
            } catch (e: Exception) {
                Log.e(TAG, "Channel sync failed", e)
                showFailure()
            }
        }
    }

    private fun showSuccess(count: Int) {
        progressBar.visibility = View.GONE
        titleTextView.text = "Channel Sync Complete"
        messageTextView.text = if (count > 0) {
            "Successfully synced $count channels to Fire TV Guide. Exiting shortly..."
        } else {
            "Channels are up to date. Exiting shortly..."
        }
        messageTextView.setTextColor(Color.parseColor("#10B981"))
        exitAfterDelay(Activity.RESULT_OK)
    }

    private fun showFailure() {
        progressBar.visibility = View.GONE
        titleTextView.text = "Channel Update Failed"
        messageTextView.text = "Please check network and try again later. Exiting shortly..."
        messageTextView.setTextColor(Color.parseColor("#EF4444"))
        exitAfterDelay(Activity.RESULT_CANCELED)
    }

    private fun exitAfterDelay(resultCode: Int) {
        exitHandler.postDelayed({
            setResult(resultCode)
            finish()
        }, AUTO_EXIT_DELAY_MS)
    }

    override fun onDestroy() {
        exitHandler.removeCallbacksAndMessages(null)
        activityScope.cancel()
        super.onDestroy()
    }
}
