package com.jio.tvplus.jio_tv_plus_flutter.tif

import android.content.ContentProviderOperation
import android.content.ContentUris
import android.content.Context
import android.content.Intent
import android.database.Cursor
import android.media.tv.TvContract
import android.net.Uri
import android.util.Log
import androidx.tvprovider.media.tv.Channel
import androidx.tvprovider.media.tv.Program
import androidx.tvprovider.media.tv.TvContractCompat
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import java.io.InputStream

data class ChannelInfo(
    val id: Long,
    val internalId: String,
    val channelNo: Int,
    val name: String,
    val category: String,
    val language: String,
    val streamUrl: String,
    val logoUrl: String
)

data class ProgramItem(
    val programId: String,
    val title: String,
    val episodeTitle: String,
    val description: String,
    val startTimeUtcMillis: Long,
    val endTimeUtcMillis: Long,
    val posterArtUri: String,
    val genre: String
)

/**
 * Manages Amazon Fire TV Linear TV EPG synchronization with Android TV Input Framework (TIF).
 * Reference: Amazon Fire TV Linear TV Integration Guide
 * - developer.amazon.com/docs/fire-tv/insert-your-first-channel.html
 * - developer.amazon.com/docs/fire-tv/tv-input-framework-on-fire-tv.html
 */
class JioTvEpgManager(private val context: Context) {

    companion object {
        private const val TAG = "JioTvEpgManager"
        private const val PREFS_NAME = "jio_fire_tv_epg_prefs"
        private const val KEY_LAST_SYNC_TIME = "last_sync_time"
        private const val KEY_CHANNEL_COUNT = "synced_channel_count"

        // Map JioTV categories to Android TIF canonical genres
        fun mapGenreToCanonical(category: String): String {
            val cat = category.trim().lowercase()
            return when {
                cat.contains("movie") || cat.contains("cinema") -> TvContract.Programs.Genres.MOVIES
                cat.contains("sport") -> TvContract.Programs.Genres.SPORTS
                cat.contains("news") -> TvContract.Programs.Genres.NEWS
                cat.contains("kid") || cat.contains("child") || cat.contains("cartoon") -> TvContract.Programs.Genres.FAMILY_KIDS
                cat.contains("music") -> TvContract.Programs.Genres.MUSIC
                cat.contains("life") || cat.contains("fashion") -> TvContract.Programs.Genres.LIFE_STYLE
                cat.contains("educat") || cat.contains("infotainment") -> TvContract.Programs.Genres.EDUCATION
                cat.contains("shopping") -> TvContract.Programs.Genres.SHOPPING
                cat.contains("devotional") -> TvContract.Programs.Genres.TRAVEL
                else -> TvContract.Programs.Genres.ENTERTAINMENT
            }
        }
    }

    private val inputId: String by lazy {
        TvContract.buildInputId(android.content.ComponentName(context, JioTvInputService::class.java))
    }

