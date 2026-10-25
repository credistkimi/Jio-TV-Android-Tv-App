package com.jio.tvplus.jio_tv_plus_flutter.tif

import android.app.Activity
import android.graphics.Color
import android.graphics.Typeface
import android.os.Bundle
import android.view.Gravity
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * Setup Activity launched when Fire TV user initiates "Sync Sources" under Settings > Live TV.
 * Reference: Amazon Fire TV Linear TV Integration Guide
 * - developer.amazon.com/docs/fire-tv/set-up-tvinputservice.html
 * - developer.amazon.com/docs/fire-tv/insert-your-first-channel.html
 */
class JioTvSetupActivity : AppCompatActivity() {

    private val activityScope = CoroutineScope(Dispatchers.Main + Job())
    private lateinit var statusTextView: TextView
    private lateinit var countTextView: TextView
    private lateinit var progressBar: ProgressBar

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Leanback 10-foot TV dark UI
        val rootLayout = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setBackgroundColor(Color.parseColor("#0A0E1A"))
            setPadding(80, 60, 80, 60)
        }

        val titleView = TextView(this).apply {
            text = "JioTV+ Live TV Setup"
            textSize = 28f
            setTextColor(Color.WHITE)
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
            setPadding(0, 0, 0, 16)
        }
        rootLayout.addView(titleView)

        statusTextView = TextView(this).apply {
            text = "Scanning and syncing Live TV channels to Fire TV Guide..."
            textSize = 18f
            setTextColor(Color.parseColor("#9CA3AF"))
            gravity = Gravity.CENTER
            setPadding(0, 0, 0, 32)
        }
        rootLayout.addView(statusTextView)

        progressBar = ProgressBar(this).apply {
            layoutParams = LinearLayout.LayoutParams(600, 24).apply {
                gravity = Gravity.CENTER
                bottomMargin = 24
            }
        }
        rootLayout.addView(progressBar)

        countTextView = TextView(this).apply {
            text = "Please wait..."
            textSize = 15f
            setTextColor(Color.parseColor("#3B82F6"))
            gravity = Gravity.CENTER
        }
        rootLayout.addView(countTextView)

        setContentView(rootLayout)

        // Start channel synchronization
        startEpgSync()
    }

    private fun startEpgSync() {
        activityScope.launch {
            val epgManager = JioTvEpgManager(this@JioTvSetupActivity)
            val syncedCount = withContext(Dispatchers.IO) {
                epgManager.syncChannels()
            }

            if (syncedCount > 0) {
                statusTextView.text = "Sync Complete!"
                countTextView.text = "Successfully added $syncedCount live channels to Fire TV Guide."
                countTextView.setTextColor(Color.parseColor("#10B981"))
            } else {
                statusTextView.text = "Sync Finished"
                countTextView.text = "Channels are up-to-date in Fire TV Guide."
            }

            // Brief delay to let the user see the success confirmation on TV screen
            delay(1200)

            setResult(Activity.RESULT_OK)
            finish()
        }
    }
}
