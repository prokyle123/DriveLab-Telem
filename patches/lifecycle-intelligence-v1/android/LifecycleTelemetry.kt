package com.auroramediagroup.drivelab

import android.content.Context
import android.os.Build
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import java.math.BigDecimal
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest
import java.util.UUID
import kotlin.math.round

internal const val LIFECYCLE_CLIENT_VERSION = "1.0.0"
private const val MAX_LOCAL_EVENTS = 250
private const val MAX_BATCH_EVENTS = 50
private const val MAX_TEXT = 240

data class LifecycleTelemetryState(
    val configured: Boolean = false,
    val enabled: Boolean = true,
    val featureUsageEnabled: Boolean = false,
    val sessionSummariesEnabled: Boolean = false,
    val registered: Boolean = false,
    val pendingEvents: Int = 0,
    val busy: Boolean = false,
    val lastUploadAtMs: Long = 0L,
    val lastMessage: String = "Lifecycle reporting is waiting for startup."
)

internal fun lifecycleCanonicalJson(value: Any?): String = when (value) {
    null, JSONObject.NULL -> "null"
    is JSONObject -> {
        val keys = buildList {
            val iterator = value.keys()
            while (iterator.hasNext()) add(iterator.next())
        }.sorted()
        keys.joinToString(prefix = "{", postfix = "}", separator = ",") { key ->
            lifecycleJsonString(key) + ":" + lifecycleCanonicalJson(value.opt(key))
        }
    }
    is JSONArray -> (0 until value.length()).joinToString(prefix = "[", postfix = "]", separator = ",") {
        lifecycleCanonicalJson(value.opt(it))
    }
    is String -> lifecycleJsonString(value)
    is Boolean -> if (value) "true" else "false"
    is Number -> lifecycleCanonicalNumber(value)
    else -> lifecycleJsonString(value.toString())
}

private fun lifecycleCanonicalNumber(value: Number): String {
    val number = value.toDouble()
    if (!number.isFinite()) return "0"
    val normalized = if (number == -0.0) 0.0 else number
    return BigDecimal.valueOf(normalized).stripTrailingZeros().toPlainString()
}

private fun lifecycleJsonString(value: String): String = buildString(value.length + 8) {
    append('"')
    value.forEach { character ->
        when (character) {
            '"' -> append("\\\"")
            '\\' -> append("\\\\")
            '\b' -> append("\\b")
            '\u000C' -> append("\\f")
            '\n' -> append("\\n")
            '\r' -> append("\\r")
            '\t' -> append("\\t")
            else -> {
                if (character.code in 0x20..0x7E) {
                    append(character)
                } else {
                    append("\\u")
                    append(character.code.toString(16).padStart(4, '0'))
                }
            }
        }
    }
    append('"')
}

private fun lifecycleNumber(value: Double, minimum: Double, maximum: Double): Number {
    if (!value.isFinite()) return 0
    val clamped = value.coerceIn(minimum, maximum)
    val rounded = round(clamped * 10_000.0) / 10_000.0
    return if (rounded % 1.0 == 0.0) rounded.toLong() else rounded
}

class LifecycleTelemetryManager(context: Context) {
    private val applicationContext = context.applicationContext
    private val identity = InstallationIdentity(applicationContext)
    private val preferences = applicationContext.getSharedPreferences(
        "drivelab_lifecycle_telemetry",
        Context.MODE_PRIVATE
    )
    private val serverUrl = BuildConfig.LICENSE_SERVER_URL.trim().trimEnd('/')
    private val appVersion = BuildConfig.VERSION_NAME.substringBefore('-')
    private val flushMutex = Mutex()
    private val queueLock = Any()
    private val appSessionId = UUID.randomUUID().toString()

    @Volatile private var operationalEnabled = true
    @Volatile private var featureUsageEnabled = false
    @Volatile private var sessionSummariesEnabled = false
    @Volatile private var started = false
    @Volatile private var appSessionStartedAtMs = 0L
    @Volatile private var backgroundedAtMs = 0L