    /**
     * Synchronizes live channels into Android's TvContract database for Amazon Fire TV Guide.
     */
    suspend fun syncChannels(customJson: String? = null): Int = withContext(Dispatchers.IO) {
        try {
            val jsonArray = if (customJson != null && customJson.isNotEmpty()) {
                parseJsonChannels(customJson)
            } else {
                loadChannelsFromAssets()
            }

            if (jsonArray == null || jsonArray.length() == 0) {
                Log.w(TAG, "No channels found to sync into Fire TV EPG")
                return@withContext 0
            }

            // Existing channels map: internalProviderId -> channelId
            val existingChannels = getExistingChannelsMap()
            val operations = ArrayList<ContentProviderOperation>()

            var insertedCount = 0
            var updatedCount = 0

            for (i in 0 until jsonArray.length()) {
                val item = jsonArray.optJSONObject(i) ?: continue
                val channelId = item.optString("channel_id").ifEmpty {
                    item.optString("channelId", "$i")
                }
                val channelName = item.optString("channel_name").ifEmpty {
                    item.optString("channelName", "JioTV Channel $channelId")
                }
                val channelNo = item.optInt("channel_order", item.optInt("channelNo", 100 + i))
                val category = item.optString("category", item.optString("channelCategoryId", "Entertainment"))
                val language = item.optString("language", item.optString("channelLanguageId", "Hindi"))
                val logoUrl = item.optString("logoUrl").ifEmpty {
                    val logoName = item.optString("logoFilename", item.optString("logo", ""))
                    if (logoName.isNotEmpty()) "https://jiotv.catchup.cdn.jio.com/dare_images/images/$logoName" else ""
                }
                val streamUrl = item.optString("streamUrl", "")

                // Fire TV Deep Link Intent URI: clicking channel in Guide launches app player directly
                val appLinkIntent = Intent(Intent.ACTION_VIEW).apply {
                    data = Uri.parse("jiotv://channel/$channelId")
                    setPackage(context.packageName)
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                }

                // Internal provider data holding streaming details for Fire TV Preview playback
                val internalData = JSONObject().apply {
                    put("channelId", channelId)
                    put("channelName", channelName)
                    put("channelNo", channelNo)
                    put("category", category)
                    put("language", language)
                    put("streamUrl", streamUrl)
                    put("logoUrl", logoUrl)
                }.toString()

                val channelBuilder = Channel.Builder()
                    .setInputId(inputId)
                    .setType(TvContractCompat.Channels.TYPE_PREVIEW)
                    .setServiceType(TvContractCompat.Channels.SERVICE_TYPE_AUDIO_VIDEO)
                    .setDisplayNumber(channelNo.toString())
                    .setDisplayName(channelName)
                    .setDescription("$category • $language • HD")
                    .setNetworkAffiliation("JioTV+")
                    .setInternalProviderId(channelId)
                    .setInternalProviderData(internalData)
                    .setAppLinkIntent(appLinkIntent)

                val contentValues = channelBuilder.build().toContentValues().apply {
                    put(TvContract.Channels.COLUMN_APP_LINK_INTENT_URI, appLinkIntent.toUri(Intent.URI_INTENT_SCHEME))
                }

                val existingId = existingChannels[channelId]
                if (existingId != null) {
                    // Update channel
                    val updateUri = TvContract.buildChannelUri(existingId)
                    operations.add(
                        ContentProviderOperation.newUpdate(updateUri)
                            .withValues(contentValues)
                            .build()
                    )
                    updatedCount++
                } else {
                    // Insert channel
                    val insertUri = TvContract.Channels.CONTENT_URI
                    operations.add(
                        ContentProviderOperation.newInsert(insertUri)
                            .withValues(contentValues)
                            .build()
                    )
                    insertedCount++
                }

                // Apply in batches of 50 to avoid binder transaction limits
                if (operations.size >= 50) {
                    context.contentResolver.applyBatch(TvContract.AUTHORITY, operations)
                    operations.clear()
                }
            }

            if (operations.isNotEmpty()) {
                context.contentResolver.applyBatch(TvContract.AUTHORITY, operations)
                operations.clear()
            }

            val totalSynced = insertedCount + updatedCount
            Log.i(TAG, "Fire TV EPG Sync completed: $insertedCount inserted, $updatedCount updated")

            // Re-query and populate baseline programs (next 24h) for all channels
            syncDefaultProgramsForAllChannels()

            // Save sync status in SharedPreferences
            saveSyncStatus(totalSynced)

            return@withContext totalSynced
        } catch (e: Exception) {
            Log.e(TAG, "Error synchronizing channels to Fire TV EPG: ${e.message}", e)
            return@withContext 0
        }
    }

