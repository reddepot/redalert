package com.zaifears.locreminder

import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import android.location.LocationManager
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "com.zaifears.locreminder/alarms"

    /** Held across the sound-picker activity result, then completed. */
    private var pendingSoundResult: MethodChannel.Result? = null
    private var pendingCatalogueResult: MethodChannel.Result? = null
    private var previewPlayer: android.media.MediaPlayer? = null
    private val previewHandler = android.os.Handler(android.os.Looper.getMainLooper())
    private val previewFocus by lazy { TransientAudioFocus(this) { stopPreview() } }
    private val previewTimeout = Runnable { stopPreview() }

    private companion object {
        const val REQUEST_PICK_RINGTONE = 8101
        const val REQUEST_PICK_AUDIO_FILE = 8102
        const val REQUEST_PICK_CATALOGUE = 8103

        /**
         * How long to wait for a fresh fix before falling back to the cached
         * one. Long enough for GPS to come up from cold outdoors, short enough
         * that the button never feels stuck.
         */
        const val FRESH_FIX_TIMEOUT_MILLIS = 8_000L
    }

    private val mapPositions by lazy { MapPositionStream(this) }
    private val voicePreviewController get() = VoicePreviewSession.controller(applicationContext)
    private val offlinePacks by lazy { OfflineMapPacks(this) }

    override fun onDestroy() {
        stopPreview()
        mapPositions.onCancel(null)
        if (isFinishing) VoicePreviewSession.cancelIfCreated("activity_finished")
        offlinePacks.close()
        super.onDestroy()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.zaifears.locreminder/maps").setMethodCallHandler { call, result ->
            when (call.method) {
                "status", "setEnabled", "retry", "delete" -> offlinePacks.handle(call.method, call.argument<Boolean>("enabled"), result)
                "tile" -> offlinePacks.tile(call.argument<Int>("z") ?: -1, call.argument<Int>("x") ?: -1, call.argument<Int>("y") ?: -1, result)
                else -> result.notImplemented()
            }
        }

        io.flutter.plugin.common.EventChannel(flutterEngine.dartExecutor.binaryMessenger, "com.zaifears.locreminder/positions").setStreamHandler(mapPositions)

        // Create notification channels up front so "Location Alarms" is
        // immediately visible in system notification settings during onboarding,
        // before any alarm has rung.
        NotificationHelper.ensureAlarmChannel(this)
        NotificationHelper.ensureWatchChannel(this)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler { call, result ->
            try {
            when (call.method) {
                "syncSelectedAlarms" -> {
                    try {
                        val (ids, active) = validatedAlarmRows(call)
                        ArrivalState(this).forgetMany(ids)
                        AlarmStore(this).replaceSelected(ids, active)
                        result.success(true)
                    } catch (_: AlarmStorageCorrupt) {
                        result.error("STORE_CORRUPT", "La copie de surveillance doit être réparée.", null)
                    } catch (_: Exception) {
                        result.error("BATCH_FAILED", "Synchronisation du lot impossible.", null)
                    }
                }
                "pickCatalogue" -> {
                    if (pendingCatalogueResult != null) {
                        result.error("BUSY", "Un sélecteur est déjà ouvert.", null)
                    } else {
                        pendingCatalogueResult = result
                        try {
                            @Suppress("DEPRECATION")
                            startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                                addCategory(Intent.CATEGORY_OPENABLE)
                                type = "*/*"
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            }, REQUEST_PICK_CATALOGUE)
                        } catch (_: Exception) {
                            pendingCatalogueResult = null
                            result.error("PICKER_UNAVAILABLE", "Sélecteur de fichier indisponible.", null)
                        }
                    }
                }
                "addAlarm" -> {
                    val id = call.argument<String>("id")
                    val lat = call.argument<Double>("latitude")
                    val lng = call.argument<Double>("longitude")
                    val radius = call.argument<Double>("radius")
                    val label = call.argument<String>("label") ?: "Destination"
                    // Absent from an older Dart side, and empty is the right
                    // reading of absent: fire once, then delete.
                    val repeatDays = call.argument<List<Int>>("repeatDays")
                        ?.filter { it in 1..7 }
                        ?.toSet()
                        ?: emptySet()
                    if (id == null || lat == null || lng == null || radius == null) {
                        result.error("INVALID_ARGS", "id, latitude, longitude and radius are required", null)
                    } else {
                        try {
                            AlarmValidation.requireValid(id, label, lat, lng, radius)
                        } catch (_: IllegalArgumentException) {
                            result.error("INVALID_ARGS", "Point invalide : coordonnées, rayon ou libellé.", null)
                            return@setMethodCallHandler
                        }
                        // Always reset arrival tracking for this ID so that creating or
                        // editing an alarm evaluates arrival fresh with no stale suppression.
                        ArrivalState(this).forget(id)
                        val everyEntry = call.argument<Boolean>("repeatOnEveryEntry") == true
                        val limit = call.argument<Int>("speedLimitKmh")?.takeIf { it in 1..130 }
                        val department = call.argument<String>("department")?.takeIf { it.isNotBlank() }
                        AlarmStore(this).save(AlarmEntry(id, label, lat, lng, radius, repeatDays, everyEntry, limit, department, call.argument<String>("poiType") ?: "other", call.argument<Double>("travelBearingDegrees")?.takeIf { it.isFinite() && it >= 0 && it < 360 }))
                        result.success(true)
                    }
                }
                "removeAlarm" -> {
                    val id = call.argument<String>("id")
                    if (id == null) {
                        result.error("INVALID_ARGS", "id is required", null)
                    } else {
                        ArrivalState(this).forget(id)
                        AlarmStore(this).remove(id)
                        result.success(true)
                    }
                }
                "removeAllAlarms" -> {
                    ArrivalState(this).forgetAllExcept(emptyList())
                    AlarmStore(this).clear()
                    result.success(true)
                }
                "getActiveAlarmIds" -> result.success(AlarmStore(this).loadAll().map { it.id })
                "getAlarmState" -> {
                    val snapshot = AlarmStore(this).snapshot()
                    result.success(mapOf("activeIds" to snapshot.entries.map { it.id },
                        "receipts" to snapshot.receipts, "corrupt" to snapshot.corrupt,
                        "invalidRecords" to snapshot.invalidRecords))
                }
                "acknowledgeAlarmReceipts" -> {
                    val receipts = call.argument<Map<String, String>>("receipts") ?: emptyMap()
                    require(receipts.size <= AlarmStore.MAX_RECEIPTS)
                    AlarmStore(this).acknowledge(receipts)
                    result.success(true)
                }
                "repairAlarmStore" -> {
                    val (ids, active) = validatedAlarmRows(call)
                    AlarmStore(this).repairSelected(ids, active)
                    ArrivalState(this).forgetMany(ids)
                    result.success(true)
                }
                // Replaces the geolocator plugin, which pulled in Play
                // Services transitively.
                "isLocationEnabled" -> {
                    val manager = getSystemService(LocationManager::class.java)
                    val enabled = manager != null && (
                        runCatching { manager.isProviderEnabled(LocationManager.GPS_PROVIDER) }.getOrDefault(false) ||
                            runCatching { manager.isProviderEnabled(LocationManager.NETWORK_PROVIDER) }.getOrDefault(false)
                        )
                    result.success(enabled)
                }
                "openLocationSettings" -> {
                    try {
                        startActivity(
                            Intent(Settings.ACTION_LOCATION_SOURCE_SETTINGS)
                                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                        )
                        result.success(true)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                "setDrivingScreen" -> {
                    if (call.argument<Boolean>("awake") == true) window.addFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    else window.clearFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    result.success(null)
                }
                "getLastKnownLocation" -> result.success(lastKnownLocation())
                "getCurrentLocation" -> currentLocation(result)
                "previewPassageVoice" -> {
                    val asset = SpokenPassagePolicy.asset(call.argument<String>("poiType") ?: "fixedCamera", "entered", 300.0)
                    val delay = call.argument<Number>("delayMillis")?.toLong() ?: 0L
                    if (delay !in 0..5000) result.error("delay", "Délai d’essai invalide", null)
                    else if (delay > 0 && Build.VERSION.SDK_INT >= 35 && !LocationWatchService.isWatching)
                        result.error("watch_inactive", "Activez la surveillance de vos lieux avant cet essai en veille.", null)
                    else result.success(voicePreviewController.start(asset, delay))
                }
                "getVoicePreviewStatus" -> result.success(voicePreviewController.snapshot())
                "stopPassageVoicePreview" -> {
                    val reason = call.argument<String>("reason")
                        ?.takeIf { it in setOf("user_cancelled", "view_disposed") } ?: "cancelled"
                    voicePreviewController.cancel(reason); result.success(null)
                }
                "setPassageVoice" -> { PassageVoice.setEnabled(this, call.argument<Boolean>("enabled") == true); result.success(null) }
                "getPassageStatus" -> {
                    val status = LocationWatchService.passageStatus
                    result.success(mapOf(
                        "audio" to LocationWatchService.passageAudioEnabled(this),
                        "voice" to PassageVoice.enabled(this),
                        "voiceError" to PassageVoice.lastError,
                        "speedLimitKmh" to status?.takeIf { it.approachAligned }?.let { AlarmStore(this).getById(it.id)?.speedLimitKmh },
                        "level2" to LocationWatchService.level2Enabled(this),
                        "speedAlerts" to LocationWatchService.speedAlertsEnabled(this),
                        "label" to status?.label,
                        "stage" to status?.let { LocationWatchService.stageLabel(it.stage) },
                        "stageCode" to status?.stage,
                        "poiType" to status?.let { AlarmStore(this).getById(it.id)?.poiType },
                        "fixAgeMillis" to status?.let { android.os.SystemClock.elapsedRealtime() - it.elapsed },
                        "distance" to status?.distance,
                        "accuracy" to status?.accuracy,
                        "stale" to (status == null || android.os.SystemClock.elapsedRealtime() - status.elapsed > 5000),
                    ))
                }
                "setPassageLevel2" -> {
                    try {
                        LocationWatchService.setLevel2(this, call.argument<Boolean>("enabled") == true)
                        result.success(true)
                    } catch (_: Exception) { result.error("storage", "Réglage non enregistré", null) }
                }
                "setSpeedAlerts" -> {
                    try {
                        LocationWatchService.setSpeedAlerts(this, call.argument<Boolean>("enabled") == true)
                        result.success(true)
                    } catch (_: Exception) { result.error("storage", "Réglage non enregistré", null) }
                }
                "setPassageAudio" -> {
                    try {
                        LocationWatchService.setPassageAudio(this, call.argument<Boolean>("enabled") == true)
                        result.success(true)
                    } catch (_: Exception) { result.error("storage", "Réglage non enregistré", null) }
                }
                // Saved map tiles live in the app's own files, not its cache.
                // Android empties the cache directory whenever it wants the
                // space and whenever the user taps "clear cache" — neither of
                // which should be able to take the map for tomorrow's journey
                // with it. Bounded and clearable from Settings instead.
                "getOfflineMapDirectory" -> {
                    val directory = java.io.File(filesDir, "map_tiles")
                    result.success(
                        if (directory.exists() || directory.mkdirs()) {
                            directory.absolutePath
                        } else {
                            null
                        },
                    )
                }
                "isIgnoringBatteryOptimizations" -> {
                    val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
                    result.success(powerManager.isIgnoringBatteryOptimizations(packageName))
                }
                "requestIgnoreBatteryOptimizations" -> {
                    try {
                        val intent = Intent(
                            Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                            Uri.parse("package:$packageName"),
                        )
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                // Android 14+ gates full-screen intents behind a separate
                // capability, and Xiaomi (MIUI / HyperOS, e.g. Redmi Note 12 4G)
                // additionally gates lock-screen and background pop-up display
                // behind custom AppOps (10020 & 10021) in com.miui.securitycenter.
                "canUseFullScreenIntent" -> {
                    result.success(OemHelper.canUseFullScreenAlarm(this))
                }
                "requestFullScreenIntentPermission" -> {
                    result.success(OemHelper.openFullScreenIntentSettings(this))
                }
                "openLockScreenSettings" -> {
                    result.success(OemHelper.openLockScreenPermissionSettings(this))
                }
                "openAlarmChannelSettings" -> {
                    result.success(OemHelper.openAlarmChannelSettings(this))
                }
                // The watch service is what makes triggering dependable; the
                // Dart layer keeps it running exactly while alarms are armed.
                "startLocationWatch" -> {
                    try {
                        ContextCompat.startForegroundService(
                            this,
                            Intent(this, LocationWatchService::class.java),
                        )
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("WATCH_START_FAILED", e.message, null)
                    }
                }
                "stopLocationWatch" -> {
                    startService(
                        Intent(this, LocationWatchService::class.java).apply {
                            action = LocationWatchService.ACTION_STOP
                        },
                    )
                    result.success(true)
                }
                "getWatchStatus" -> result.success(LocationWatchService.watchStatus(this))
                "isLocationWatchRunning" -> result.success(LocationWatchService.isWatching)
                "getDeviceInfo" -> result.success(
                    mapOf(
                        "manufacturer" to (android.os.Build.MANUFACTURER ?: ""),
                        "brand" to (android.os.Build.BRAND ?: ""),
                        "model" to (android.os.Build.MODEL ?: ""),
                        "sdkInt" to android.os.Build.VERSION.SDK_INT,
                        "needsExtraSetup" to OemHelper.needsExtraSetup(),
                    ),
                )
                "openAutoStartSettings" -> result.success(OemHelper.openAutoStartSettings(this))
                "openAppSettings" -> result.success(OemHelper.openAppSettings(this))
                // Fires the real alarm path after a delay so the user can lock
                // the screen and confirm it breaks through from a locked,
                // idle state — the condition that actually matters.
                "triggerTestAlarm" -> {
                    val delaySeconds = call.argument<Int>("delaySeconds") ?: 10
                    val testIntent = Intent(this, TestAlarmReceiver::class.java).apply {
                        putExtra(AlarmForegroundService.EXTRA_LABEL, getString(R.string.test_alarm_label))
                    }
                    val pendingIntent = PendingIntent.getBroadcast(
                        this,
                        TestAlarmReceiver.REQUEST_CODE,
                        testIntent,
                        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                    )
                    val alarmManager = getSystemService(android.app.AlarmManager::class.java)
                    if (alarmManager != null) {
                        val triggerAtMillis = android.os.SystemClock.elapsedRealtime() + delaySeconds * 1000L
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && alarmManager.canScheduleExactAlarms()) {
                            alarmManager.setExactAndAllowWhileIdle(
                                android.app.AlarmManager.ELAPSED_REALTIME_WAKEUP,
                                triggerAtMillis,
                                pendingIntent,
                            )
                        } else {
                            alarmManager.setAndAllowWhileIdle(
                                android.app.AlarmManager.ELAPSED_REALTIME_WAKEUP,
                                triggerAtMillis,
                                pendingIntent,
                            )
                        }
                        result.success(true)
                    } else {
                        result.error("ALARM_UNAVAILABLE", "AlarmManager not available", null)
                    }
                }
                "getAlarmSound" -> {
                    val settings = AlarmSettings(this)
                    result.success(
                        mapOf(
                            "uri" to settings.soundUri()?.toString(),
                            "name" to settings.soundName(),
                            "vibrate" to settings.vibrationEnabled(),
                        ),
                    )
                }
                "pickAlarmRingtone" -> startSoundPicker(result, ringtonePicker(), REQUEST_PICK_RINGTONE)
                "pickAlarmAudioFile" -> startSoundPicker(result, audioFilePicker(), REQUEST_PICK_AUDIO_FILE)
                "resetAlarmSound" -> {
                    AlarmSettings(this).setSound(null, null)
                    result.success(true)
                }
                "setAlarmVibration" -> {
                    AlarmSettings(this).setVibrationEnabled(call.argument<Boolean>("enabled") ?: true)
                    result.success(true)
                }
                "previewAlarmSound" -> {
                    playPreview()
                    result.success(true)
                }
                "stopAlarmSoundPreview" -> {
                    stopPreview()
                    result.success(true)
                }
                "setDistanceUnit" -> {
                    val miles = call.argument<Boolean>("miles") ?: false
                    AlarmSettings(this).setUseMiles(miles)
                    if (LocationWatchService.isWatching) {
                        runCatching {
                            ContextCompat.startForegroundService(
                                this,
                                Intent(this, LocationWatchService::class.java),
                            )
                        }
                    }
                    result.success(true)
                }
                "isAlarmRinging" -> result.success(AlarmForegroundService.isRinging)
                "stopAlarm" -> {
                    startService(
                        Intent(this, AlarmForegroundService::class.java).apply {
                            action = AlarmForegroundService.ACTION_STOP
                        },
                    )
                    result.success(null)
                }
                else -> result.notImplemented()
            }
            } catch (_: AlarmStorageCorrupt) {
                result.error("STORE_CORRUPT", "La copie de surveillance doit être réparée.", null)
            } catch (_: Exception) {
                result.error("NATIVE_OPERATION_FAILED", "Opération native impossible. Les données sont conservées.", null)
            }
        }
    }

    private fun validatedAlarmRows(call: io.flutter.plugin.common.MethodCall): Pair<Set<String>, List<AlarmEntry>> {
        val rows = call.argument<List<Map<String, Any?>>>("alarms") ?: error("Missing alarms")
        require(rows.size in 0..50000)
        val ids = mutableSetOf<String>()
        val active = rows.mapNotNull { row ->
            val id = row["id"] as? String ?: error("Missing id")
            val label = row["label"] as? String ?: error("Missing label")
            val lat = (row["latitude"] as? Number)?.toDouble() ?: error("Missing latitude")
            val lon = (row["longitude"] as? Number)?.toDouble() ?: error("Missing longitude")
            val radius = (row["radius"] as? Number)?.toDouble() ?: error("Missing radius")
            val enabled = row["isActive"] as? Boolean ?: error("Missing activation")
            require(ids.add(id))
            AlarmValidation.requireValid(id, label, lat, lon, radius)
            val days = (row["repeatDays"] as? List<*>)?.mapNotNull { (it as? Number)?.toInt() }?.filter { it in 1..7 }?.toSet() ?: emptySet()
            val limit = (row["speedLimitKmh"] as? Number)?.toInt()?.takeIf { it in 1..130 }
            val department = (row["department"] as? String)?.takeIf { it.isNotBlank() }
            if (enabled) AlarmEntry(id, label, lat, lon, radius, days, row["repeatOnEveryEntry"] == true, limit, department, row["poiType"] as? String ?: "other", (row["travelBearingDegrees"] as? Number)?.toDouble()?.takeIf { it.isFinite() && it >= 0 && it < 360 }) else null
        }
        return ids to active
    }

    // ---------------------------------------------------------------- sound

    private fun ringtonePicker(): Intent {
        return Intent(RingtoneManager.ACTION_RINGTONE_PICKER).apply {
            putExtra(RingtoneManager.EXTRA_RINGTONE_TYPE, RingtoneManager.TYPE_ALARM)
            putExtra(RingtoneManager.EXTRA_RINGTONE_TITLE, "Choose an alarm sound")
            putExtra(RingtoneManager.EXTRA_RINGTONE_SHOW_DEFAULT, true)
            putExtra(RingtoneManager.EXTRA_RINGTONE_SHOW_SILENT, false)
            putExtra(
                RingtoneManager.EXTRA_RINGTONE_EXISTING_URI,
                AlarmSettings(this@MainActivity).soundUri(),
            )
        }
    }

    private fun audioFilePicker(): Intent {
        return Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "audio/*"
            // Lets the picker offer formats whose MIME type some providers
            // report inconsistently, mp3 among them.
            putExtra(
                Intent.EXTRA_MIME_TYPES,
                arrayOf("audio/mpeg", "audio/mp4", "audio/ogg", "audio/x-wav", "audio/flac", "audio/*"),
            )
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
    }

    private fun startSoundPicker(result: MethodChannel.Result, intent: Intent, requestCode: Int) {
        if (pendingSoundResult != null) {
            result.error("PICKER_BUSY", "A sound picker is already open", null)
            return
        }
        try {
            pendingSoundResult = result
            startActivityForResult(intent, requestCode)
        } catch (e: Exception) {
            pendingSoundResult = null
            result.error("PICKER_UNAVAILABLE", e.message, null)
        }
    }

    @Deprecated("Deprecated in Java")
    @Suppress("DEPRECATION")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)

        if (requestCode == REQUEST_PICK_CATALOGUE) {
            val pending = pendingCatalogueResult ?: return
            pendingCatalogueResult = null
            val uri = data?.data
            if (resultCode != RESULT_OK || uri == null) {
                pending.success(null)
                return
            }
            Thread {
                try {
                    val bytes = contentResolver.openInputStream(uri)?.use { input ->
                        val output = java.io.ByteArrayOutputStream()
                        val buffer = ByteArray(8192)
                        while (true) {
                            val count = input.read(buffer)
                            if (count < 0) break
                            require(output.size() + count <= 8 * 1024 * 1024)
                            output.write(buffer, 0, count)
                        }
                        output.toByteArray()
                    } ?: error("Fichier illisible")
                    val text = bytes.toString(Charsets.UTF_8)
                    runOnUiThread { pending.success(text) }
                } catch (_: Exception) {
                    runOnUiThread { pending.error("READ_FAILED", "Fichier illisible ou supérieur à 8 Mo.", null) }
                }
            }.start()
            return
        }

        if (requestCode != REQUEST_PICK_RINGTONE && requestCode != REQUEST_PICK_AUDIO_FILE) return

        val pending = pendingSoundResult ?: return
        pendingSoundResult = null

        if (resultCode != RESULT_OK) {
            pending.success(null)
            return
        }

        val uri: Uri? = if (requestCode == REQUEST_PICK_RINGTONE) {
            @Suppress("DEPRECATION")
            data?.getParcelableExtra(RingtoneManager.EXTRA_RINGTONE_PICKED_URI)
        } else {
            data?.data
        }

        if (uri == null) {
            // The system picker returns no URI when "Default"/"None" is chosen.
            AlarmSettings(this).setSound(null, null)
            pending.success(null)
            return
        }

        // A document URI is only readable in future processes if we take a
        // persistable grant now — without this the alarm would fall silent
        // after the next reboot.
        if (requestCode == REQUEST_PICK_AUDIO_FILE) {
            try {
                contentResolver.takePersistableUriPermission(
                    uri,
                    Intent.FLAG_GRANT_READ_URI_PERMISSION,
                )
            } catch (_: SecurityException) {
                pending.error("AUDIO_PERMISSION_NOT_PERSISTED",
                    "L’accès durable à ce fichier audio est refusé. Le son précédent est conservé.", null)
                return
            }
        }

        val name = AlarmSettings.displayNameFor(this, uri)
        AlarmSettings(this).setSound(uri, name)
        pending.success(mapOf("uri" to uri.toString(), "name" to name))
    }

    private fun playPreview() {
        stopPreview()
        val uri = AlarmSettings(this).resolvePlayableUri() ?: return
        try {
            val player = android.media.MediaPlayer()
            previewPlayer = player
            player.setAudioAttributes(android.media.AudioAttributes.Builder()
                .setUsage(android.media.AudioAttributes.USAGE_ALARM)
                .setContentType(android.media.AudioAttributes.CONTENT_TYPE_SONIFICATION).build())
            player.setOnPreparedListener {
                if (previewPlayer !== player) return@setOnPreparedListener
                previewHandler.removeCallbacks(previewTimeout)
                try {
                    if (!previewFocus.acquire()) { stopPreview(); return@setOnPreparedListener }
                    player.start()
                    previewHandler.postDelayed(previewTimeout, 15_000)
                } catch (_: Exception) { stopPreview() }
            }
            player.setOnCompletionListener { if (previewPlayer === player) stopPreview() }
            player.setOnErrorListener { _, _, _ ->
                if (previewPlayer === player) stopPreview()
                true
            }
            player.setDataSource(this, uri)
            player.isLooping = false
            previewHandler.postDelayed(previewTimeout, 5_000)
            player.prepareAsync()
        } catch (_: Exception) {
            stopPreview()
        }
    }

    private fun stopPreview() {
        previewHandler.removeCallbacks(previewTimeout)
        val previous = previewPlayer
        previewPlayer = null
        try { previous?.release() } catch (_: Exception) { /* Already released. */ }
        previewFocus.release()
    }

    override fun onStop() {
        // Never let a preview keep playing once the screen is gone.
        stopPreview()
        super.onStop()
    }

    // ------------------------------------------------------------- location

    /**
     * Most recent fix known to the platform, used to centre the map. Returns
     * null rather than waiting for a fresh fix — the map has a sensible
     * default, and blocking the UI on GPS would be worse than showing it.
     */
    private fun lastKnownLocation(): Map<String, Any?>? {
        val manager = getSystemService(LocationManager::class.java) ?: return null

        val providers = buildList {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) add(LocationManager.FUSED_PROVIDER)
            add(LocationManager.GPS_PROVIDER)
            add(LocationManager.NETWORK_PROVIDER)
            add(LocationManager.PASSIVE_PROVIDER)
        }

        var best: android.location.Location? = null
        for (provider in providers) {
            val location = try {
                manager.getLastKnownLocation(provider)
            } catch (e: SecurityException) {
                return null
            } catch (e: Exception) {
                null
            } ?: continue

            if (best == null || location.time > best.time) best = location
        }

        return (best ?: return null).asMap()
    }

    private fun android.location.Location.asMap(): Map<String, Any?> = positionPayload()

    /**
     * Asks for a fresh fix, falling back to the cached one if nothing arrives
     * in time.
     *
     * [lastKnownLocation] alone is not enough for "centre on my location":
     * right after a boot or a fresh install the platform holds no fix at all
     * and it returns null, leaving the button doing nothing at all — and when
     * it does return something, that something can be badly out of date.
     */
    private fun currentLocation(result: MethodChannel.Result) {
        val manager = getSystemService(LocationManager::class.java)
        if (manager == null) {
            result.success(null)
            return
        }

        val providers = buildList {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) add(LocationManager.FUSED_PROVIDER)
            add(LocationManager.GPS_PROVIDER)
            add(LocationManager.NETWORK_PROVIDER)
        }.filter { provider ->
            runCatching { manager.isProviderEnabled(provider) }.getOrDefault(false)
        }

        if (providers.isEmpty()) {
            result.success(lastKnownLocation())
            return
        }

        val handler = android.os.Handler(android.os.Looper.getMainLooper())
        var settled = false
        // A one-slot holder rather than a `var`: settle() has to unregister
        // the listener, but the listener has to call settle(), and Kotlin
        // won't smart-cast a var captured by a closure back to non-null.
        val registered = arrayOfNulls<android.location.LocationListener>(1)

        fun settle(value: Map<String, Any?>?) {
            if (settled) return
            settled = true
            registered[0]?.let { runCatching { manager.removeUpdates(it) } }
            result.success(value)
        }

        val giveUp = Runnable { settle(lastKnownLocation()) }

        val listener = object : android.location.LocationListener {
            override fun onLocationChanged(location: android.location.Location) {
                handler.removeCallbacks(giveUp)
                settle(location.asMap())
            }

            // Explicit for API 23; the interface defaults only exist from 30.
            @Deprecated("Deprecated in Java")
            override fun onStatusChanged(provider: String?, status: Int, extras: android.os.Bundle?) = Unit

            override fun onProviderEnabled(provider: String) = Unit

            override fun onProviderDisabled(provider: String) = Unit
        }
        registered[0] = listener

        try {
            for (provider in providers) {
                manager.requestLocationUpdates(provider, 0L, 0f, listener, mainLooper)
            }
            handler.postDelayed(giveUp, FRESH_FIX_TIMEOUT_MILLIS)
        } catch (e: SecurityException) {
            settle(null)
        } catch (e: Exception) {
            settle(lastKnownLocation())
        }
    }
}