    private val _state = MutableStateFlow(
        LifecycleTelemetryState(
            configured = serverUrl.isNotBlank(),
            pendingEvents = pendingCount()
        )
    )
    val state: StateFlow<LifecycleTelemetryState> = _state.asStateFlow()

    fun configure(
        enabled: Boolean,
        featureUsage: Boolean,
        sessionSummaries: Boolean
    ) {
        operationalEnabled = enabled
        featureUsageEnabled = enabled && featureUsage
        sessionSummariesEnabled = enabled && sessionSummaries
        if (!enabled) {
            synchronized(queueLock) {
                preferences.edit().remove("pendingEvents").apply()
            }
        }
        publishState(
            enabled = enabled,
            featureUsageEnabled = featureUsageEnabled,
            sessionSummariesEnabled = sessionSummariesEnabled,
            pendingEvents = pendingCount(),
            lastMessage = if (enabled) {
                "Device and reliability reporting is enabled."
            } else {
                "Lifecycle reporting is disabled and pending reports were cleared."
            }
        )
    }

    suspend fun initialize(currentEdition: String) {
        if (started) return
        started = true
        appSessionStartedAtMs = System.currentTimeMillis()
        val previousRunClean = preferences.getBoolean("currentRunClean", true)
        preferences.edit().putBoolean("currentRunClean", false).apply()

        if (operationalEnabled) {
            enqueue(
                eventType = "app_launch",
                properties = JSONObject()
                    .put("launch_reason", "normal")
                    .put("previous_run_clean", previousRunClean)
                    .put("android_version", Build.VERSION.RELEASE.orEmpty().take(40))
                    .put(
                        "device_model",
                        "${Build.MANUFACTURER} ${Build.MODEL}".trim().take(120)
                    )
            )

            val previousVersion = preferences.getString("lastAppVersion", "").orEmpty()
            if (previousVersion.isNotBlank() && previousVersion != appVersion) {
                enqueue(
                    eventType = "version_changed",
                    properties = JSONObject()
                        .put("from_version", previousVersion.take(40))
                        .put("to_version", appVersion.take(40))
                )
            }
            preferences.edit().putString("lastAppVersion", appVersion).apply()
            updateEdition(currentEdition)
            flush()
        }
    }

    fun onForegrounded() {
        if (!started || !operationalEnabled) return
        val backgroundAt = backgroundedAtMs
        preferences.edit().putBoolean("currentRunClean", false).apply()
        if (backgroundAt > 0L) {
            val seconds = ((System.currentTimeMillis() - backgroundAt).coerceAtLeast(0L) / 1000.0)
            enqueue(
                eventType = "app_foreground",
                properties = JSONObject().put(
                    "background_seconds",
                    lifecycleNumber(seconds, 0.0, 30.0 * 86400.0)
                )
            )
        }
        backgroundedAtMs = 0L
    }

    fun onBackgrounded() {
        if (!started) return
        if (backgroundedAtMs > 0L) return
        val now = System.currentTimeMillis()
        if (operationalEnabled) {
            val duration = ((now - appSessionStartedAtMs).coerceAtLeast(0L) / 1000.0)
            enqueue(
                eventType = "app_session_ended",
                properties = JSONObject()
                    .put("clean", true)
                    .put("duration_seconds", lifecycleNumber(duration, 0.0, 30.0 * 86400.0))
            )
        }
        preferences.edit().putBoolean("currentRunClean", true).apply()
        backgroundedAtMs = now
    }

    fun markCleanShutdown() {
        preferences.edit().putBoolean("currentRunClean", true).apply()
    }

    fun updateEdition(edition: String) {
        if (!operationalEnabled) return
        val normalized = if (edition.equals("full", ignoreCase = true)) "full" else "free"
        val previous = preferences.getString("lastEdition", "").orEmpty()
        if (previous.isNotBlank() && previous != normalized) {
            enqueue(
                eventType = "edition_changed",
                properties = JSONObject()
                    .put("from_edition", previous)
                    .put("to_edition", normalized)
            )
        }
        preferences.edit().putString("lastEdition", normalized).apply()
    }