    /**
     * Populates baseline rolling program schedule (EPG) blocks for all channels in TvContract.
     */
    suspend fun syncDefaultProgramsForAllChannels() = withContext(Dispatchers.IO) {
        try {
            val cursor = context.contentResolver.query(
                TvContract.Channels.CONTENT_URI,
                arrayOf(TvContract.Channels._ID, TvContract.Channels.COLUMN_INTERNAL_PROVIDER_ID, TvContract.Channels.COLUMN_DISPLAY_NAME, TvContract.Channels.COLUMN_DESCRIPTION),
                "${TvContract.Channels.COLUMN_INPUT_ID}=?",
                arrayOf(inputId),
                null
            ) ?: return@withContext

            val now = System.currentTimeMillis()
            val thirtyMinutes = 30 * 60 * 1000L
            val currentBlockStart = (now / thirtyMinutes) * thirtyMinutes

            val programOperations = ArrayList<ContentProviderOperation>()

            cursor.use { c ->
                val idIndex = c.getColumnIndexOrThrow(TvContract.Channels._ID)
                val internalIdIndex = c.getColumnIndexOrThrow(TvContract.Channels.COLUMN_INTERNAL_PROVIDER_ID)
                val nameIndex = c.getColumnIndexOrThrow(TvContract.Channels.COLUMN_DISPLAY_NAME)
                val descIndex = c.getColumnIndexOrThrow(TvContract.Channels.COLUMN_DESCRIPTION)

                while (c.moveToNext()) {
                    val systemChannelId = c.getLong(idIndex)
                    val internalId = c.getString(internalIdIndex) ?: "$systemChannelId"
                    val channelName = c.getString(nameIndex) ?: "Live Channel"
                    val desc = c.getString(descIndex) ?: "Entertainment"

                    // Delete expired past programs for this channel
                    programOperations.add(
                        ContentProviderOperation.newDelete(TvContract.Programs.CONTENT_URI)
                            .withSelection(
                                "${TvContract.Programs.COLUMN_CHANNEL_ID}=? AND ${TvContract.Programs.COLUMN_END_TIME_UTC_MILLIS} < ?",
                                arrayOf(systemChannelId.toString(), now.toString())
                            )
                            .build()
                    )

                    // Generate next 4 program blocks (2 hours) of continuous live schedules
                    for (block in 0 until 6) {
                        val start = currentBlockStart + (block * thirtyMinutes)
                        val end = start + thirtyMinutes

                        val title = when (block) {
                            0 -> "$channelName Live Broadcast"
                            1 -> "$channelName Prime Hour"
                            2 -> "$channelName Evening Special"
                            3 -> "$channelName Super Showcase"
                            4 -> "$channelName Night Express"
                            else -> "$channelName Live Stream"
                        }

                        val program = Program.Builder()
                            .setChannelId(systemChannelId)
                            .setTitle(title)
                            .setEpisodeTitle("Live Broadcast")
                            .setShortDescription("Watch live uninterrupted broadcast of $channelName in HD quality on JioTV+ TV.")
                            .setStartTimeUtcMillis(start)
                            .setEndTimeUtcMillis(end)
                            .setCanonicalGenres(arrayOf(mapGenreToCanonical(desc)))
                            .setInternalProviderData("prog_${internalId}_$start")
                            .build()

                        programOperations.add(
                            ContentProviderOperation.newInsert(TvContract.Programs.CONTENT_URI)
                                .withValues(program.toContentValues())
                                .build()
                        )
                    }

                    if (programOperations.size >= 50) {
                        context.contentResolver.applyBatch(TvContract.AUTHORITY, programOperations)
                        programOperations.clear()
                    }
                }
            }

            if (programOperations.isNotEmpty()) {
                context.contentResolver.applyBatch(TvContract.AUTHORITY, programOperations)
                programOperations.clear()
            }

            Log.i(TAG, "Default program schedule successfully injected for all Fire TV channels")
        } catch (e: Exception) {
            Log.e(TAG, "Error populating default programs in Fire TV EPG: ${e.message}", e)
        }
    }

    /**
     * Inserts detailed schedule programs for a specific channel (e.g. from upstream Jio EPG API).
     */
    suspend fun syncProgramsForChannel(internalChannelId: String, programs: List<ProgramItem>): Int = withContext(Dispatchers.IO) {
        try {
            val systemChannelId = getSystemChannelId(internalChannelId) ?: return@withContext 0

            val operations = ArrayList<ContentProviderOperation>()

            // Clear existing programs for this channel
            operations.add(
                ContentProviderOperation.newDelete(TvContract.Programs.CONTENT_URI)
                    .withSelection("${TvContract.Programs.COLUMN_CHANNEL_ID}=?", arrayOf(systemChannelId.toString()))
                    .build()
            )

            for (p in programs) {
                val program = Program.Builder()
                    .setChannelId(systemChannelId)
                    .setTitle(p.title)
                    .setEpisodeTitle(p.episodeTitle)
                    .setShortDescription(p.description)
                    .setStartTimeUtcMillis(p.startTimeUtcMillis)
                    .setEndTimeUtcMillis(p.endTimeUtcMillis)
                    .setPosterArtUri(if (p.posterArtUri.isNotEmpty()) Uri.parse(p.posterArtUri) else null)
                    .setCanonicalGenres(arrayOf(mapGenreToCanonical(p.genre)))
                    .setInternalProviderData(p.programId)
                    .build()

                operations.add(
                    ContentProviderOperation.newInsert(TvContract.Programs.CONTENT_URI)
                        .withValues(program.toContentValues())
                        .build()
                )

                if (operations.size >= 50) {
                    context.contentResolver.applyBatch(TvContract.AUTHORITY, operations)
                    operations.clear()
                }
            }

            if (operations.isNotEmpty()) {
                context.contentResolver.applyBatch(TvContract.AUTHORITY, operations)
                operations.clear()
            }

            Log.i(TAG, "Synced ${programs.size} EPG programs for channel $internalChannelId")
            return@withContext programs.size
        } catch (e: Exception) {
            Log.e(TAG, "Error syncing programs for channel $internalChannelId: ${e.message}", e)
            return@withContext 0
        }
    }

