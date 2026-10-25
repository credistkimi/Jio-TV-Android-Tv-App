package com.jio.tvplus.jio_tv_plus_flutter.tif

import android.content.ContentProviderOperation
import android.content.ContentUris
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.database.Cursor
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Typeface
import android.media.tv.TvContract
import android.net.Uri
import android.util.Log
import androidx.tvprovider.media.tv.Channel
import androidx.tvprovider.media.tv.ChannelLogoUtils
import androidx.tvprovider.media.tv.Program
import androidx.tvprovider.media.tv.TvContractCompat
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import java.io.InputStream
import java.net.HttpURLConnection
import java.net.URL

data class ChannelSyncItem(
    val internalId: String,
    val channelName: String,
    val logoUrl: String,
    val tier: String,
    val category: String
)

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

            // Existing channels map: internalProviderId -> system channel row _id
            val existingChannels = getExistingChannelsMap()
            val operations = ArrayList<ContentProviderOperation>()
            val syncItemList = ArrayList<ChannelSyncItem>()

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
                val originalNetId = channelId.toIntOrNull() ?: channelNo
                val category = item.optString("category", item.optString("channelCategoryId", "Entertainment"))
                val language = item.optString("language", item.optString("channelLanguageId", "Hindi"))

                // Free vs Premium tier detection based on price, is_premium, and business_type
                val rawPrice = item.optString("channelPrice", "").trim()
                val isPremium = item.optBoolean("is_premium", false) ||
                    item.optString("business_type").equals("premium", ignoreCase = true) ||
                    (rawPrice.isNotEmpty() && !rawPrice.equals("Free", ignoreCase = true))
                val tier = if (isPremium) "Premium" else "Free"

                // Robust channel logo resolution: ensure complete CDN URL
                val rawLogo = item.optString("logoUrl").ifEmpty {
                    item.optString("logoFilename", item.optString("logo", ""))
                }
                val logoUrl = when {
                    rawLogo.isEmpty() -> ""
                    rawLogo.startsWith("http://") || rawLogo.startsWith("https://") -> rawLogo
                    else -> "https://jiotv.catchup.cdn.jio.com/dare_images/images/$rawLogo"
                }

                syncItemList.add(ChannelSyncItem(channelId, channelName, logoUrl, tier, category))
                val streamUrl = item.optString("streamUrl", "")

                // Fire TV Deep Link Intent URI: selecting channel in Fire TV UI launches app player directly
                val appLinkIntent = Intent(Intent.ACTION_VIEW).apply {
                    data = Uri.parse("jiotv://channel/$channelId")
                    setPackage(context.packageName)
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                }
                val deepLinkUriString = appLinkIntent.toUri(Intent.URI_INTENT_SCHEME)

                // Internal provider data holding streaming details & playbackDeepLinkUri for Fire TV
                val internalData = JSONObject().apply {
                    put("playbackDeepLinkUri", deepLinkUriString)
                    put("channelId", channelId)
                    put("channelName", channelName)
                    put("channelNo", channelNo)
                    put("category", category)
                    put("language", language)
                    put("streamUrl", streamUrl)
                    put("logoUrl", logoUrl)
                    put("is_premium", isPremium)
                    put("tier", tier)
                    put("channelPrice", rawPrice)
                }.toString()

                val channelBuilder = Channel.Builder()
                    .setInputId(inputId)
                    .setType(TvContractCompat.Channels.TYPE_OTHER)
                    .setServiceType(TvContractCompat.Channels.SERVICE_TYPE_AUDIO_VIDEO)
                    .setDisplayNumber(channelNo.toString())
                    .setDisplayName(channelName)
                    .setDescription("$tier • $category • $language • HD")
                    .setNetworkAffiliation(if (isPremium) "JioTV+ [Premium]" else "JioTV+ [Free]")
                    .setSearchable(true)
                    .setOriginalNetworkId(originalNetId)
                    .setInternalProviderId(channelId)
                    .setInternalProviderData(internalData.toByteArray(Charsets.UTF_8))
                    .setAppLinkIntent(appLinkIntent)

                val contentValues = channelBuilder.build().toContentValues().apply {
                    put(TvContract.Channels.COLUMN_TYPE, TvContract.Channels.TYPE_OTHER)
                    put(TvContract.Channels.COLUMN_SERVICE_TYPE, TvContract.Channels.SERVICE_TYPE_AUDIO_VIDEO)
                    put(TvContract.Channels.COLUMN_SEARCHABLE, 1)
                    put(TvContract.Channels.COLUMN_ORIGINAL_NETWORK_ID, originalNetId)
                    put(TvContract.Channels.COLUMN_APP_LINK_INTENT_URI, deepLinkUriString)
                    put(TvContract.Channels.COLUMN_INTERNAL_PROVIDER_DATA, internalData.toByteArray(Charsets.UTF_8))
                    // CRITICAL: COLUMN_BROWSABLE and COLUMN_LOCKED are restricted to system apps.
                    // If a third-party TV provider attempts to write to COLUMN_BROWSABLE,
                    // Android throws java.lang.SecurityException: Not allowed to access Channels.COLUMN_BROWSABLE.
                    remove(TvContract.Channels.COLUMN_BROWSABLE)
                    remove("browsable")
                    remove(TvContract.Channels.COLUMN_LOCKED)
                    remove("locked")
                }

                val existingId = existingChannels[channelId]
                if (existingId != null) {
                    val updateUri = TvContract.buildChannelUri(existingId)
                    operations.add(
                        ContentProviderOperation.newUpdate(updateUri)
                            .withValues(contentValues)
                            .build()
                    )
                    updatedCount++
                } else {
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

            // Re-fetch system channel IDs for current input
            val updatedMap = getExistingChannelsMap()
            val pairedItems = ArrayList<Pair<Long, ChannelSyncItem>>()
            for (syncItem in syncItemList) {
                val sysId = updatedMap[syncItem.internalId]
                if (sysId != null) {
                    pairedItems.add(Pair(sysId, syncItem))
                }
            }

            // 1. Sync Amazon TIF Extension Genres (Free / Premium / Content Category)
            syncAmazonGenres(context, inputId, pairedItems)

            // 2. Re-query and populate baseline programs (next 24h) for all channels
            syncDefaultProgramsForAllChannels()

            // 3. Save sync status in SharedPreferences
            saveSyncStatus(totalSynced)

            // 4. Asynchronously populate logos in background (non-blocking for fast sync completion)
            CoroutineScope(Dispatchers.IO).launch {
                syncChannelLogos(context, pairedItems)
            }

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

                        val shortDesc = "Watch $channelName live on Fire TV."
                        val longDesc = "Watch live uninterrupted broadcast of $channelName in HD quality on JioTV+ TV."

                        val program = Program.Builder()
                            .setChannelId(systemChannelId)
                            .setTitle(title)
                            .setEpisodeTitle("Live Broadcast")
                            .setDescription(longDesc)
                            .setStartTimeUtcMillis(start)
                            .setEndTimeUtcMillis(end)
                            .setCanonicalGenres(arrayOf(mapGenreToCanonical(desc)))
                            .setInternalProviderData("prog_${internalId}_$start".toByteArray(Charsets.UTF_8))
                            .build()

                        val programValues = program.toContentValues().apply {
                            put(TvContract.Programs.COLUMN_SHORT_DESCRIPTION, shortDesc)
                            put(TvContract.Programs.COLUMN_LONG_DESCRIPTION, longDesc)
                        }

                        programOperations.add(
                            ContentProviderOperation.newInsert(TvContract.Programs.CONTENT_URI)
                                .withValues(programValues)
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
                    .setDescription(p.description)
                    .setStartTimeUtcMillis(p.startTimeUtcMillis)
                    .setEndTimeUtcMillis(p.endTimeUtcMillis)
                    .setPosterArtUri(if (p.posterArtUri.isNotEmpty()) Uri.parse(p.posterArtUri) else null)
                    .setCanonicalGenres(arrayOf(mapGenreToCanonical(p.genre)))
                    .setInternalProviderData(p.programId.toByteArray(Charsets.UTF_8))
                    .build()

                val programValues = program.toContentValues().apply {
                    put(TvContract.Programs.COLUMN_SHORT_DESCRIPTION, p.description)
                    put(TvContract.Programs.COLUMN_LONG_DESCRIPTION, p.description)
                }

                operations.add(
                    ContentProviderOperation.newInsert(TvContract.Programs.CONTENT_URI)
                        .withValues(programValues)
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

            Log.i(TAG, "Synced ${programs.size} detailed programs for channel $internalChannelId")
            return@withContext programs.size
        } catch (e: Exception) {
            Log.e(TAG, "Error syncing programs for channel $internalChannelId: ${e.message}", e)
            return@withContext 0
        }
    }

    /**
     * Retrieves channel metadata from TvContract using a Content URI.
     */
    fun getChannelByUri(channelUri: Uri): ChannelInfo? {
        val cursor = context.contentResolver.query(
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
            val internalId = c.getString(c.getColumnIndexOrThrow(TvContract.Channels.COLUMN_INTERNAL_PROVIDER_ID)) ?: ""
            val chNo = c.getString(c.getColumnIndexOrThrow(TvContract.Channels.COLUMN_DISPLAY_NUMBER))?.toIntOrNull() ?: 100
            val name = c.getString(c.getColumnIndexOrThrow(TvContract.Channels.COLUMN_DISPLAY_NAME)) ?: "JioTV Channel"

            val rawData = try {
                val blob = c.getBlob(c.getColumnIndexOrThrow(TvContract.Channels.COLUMN_INTERNAL_PROVIDER_DATA))
                if (blob != null) String(blob, Charsets.UTF_8) else null
            } catch (_: Exception) {
                try {
                    c.getString(c.getColumnIndexOrThrow(TvContract.Channels.COLUMN_INTERNAL_PROVIDER_DATA))
                } catch (_: Exception) {
                    null
                }
            }

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
        val channelsUri = TvContract.buildChannelsUriForInput(inputId)
        val cursor = context.contentResolver.query(
            channelsUri,
            arrayOf(TvContract.Channels._ID, TvContract.Channels.COLUMN_INTERNAL_PROVIDER_ID, TvContract.Channels.COLUMN_ORIGINAL_NETWORK_ID),
            null,
            null,
            null
        )
        cursor?.use { c ->
            val idIndex = c.getColumnIndexOrThrow(TvContract.Channels._ID)
            val internalIdIndex = c.getColumnIndex(TvContract.Channels.COLUMN_INTERNAL_PROVIDER_ID)
            val originalNetIdIndex = c.getColumnIndex(TvContract.Channels.COLUMN_ORIGINAL_NETWORK_ID)
            while (c.moveToNext()) {
                val internalId = if (internalIdIndex >= 0) c.getString(internalIdIndex) else null
                val originalNetId = if (originalNetIdIndex >= 0) c.getInt(originalNetIdIndex) else null
                val id = c.getLong(idIndex)
                if (!internalId.isNullOrEmpty()) {
                    map[internalId] = id
                } else if (originalNetId != null && originalNetId > 0) {
                    map[originalNetId.toString()] = id
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
                    val array = parseJsonChannels(text)
                    if (array != null && array.length() > 0) {
                        Log.i(TAG, "Successfully loaded ${array.length()} channels from asset: $path")
                        return array
                    }
                }
            } catch (e: Exception) {
                Log.d(TAG, "Could not load asset from $path: ${e.message}")
            }
        }
        Log.w(TAG, "Failed to load channels from all attempted asset paths")
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

    /**
     * Attributes Amazon Fire TV TIF Extension genres (Free / Premium / Content Category)
     * Reference: developer.amazon.com/docs/fire-tv/tv-input-framework-on-fire-tv.html
     */
    private fun syncAmazonGenres(
        context: Context,
        inputId: String,
        items: List<Pair<Long, ChannelSyncItem>>
    ) {
        try {
            val tifExtensionUri = Uri.parse("content://com.amazon.tv.livetv.tifextension/channel")
            var count = 0
            for ((systemId, item) in items) {
                // 1. Primary Free or Premium category
                try {
                    val tierValues = ContentValues().apply {
                        put("input_id", inputId)
                        put("channel_id", systemId)
                        put("genre", item.tier)
                    }
                    context.contentResolver.insert(tifExtensionUri, tierValues)
                    count++
                } catch (_: Exception) {}

                // 2. Broadcast Category (e.g. Sports, News, Movies)
                if (item.category.isNotEmpty() && !item.category.equals(item.tier, ignoreCase = true)) {
                    try {
                        val catValues = ContentValues().apply {
                            put("input_id", inputId)
                            put("channel_id", systemId)
                            put("genre", item.category)
                        }
                        context.contentResolver.insert(tifExtensionUri, catValues)
                    } catch (_: Exception) {}
                }
            }
            Log.i(TAG, "Successfully synced Amazon TIF Extension genres ($count tier entries)")
        } catch (e: Exception) {
            Log.d(TAG, "Amazon TIF Extension provider not accessible: ${e.message}")
        }
    }

    /**
     * Ingests channel logos into content://android.media.tv/channel/{channelId}/logo.
     * Android TV & Fire TV live guide tiles render icons directly from this content URI.
     */
    private suspend fun syncChannelLogos(
        context: Context,
        items: List<Pair<Long, ChannelSyncItem>>
    ) = withContext(Dispatchers.IO) {
        try {
            val pending = items.filter { !hasChannelLogo(context, it.first) }
            Log.i(TAG, "Starting logo ingestion: ${pending.size} channels require logos (${items.size - pending.size} already present)")

            // Concurrently download and store logos in batches of 15
            pending.chunked(15).forEach { chunk ->
                coroutineScope {
                    chunk.map { (systemId, item) ->
                        async {
                            downloadAndStoreLogo(context, systemId, item.logoUrl, item.channelName)
                        }
                    }.awaitAll()
                }
            }
            Log.i(TAG, "Completed channel logo ingestion for all channels")
        } catch (e: Exception) {
            Log.w(TAG, "Error synchronizing channel logos: ${e.message}")
        }
    }

    private fun hasChannelLogo(context: Context, channelId: Long): Boolean {
        val uri = TvContract.buildChannelLogoUri(channelId)
        return try {
            context.contentResolver.openInputStream(uri)?.use { true } ?: false
        } catch (_: Exception) {
            false
        }
    }

    private suspend fun downloadAndStoreLogo(
        context: Context,
        systemChannelId: Long,
        logoUrl: String,
        channelName: String
    ) = withContext(Dispatchers.IO) {
        try {
            var bitmap: Bitmap? = null
            if (logoUrl.isNotEmpty() && (logoUrl.startsWith("http://") || logoUrl.startsWith("https://"))) {
                try {
                    val url = URL(logoUrl)
                    val conn = url.openConnection() as HttpURLConnection
                    conn.connectTimeout = 3000
                    conn.readTimeout = 3000
                    conn.requestMethod = "GET"
                    conn.setRequestProperty("User-Agent", "Mozilla/5.0")
                    if (conn.responseCode == HttpURLConnection.HTTP_OK) {
                        conn.inputStream.use { stream ->
                            bitmap = BitmapFactory.decodeStream(stream)
                        }
                    }
                } catch (e: Exception) {
                    // Fall back to programmatic branded vector logo
                }
            }

            val finalBitmap = bitmap ?: generateFallbackChannelLogo(channelName)
            ChannelLogoUtils.storeChannelLogo(context, systemChannelId, finalBitmap)
        } catch (e: Exception) {
            Log.d(TAG, "Failed storing logo for channel $systemChannelId ($channelName): ${e.message}")
        }
    }

    /**
     * Programmatically generates a crisp 256x256 branded logo disk for immediate display
     * in the Fire TV guide when remote logos are loading or unavailable.
     */
    private fun generateFallbackChannelLogo(channelName: String): Bitmap {
        val size = 256
        val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)

        // Rounded background disk in deep Jio blue
        val bgPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.parseColor("#0A2885")
            style = Paint.Style.FILL
        }
        val rect = RectF(12f, 12f, (size - 12).toFloat(), (size - 12).toFloat())
        canvas.drawRoundRect(rect, 40f, 40f, bgPaint)

        // Blue accent highlight border
        val borderPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.parseColor("#0070F3")
            style = Paint.Style.STROKE
            strokeWidth = 6f
        }
        canvas.drawRoundRect(rect, 40f, 40f, borderPaint)

        // Compute 2-4 letter initials from channel name (e.g. "Colors HD" -> "COL", "Sony Max" -> "MAX")
        val words = channelName.trim().split("\\s+".toRegex()).filter { it.isNotEmpty() }
        val initials = when {
            words.size >= 2 -> words[0].take(2).uppercase() + words[1].take(2).uppercase()
            words.isNotEmpty() -> words[0].take(4).uppercase()
            else -> "JIO"
        }

        val textPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.WHITE
            textSize = if (initials.length <= 3) 72f else 54f
            typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
            textAlign = Paint.Align.CENTER
        }

        val xPos = size / 2f
        val yPos = (size / 2f) - ((textPaint.descent() + textPaint.ascent()) / 2f)
        canvas.drawText(initials, xPos, yPos, textPaint)

        return bitmap
    }
}