    fun recordConnectionAttempt(mode: String) {
        if (!operationalEnabled) return
        enqueue("beamng_connect_attempt", JSONObject().put("mode", mode.take(80)))
    }

    fun recordConnected(mode: String, timeToFirstPacketMs: Long) {
        if (!operationalEnabled) return
        enqueue(
            "beamng_connected",
            JSONObject()
                .put("mode", mode.take(80))
                .put("time_to_first_packet_ms", timeToFirstPacketMs.coerceIn(0L, 2_000_000L))
        )
    }

    fun recordConnectionFailed(reason: String) {
        if (!operationalEnabled) return
        enqueue(
            "beamng_connect_failed",
            JSONObject().put("reason", reason.ifBlank { "unknown" }.take(MAX_TEXT))
        )
    }

    fun recordDisconnected(reason: String, durationSeconds: Double, reconnectCount: Int) {
        if (!operationalEnabled) return
        enqueue(
            "beamng_disconnected",
            JSONObject()
                .put("reason", reason.ifBlank { "packet_timeout" }.take(MAX_TEXT))
                .put(
                    "duration_seconds",
                    lifecycleNumber(durationSeconds, 0.0, 30.0 * 86400.0)
                )
                .put("reconnect_count", reconnectCount.coerceIn(0, 2_000_000))
        )
    }

    fun recordFeatureOpened(feature: String) {
        if (!operationalEnabled || !featureUsageEnabled) return
        enqueue("feature_opened", JSONObject().put("feature", feature.take(64)))
    }

    fun recordFeatureCompleted(feature: String, result: String) {
        if (!operationalEnabled || !featureUsageEnabled) return
        enqueue(
            "feature_completed",
            JSONObject()
                .put("feature", feature.take(64))
                .put("result", result.take(MAX_TEXT))
        )
    }

    fun recordSessionSummary(session: SessionSummary, automatic: Boolean) {
        if (!operationalEnabled || !sessionSummariesEnabled || session.isDemo) return
        enqueue(
            eventType = "drive_session_summary",
            properties = JSONObject()
                .put(
                    "duration_seconds",
                    lifecycleNumber(session.durationSeconds, 0.0, 30.0 * 86400.0)
                )
                .put(
                    "distance_meters",
                    lifecycleNumber(session.distanceMeters, 0.0, 10_000_000.0)
                )
                .put(
                    "max_speed_mph",
                    lifecycleNumber(session.maxSpeedMph, 0.0, 1000.0)
                )
                .put("peak_g", lifecycleNumber(session.peakG, 0.0, 100.0))
                .put("crash_count", session.crashCount.coerceIn(0, 2_000_000))
                .put("drift_score", session.driftScore.coerceIn(0, 2_000_000))
                .put(
                    "max_drift_angle_deg",
                    lifecycleNumber(session.maxDriftAngleDeg, 0.0, 100.0)
                )
                .put("total_shifts", session.totalShifts.coerceIn(0, 2_000_000))
                .put("abuse_score", session.abuseScore.coerceIn(0, 2_000_000))
                .put("shift_score", session.shiftScore.coerceIn(0, 2_000_000))
                .put("automatic", automatic),
            sessionId = session.id
        )
    }

    suspend fun sendDiagnosticReport(connection: ConnectionState): Boolean {
        val errors = JSONArray()
        if (connection.error.isNotBlank()) errors.put(connection.error.take(MAX_TEXT))
        val categories = JSONArray()
            .put("connection")
            .put("application")
        val properties = JSONObject()
            .put("summary", "User-submitted DriveLab diagnostic report")
            .put("categories", categories)
            .put("error_count", if (connection.error.isBlank()) 0 else 1)
            .put("connection_state", connection.statusText.take(80))
            .put("database_ok", applicationContext.filesDir.canRead())
            .put("recent_errors", errors)

        enqueue(
            eventType = "diagnostic_report",
            properties = properties,
            allowWhenDisabled = true
        )
        recordFeatureCompleted("diagnostic_report", "submitted")
        return flush(force = true)
    }