    /**
     * Retrieves channel information given its TvContract content URI.
     */
    fun getChannelByUri(channelUri: Uri): ChannelInfo? {
        val cursor: Cursor? = context.contentResolver.query(
            channelUri,
            arrayOf(
                TvContract.Channels._ID,
                TvContract.Channels.COLUMN_INTERNAL_PROVIDER_ID,
                TvContract.Channels.COLUMN_DISPLAY_NUMBER,
                TvContract.Channels.COLUMN_DISPLAY_NAME,
                TvContract.Channels.COLUMN_INTERNAL_PROVIDER_DATA
            ),
            null,
            null,
            null
        )

        return cursor?.use { c ->
            if (!c.moveToFirst()) return null

            val id = c.getLong(c.getColumnIndexOrThrow(TvContract.Channels._ID))
            val internalId = c.getString(c.getColumnIndexOrThrow(TvContract.Channels.COLUMN_INTERNAL_PROVIDER_ID)) ?: "$id"
            val chNo = c.getString(c.getColumnIndexOrThrow(TvContract.Channels.COLUMN_DISPLAY_NUMBER))?.toIntOrNull() ?: 100
            val name = c.getString(c.getColumnIndexOrThrow(TvContract.Channels.COLUMN_DISPLAY_NAME)) ?: "JioTV Channel"
            val rawData = c.getString(c.getColumnIndexOrThrow(TvContract.Channels.COLUMN_INTERNAL_PROVIDER_DATA))

            var streamUrl = ""
            var category = "Entertainment"
            var language = "Hindi"
            var logoUrl = ""

            if (!rawData.isNullOrEmpty()) {
                try {
                    val json = JSONObject(rawData)
                    streamUrl = json.optString("streamUrl", "")
                    category = json.optString("category", "Entertainment")
                    language = json.optString("language", "Hindi")
                    logoUrl = json.optString("logoUrl", "")
                } catch (_: Exception) {}
            }

            ChannelInfo(
                id = id,
                internalId = internalId,
                channelNo = chNo,
                name = name,
                category = category,
                language = language,
                streamUrl = streamUrl,
                logoUrl = logoUrl
            )
        }
    }

    /**
     * Looks up system channel ID by internal channel ID (e.g. "104").
     */
    fun getSystemChannelId(internalChannelId: String): Long? {
        val cursor = context.contentResolver.query(
            TvContract.Channels.CONTENT_URI,
            arrayOf(TvContract.Channels._ID),
            "${TvContract.Channels.COLUMN_INPUT_ID}=? AND ${TvContract.Channels.COLUMN_INTERNAL_PROVIDER_ID}=?",
            arrayOf(inputId, internalChannelId),
            null
        )
        return cursor?.use {
            if (it.moveToFirst()) it.getLong(0) else null
        }
    }

    private fun getExistingChannelsMap(): Map<String, Long> {
        val map = HashMap<String, Long>()
        val cursor = context.contentResolver.query(
            TvContract.Channels.CONTENT_URI,
            arrayOf(TvContract.Channels._ID, TvContract.Channels.COLUMN_INTERNAL_PROVIDER_ID),
            "${TvContract.Channels.COLUMN_INPUT_ID}=?",
            arrayOf(inputId),
            null
        )
        cursor?.use { c ->
            val idIndex = c.getColumnIndexOrThrow(TvContract.Channels._ID)
            val internalIdIndex = c.getColumnIndexOrThrow(TvContract.Channels.COLUMN_INTERNAL_PROVIDER_ID)
            while (c.moveToNext()) {
                val internalId = c.getString(internalIdIndex)
                val id = c.getLong(idIndex)
                if (!internalId.isNullOrEmpty()) {
                    map[internalId] = id
                }
            }
        }
        return map
    }

    private fun loadChannelsFromAssets(): JSONArray? {
        val possiblePaths = listOf(
            "flutter_assets/assets/channels.json",
            "assets/channels.json",
            "channels.json"
        )
        for (path in possiblePaths) {
            try {
                context.assets.open(path).use { stream ->
                    val text = stream.bufferedReader().use { it.readText() }
                    return parseJsonChannels(text)
                }
            } catch (_: Exception) {}
        }
        return null
    }

    private fun parseJsonChannels(jsonString: String): JSONArray? {
        return try {
            val trimmed = jsonString.trim()
            if (trimmed.startsWith("[")) {
                JSONArray(trimmed)
            } else {
                val root = JSONObject(trimmed)
                root.optJSONArray("result")
                    ?: root.optJSONArray("data")
                    ?: root.optJSONArray("channels")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error parsing channels JSON: ${e.message}")
            null
        }
    }

    private fun saveSyncStatus(channelCount: Int) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putLong(KEY_LAST_SYNC_TIME, System.currentTimeMillis())
            .putInt(KEY_CHANNEL_COUNT, channelCount)
            .apply()
    }

    fun getSyncStatus(): Map<String, Any> {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        return mapOf(
            "lastSyncTime" to prefs.getLong(KEY_LAST_SYNC_TIME, 0L),
            "channelCount" to prefs.getInt(KEY_CHANNEL_COUNT, 0),
            "inputId" to inputId
        )
    }
}