    suspend fun flush(force: Boolean = false): Boolean = flushMutex.withLock {
        withContext(Dispatchers.IO) {
            if (serverUrl.isBlank()) {
                publishState(lastMessage = "Lifecycle server is not configured.")
                return@withContext false
            }
            if (!operationalEnabled && !force) return@withContext false
            val batch = firstBatch()
            if (batch.length() == 0) {
                publishState(
                    registered = preferences.getBoolean("registered", false),
                    pendingEvents = 0,
                    lastMessage = "Lifecycle queue is up to date."
                )
                return@withContext true
            }

            publishState(busy = true, pendingEvents = pendingCount(), lastMessage = "Uploading lifecycle events…")
            runCatching {
                registerIdentity()
                val timestamp = System.currentTimeMillis() / 1000L
                val nonce = UUID.randomUUID().toString()
                val canonical = lifecycleCanonicalJson(batch)
                val payloadHash = sha256Hex(canonical.toByteArray(Charsets.UTF_8))
                val message = "lifecycle_batch:$payloadHash|${identity.installationId}|$timestamp|$nonce|$appVersion"
                val response = postJson(
                    "/v1/lifecycle/batch",
                    JSONObject()
                        .put("installation_id", identity.installationId)
                        .put("timestamp", timestamp)
                        .put("nonce", nonce)
                        .put("app_version", appVersion)
                        .put("events", batch)
                        .put("proof_signature", identity.signProof(message))
                )
                val accepted = response.optInt("accepted", 0)
                val duplicates = response.optInt("duplicates", 0)
                require(accepted + duplicates == batch.length()) {
                    "The lifecycle server did not account for every event."
                }
                removeFirst(batch.length())
                preferences.edit().putLong("lastUploadAtMs", System.currentTimeMillis()).apply()
                publishState(
                    registered = true,
                    pendingEvents = pendingCount(),
                    busy = false,
                    lastUploadAtMs = System.currentTimeMillis(),
                    lastMessage = "Lifecycle upload complete: $accepted accepted, $duplicates duplicate."
                )
                true
            }.getOrElse { error ->
                publishState(
                    busy = false,
                    pendingEvents = pendingCount(),
                    lastMessage = "Lifecycle upload deferred: ${error.message?.take(180) ?: "unknown error"}"
                )
                false
            }
        }
    }

    private fun registerIdentity() {
        val timestamp = System.currentTimeMillis() / 1000L
        val nonce = UUID.randomUUID().toString()
        val keyHash = identity.publicKeySha256()
        val message = "lifecycle_register|${identity.installationId}|$timestamp|$nonce|$appVersion|$keyHash"
        val response = postJson(
            "/v1/lifecycle/register",
            JSONObject()
                .put("installation_id", identity.installationId)
                .put("device_public_key", identity.publicKeyBase64())
                .put("timestamp", timestamp)
                .put("nonce", nonce)
                .put("app_version", appVersion)
                .put("proof_signature", identity.signProof(message))
        )
        require(response.optBoolean("registered", false)) {
            "Lifecycle identity registration was not accepted."
        }
        preferences.edit()
            .putBoolean("registered", true)
            .putString("registeredEdition", response.optString("edition", "free"))
            .apply()
    }

    private fun enqueue(
        eventType: String,
        properties: JSONObject,
        sessionId: String = appSessionId,
        allowWhenDisabled: Boolean = false
    ) {
        if (!operationalEnabled && !allowWhenDisabled) return
        val event = JSONObject()
            .put("event_id", UUID.randomUUID().toString())
            .put("event_type", eventType)
            .put("occurred_at", System.currentTimeMillis() / 1000L)
            .put("session_id", sessionId.take(128))
            .put("properties", properties)
        synchronized(queueLock) {
            val queue = loadQueue()
            queue.put(event)
            while (queue.length() > MAX_LOCAL_EVENTS) {
                val trimmed = JSONArray()
                for (index in 1 until queue.length()) trimmed.put(queue.opt(index))
                saveQueue(trimmed)
                publishState(pendingEvents = trimmed.length())
                return
            }
            saveQueue(queue)
            publishState(pendingEvents = queue.length())
        }
    }

    private fun firstBatch(): JSONArray = synchronized(queueLock) {
        val source = loadQueue()
        JSONArray().also { target ->
            for (index in 0 until minOf(source.length(), MAX_BATCH_EVENTS)) {
                target.put(source.opt(index))
            }
        }
    }

    private fun removeFirst(count: Int) = synchronized(queueLock) {
        val source = loadQueue()
        val target = JSONArray()
        for (index in count.coerceAtLeast(0) until source.length()) {
            target.put(source.opt(index))
        }
        saveQueue(target)
    }

    private fun pendingCount(): Int = synchronized(queueLock) { loadQueue().length() }

    private fun loadQueue(): JSONArray = runCatching {
        JSONArray(preferences.getString("pendingEvents", "[]") ?: "[]")
    }.getOrDefault(JSONArray())

    private fun saveQueue(queue: JSONArray) {
        preferences.edit().putString("pendingEvents", queue.toString()).apply()
    }

    private fun publishState(
        configured: Boolean = _state.value.configured,
        enabled: Boolean = operationalEnabled,
        featureUsageEnabled: Boolean = featureUsageEnabled,
        sessionSummariesEnabled: Boolean = sessionSummariesEnabled,
        registered: Boolean = _state.value.registered,
        pendingEvents: Int = _state.value.pendingEvents,
        busy: Boolean = _state.value.busy,
        lastUploadAtMs: Long = preferences.getLong("lastUploadAtMs", _state.value.lastUploadAtMs),
        lastMessage: String = _state.value.lastMessage
    ) {
        _state.value = LifecycleTelemetryState(
            configured = configured,
            enabled = enabled,
            featureUsageEnabled = featureUsageEnabled,
            sessionSummariesEnabled = sessionSummariesEnabled,
            registered = registered,
            pendingEvents = pendingEvents,
            busy = busy,
            lastUploadAtMs = lastUploadAtMs,
            lastMessage = lastMessage
        )
    }

    private fun postJson(path: String, body: JSONObject): JSONObject {
        require(serverUrl.startsWith("https://") || BuildConfig.DEBUG) {
            "The lifecycle server must use HTTPS."
        }
        val connection = URL(serverUrl + path).openConnection() as HttpURLConnection
        connection.apply {
            requestMethod = "POST"
            connectTimeout = 10_000
            readTimeout = 15_000
            doOutput = true
            useCaches = false
            setRequestProperty("Content-Type", "application/json; charset=utf-8")
            setRequestProperty("Accept", "application/json")
        }
        try {
            connection.outputStream.use { stream ->
                stream.write(body.toString().toByteArray(Charsets.UTF_8))
            }
            val status = connection.responseCode
            val text = (
                if (status in 200..299) connection.inputStream else connection.errorStream
                )?.bufferedReader(Charsets.UTF_8)?.use { it.readText() }.orEmpty()
            val json = runCatching { JSONObject(text) }.getOrDefault(JSONObject())
            if (status !in 200..299) {
                val code = json.optString("code", "http_$status")
                val detail = json.optString("detail", "Lifecycle request failed with HTTP $status.")
                throw IllegalStateException("$code: $detail")
            }
            return json
        } finally {
            connection.disconnect()
        }
    }

    private fun sha256Hex(value: ByteArray): String = MessageDigest
        .getInstance("SHA-256")
        .digest(value)
        .joinToString("") { "%02x".format(it) }
}
