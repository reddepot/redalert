package com.zaifears.locreminder

import android.app.Notification
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.location.LocationRequest
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.IBinder
import android.os.SystemClock
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import java.util.Calendar

/**
 * Actively watches the device's location while any alarm is armed, and rings
 * the alarm on arrival.
 *
 * This is the whole detection mechanism, deliberately. Play Services
 * geofencing was tried first and is not dependable for an alarm: once the app
 * goes idle, Doze and App Standby defer the transition broadcast, so it can
 * arrive minutes late — or not until the user next opens the app, long after
 * the stop. Holding a foreground service keeps the process out of that idle
 * state, which is what makes the alarm land on time.
 *
 * Uses the platform [LocationManager] rather than Play Services' fused
 * client, so the app carries no proprietary dependency and works on devices
 * with no Google services at all — Huawei's HMS phones and de-Googled ROMs
 * included. On Android 12+ the platform exposes its own fused provider,
 * giving the same sensor-blended efficiency without the dependency.
 *
 * Nothing here touches the network. GNSS is a receive-only radio: the
 * satellites broadcast, the phone listens, and no data connection is involved
 * at any point. That is what lets the alarm ring on a bus with no signal —
 * only the map tiles and the place search need the internet, and neither is
 * part of detection.
 */
class LocationWatchService : Service() {
    private val voice by lazy { PassageVoice(this) }
    private var voiceSpeedMps: Double? = null
    private var voiceStatuses = emptyMap<String, PassageTracker.Status>()
    private val passageTracker = PassageCoordinator()
    private val passageState by lazy { PassageStateStore(this) }
    private var passageTone: android.media.ToneGenerator? = null
    private var passageToneLoud: android.media.ToneGenerator? = null
    private val toneFocus: TransientAudioFocus by lazy { TransientAudioFocus(this) { toneSequence.cancel() } }
    private val toneSequence: PassageToneSequence by lazy {
        PassageToneSequence(
            post = { task, delay -> handler.postDelayed(task, delay); Unit },
            remove = { handler.removeCallbacks(it) },
            requestFocus = { toneFocus.acquire() },
            releaseFocus = { toneFocus.release() },
            play = { id, duration -> selectedTone?.startTone(id, duration) == true },
            stop = { passageTone?.stopTone(); passageToneLoud?.stopTone() },
        )
    }
    private var selectedTone: android.media.ToneGenerator? = null

    /** "96 km/h · limite 80" while the user is over the limit at the point. */
    private var speedNote: String? = null
    private var lastSpeedWarningAt = 0L
    /**
     * Cues already played, per point.
     *
     * Keyed by id because the coordinator reports every point that changed on
     * a fix: a set keyed by stage alone let the second point's approach be
     * swallowed by the first point's.
     */
    private val announcedCues = mutableMapOf<String, MutableSet<String>>()


    private lateinit var locationManager: LocationManager
    private var currentIntervalMillis: Long = FAR_INTERVAL_MILLIS
    private var scheduledEntries: List<AlarmEntry> = emptyList()
    private var nearestLabel: String? = null
    private var nearestDistance: Double? = null

    /** Last text put on the ongoing notification, so identical ones are skipped. */
    private var lastNotificationText: String? = null

    /**
     * When a fix last arrived, on the monotonic clock. Registration succeeding
     * says nothing about fixes actually being delivered — see
     * [onStarvationCheck] for the case where it silently is not.
     */

    /**
     * Whether the platform's own fused provider has been given up on for this
     * run, and the raw providers registered instead. Sticky on purpose: a
     * provider that starved once will starve again, and flapping between the
     * two costs more than staying on the one that works.
     */
    private var escalatedToRawProviders = false

    private val handler by lazy { Handler(mainLooper) }
    private val starvationCheck = Runnable { onStarvationCheck() }
    private val stalePassageCheck = Runnable { updateNotification() }
    private val staleFixCheck = Runnable {
        updateNotification()
        scheduleFixExpiry()
    }

    /**
     * Which alarms have been seen from outside, and so may ring on the way
     * back in. Persisted rather than held in fields: see [ArrivalState] for
     * the missed alarm that taught us the difference.
     */
    private val arrivalState by lazy { ArrivalState(this) }

    private val locationListener = object : LocationListener {
        override fun onLocationChanged(location: Location) = onLocation(location)

        // Declared explicitly rather than relying on the interface defaults,
        // which only exist from API 30 — this app supports API 23.
        @Deprecated("Deprecated in Java")
        override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) = Unit

        // A provider coming back (user re-enabling GPS, leaving airplane mode)
        // is the cue to re-register: the set of usable providers has changed,
        // and on the way in it may have been empty.
        override fun onProviderEnabled(provider: String) {
            requestUpdates(currentIntervalMillis)
        }

        override fun onProviderDisabled(provider: String) {
            requestUpdates(currentIntervalMillis)
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        lastFixElapsed = 0
        locationManager = getSystemService(LocationManager::class.java)
        NotificationHelper.ensureWatchChannel(this)
        passageState.restore(passageTracker)?.forEach { (id, cues) ->
            announcedCues[id] = cues.toMutableSet()
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            WatchdogReceiver.cancel(this)
            stopWatching()
            return START_NOT_STICKY
        }

        // Before anything else, including the decision to stop again.
        //
        // Every caller that can reach this from the background — the
        // watchdog's tick, the boot receiver — arrives via
        // startForegroundService, which is a promise to the system that this
        // notification appears within five seconds. Breaking that promise is
        // not an error code, it is an app kill. So the promise is kept first
        // and the question of whether there is anything to watch asked
        // second: an alarm deleted in the moment between the watchdog reading
        // the store and this running is a race nobody would ever reproduce,
        // and a crash is a poor way to find out about it.
        startForeground(NOTIFICATION_ID, buildNotification())

        // Nothing armed means nothing to watch; don't hold a notification for
        // no reason.
        if (AlarmStore(this).loadAll().isEmpty()) {
            stopWatching()
            return START_NOT_STICKY
        }

        // Deliberately reported even when registration fails. The service is
        // alive either way; what the watchdog needs to know is whether fixes
        // are actually arriving, which isReceivingUpdates carries separately.
        isWatching = true
        applyTodaysSchedule()

        WatchdogReceiver.schedule(this)
        return START_STICKY
    }

    /**
     * Watches only on days something can actually ring.
     *
     * A weekday commute alarm used to hold the GPS open all weekend for an
     * alarm that could not fire until Monday — two days of polling for
     * nothing, which is a large share of what people mean when they say this
     * app drains their battery. On a day when no armed alarm is scheduled the
     * service stays alive, keeps its notification and stays out of Doze, but
     * asks for no fixes at all.
     *
     * Both edges of that are the watchdog's periodic tick, which
     * pokes the service whether or not anything looks wrong precisely so this
     * runs again: the day rolls over in the middle of a run, in both
     * directions, and nothing else would notice. A quarter of an hour either
     * side of midnight is ample for a journey nobody has started yet.
     *
     * Which is why this only re-registers when the state actually has to
     * change. Called periodically for the life of an alarm, tearing
     * the registration down and building it back up each time would restart
     * the receiver's acquisition cycle four times an hour for nothing.
     */
    private fun applyTodaysSchedule() {
        val weekday = todayIsoWeekday()
        val todayStr = today()
        val activeToday = AlarmStore(this).loadAll().filter {
            it.ringsOn(weekday) && !(it.oncePerDay && arrivalState.hasRungToday(it.id, todayStr))
        }
        val definitionsChanged = activeToday != scheduledEntries
        scheduledEntries = activeToday
        val ringsToday = activeToday.isNotEmpty()

        if (ringsToday) {
            if (isDormant) {
                isDormant = false
                // Yesterday's distance is not today's. Clearing it keeps the
                // notification from showing a stale number until the first
                // fix lands.
                nearestLabel = null
                nearestDistance = null
            } else {
                // If the alarm that was previously nearest was disarmed, deleted,
                // or edited so it no longer rings today, clear its cached label
                // so the ongoing notification updates immediately.
                if (nearestLabel != null && activeToday.none { it.label == nearestLabel }) {
                    nearestLabel = null
                    nearestDistance = null
                }
                if (isReceivingUpdates) {
                    if (definitionsChanged) {
                        // A newly armed nearby point must not inherit a distant point's slow cadence.
                        requestUpdates(RECONFIGURE_INTERVAL_MILLIS)
                        return
                    }
                    // Already watching, and watching correctly. The armed count
                    // may have changed, which the notification says when it has
                    // no distance to show yet; nothing else here has.
                    updateNotification()
                    return
                }
            }
            requestUpdates(if (definitionsChanged) RECONFIGURE_INTERVAL_MILLIS else currentIntervalMillis)
            return
        }

        if (isDormant) return

        Log.i(TAG, "Nothing is scheduled to ring today (or all scheduled alarms have already rung); standing down until it is")
        isDormant = true
        handler.removeCallbacks(staleFixCheck)
        isReceivingUpdates = false
        handler.removeCallbacks(starvationCheck)
        runCatching { locationManager.removeUpdates(locationListener) }
        NotificationHelper.clearLocationOffNotification(this)
        updateNotification()
    }

    /**
     * Providers to listen on, best first.
     *
     * Android 12 added a platform fused provider that blends GPS, wifi and
     * sensors the way Play Services does — preferred where present. Below
     * that, GPS and network are used together: network gives cheap coarse
     * fixes indoors, GPS the accuracy needed near the destination.
     *
     * The enabled check matters as much as the availability one. A provider
     * that exists but is switched off delivers nothing, and registering on it
     * regardless left the service claiming to watch while location was off at
     * the OS level — armed, notified, and incapable of ever ringing.
     */
    private fun activeProviders(): List<String> {
        val available = try {
            locationManager.allProviders
        } catch (e: Exception) {
            emptyList<String>()
        }

        if (!escalatedToRawProviders &&
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
            available.contains(LocationManager.FUSED_PROVIDER) &&
            runCatching { locationManager.isProviderEnabled(LocationManager.FUSED_PROVIDER) }
                .getOrDefault(false)
        ) {
            // Fused location is efficient when it works, but some Android
            // builds stop producing fused fixes without a data connection.
            // Listen to raw GPS at the same time so an offline journey never
            // has to wait several minutes for the starvation fallback.
            return listOf(
                LocationManager.FUSED_PROVIDER,
                LocationManager.GPS_PROVIDER,
            ).filter { provider ->
                available.contains(provider) &&
                    runCatching { locationManager.isProviderEnabled(provider) }
                        .getOrDefault(false)
            }
        }

        return listOf(LocationManager.GPS_PROVIDER, LocationManager.NETWORK_PROVIDER)
            .filter { provider ->
                available.contains(provider) &&
                    runCatching { locationManager.isProviderEnabled(provider) }
                        .getOrDefault(false)
            }
    }

    private fun requestUpdates(intervalMillis: Long) {
        val providers = activeProviders()
        if (providers.isEmpty()) {
            // Location is switched off at the OS level. Nothing can be
            // registered, so no callback will ever arrive to recover on its
            // own — the watchdog's retry is the only way back, and until then
            // the user must be told, or they will trust an alarm that cannot
            // possibly ring.
            Log.w(TAG, "No location provider is enabled; cannot watch")
            isReceivingUpdates = false
            handler.removeCallbacks(starvationCheck)
            updateNotification()
            NotificationHelper.postLocationOffNotification(this)
            return
        }

        try {
            locationManager.removeUpdates(locationListener)
            for (provider in providers) {
                register(provider, intervalMillis)
            }

            // Fixes another app has already paid for are free to read, so at
            // the long intervals of a journey's early hours it is worth
            // listening for them: a mapping app running alongside this one
            // keeps the distance current at no cost in battery at all.
            if (intervalMillis >= PASSIVE_PIGGYBACK_FROM_MILLIS &&
                runCatching { locationManager.allProviders }
                    .getOrDefault(emptyList<String>())
                    .contains(LocationManager.PASSIVE_PROVIDER)
            ) {
                register(
                    LocationManager.PASSIVE_PROVIDER,
                    maxOf(NEAR_INTERVAL_MILLIS, intervalMillis / 4),
                )
            }

            currentIntervalMillis = intervalMillis
            requestedIntervalMillis = intervalMillis
            scheduleFixExpiry()
            armStarvationCheck()
            if (!isReceivingUpdates) {
                isReceivingUpdates = true
                NotificationHelper.clearLocationOffNotification(this)
                updateNotification()
            }
        } catch (e: SecurityException) {
            Log.e(TAG, "Location permission missing; stopping watch", e)
            isReceivingUpdates = false
            stopWatching()
        } catch (e: Exception) {
            Log.e(TAG, "Could not request location updates", e)
            isReceivingUpdates = false
        }
    }

    /**
     * Registers one provider, asking for as little power as the current
     * distance allows.
     *
     * Android 12 added a way to say what a request is actually for, and the
     * platform bills accordingly: [LocationRequest.QUALITY_HIGH_ACCURACY]
     * turns the GNSS receiver on for every fix, while
     * [LocationRequest.QUALITY_BALANCED_POWER_ACCURACY] lets it answer from
     * whatever it already knows when that is good enough. Only the last few
     * hundred metres need the expensive answer, so only they ask for it.
     *
     * [LocationRequest.QUALITY_LOW_POWER] is deliberately never used: it is
     * the tier that gives up on GNSS entirely, and on a phone with no data
     * connection — the exact situation this alarm exists for — that is a
     * request for fixes that can never arrive.
     */
    private fun register(provider: String, intervalMillis: Long) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val request = LocationRequest.Builder(intervalMillis)
                .setQuality(
                    if (intervalMillis <= HIGH_ACCURACY_UP_TO_MILLIS) {
                        LocationRequest.QUALITY_HIGH_ACCURACY
                    } else {
                        LocationRequest.QUALITY_BALANCED_POWER_ACCURACY
                    },
                )
                // Do not set a maximum update delay. Location batching allows
                // Android to hold completed fixes and deliver them later,
                // which saves some wakeups but is the wrong trade-off for an
                // alarm whose main failure condition is learning about an
                // arrival several minutes late.
                .build()
            locationManager.requestLocationUpdates(provider, request, mainExecutor, locationListener)
        } else {
            locationManager.requestLocationUpdates(
                provider,
                intervalMillis,
                0f,
                locationListener,
                mainLooper,
            )
        }
    }

    /** Re-checks, after a generous grace period, that fixes are still arriving. */
    private fun armStarvationCheck() {
        handler.removeCallbacks(starvationCheck)
        handler.postDelayed(starvationCheck, starvationDeadlineMillis())
    }

    /**
     * How long silence has to last before it counts as a provider failing
     * rather than a phone indoors.
     *
     * Three missed intervals is the signal, but with a floor under it: near
     * the destination the interval is ten seconds, and a GNSS receiver in a
     * building can easily take longer than thirty to produce anything at all.
     * Treating that as a fault would mean tearing down a working registration
     * every time somebody waits inside a shop.
     */
    private fun starvationDeadlineMillis(): Long {
        // Getting the first fix is the highest-risk period. Waiting the normal
        // multi-interval deadline here can leave an offline alarm unaware of
        // movement for several minutes.
        if (lastFixElapsed == 0L) return FIRST_FIX_STARVATION_MILLIS

        return maxOf(
            currentIntervalMillis * 3,
            MIN_STARVATION_MILLIS,
        ) + STARVATION_GRACE_MILLIS
    }

    /**
     * Handles a registration that succeeded but delivers nothing.
     *
     * The fused provider is the usual cause. It is a blend, and on some
     * builds — de-Googled ROMs especially, but also ordinary phones with no
     * data connection — the half of the blend it prefers is the network one,
     * so with no internet it can sit there answering nothing at all while
     * GPS, which needs no internet whatsoever, would have had a fix in
     * seconds. Falling back to the raw providers is what makes the alarm work
     * on a bus with no signal.
     */
    private fun onStarvationCheck() {
        if (isDormant || !isWatching) return

        val silentFor = SystemClock.elapsedRealtime() - lastFixElapsed
        if (lastFixElapsed != 0L && silentFor < starvationDeadlineMillis()) {
            armStarvationCheck()
            return
        }

        if (!escalatedToRawProviders && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            Log.w(TAG, "No fix in ${silentFor}ms; falling back to GPS and network")
            escalatedToRawProviders = true
            requestUpdates(currentIntervalMillis)
            return
        }

        // Already on the raw providers and still nothing. Deliberately *not*
        // reported as a fault: on the raw providers, prolonged silence is
        // usually a phone that is simply indoors, and saying "location is off"
        // to somebody whose location is plainly on would be a lie that also
        // sends the watchdog into restarting a registration that is working
        // as well as it can. Logged, and left alone.
        Log.w(TAG, "No fix in ${silentFor}ms on raw providers")
        armStarvationCheck()
    }

    private fun scheduleFixExpiry() {
        handler.removeCallbacks(staleFixCheck)
        if (!isWatching || isDormant || lastFixElapsed <= 0) return
        val age = SystemClock.elapsedRealtime() - lastFixElapsed
        val deadline = when {
            age <= STALE_FIX_MILLIS -> STALE_FIX_MILLIS
            currentIntervalMillis > STALE_FIX_MILLIS && age <= currentIntervalMillis * 2 -> currentIntervalMillis * 2
            else -> return
        }
        handler.postDelayed(staleFixCheck, maxOf(1L, deadline - age + 1))
    }

    private fun onLocation(location: Location) {
        if (!isWatching || isDormant) return
        val now = SystemClock.elapsedRealtime()
        val fixTime = location.elapsedRealtimeNanos / 1_000_000
        if (now - fixTime !in 0..15000 || fixTime <= lastFixElapsed || !location.hasAccuracy() ||
            !location.latitude.isFinite() || location.latitude !in -90.0..90.0 ||
            !location.longitude.isFinite() || location.longitude !in -180.0..180.0 ||
            !location.accuracy.isFinite() || location.accuracy < 0) return
        lastFixElapsed = fixTime
        scheduleFixExpiry()
        if (!isReceivingUpdates) {
            isReceivingUpdates = true
            NotificationHelper.clearLocationOffNotification(this)
        }

        val entries = AlarmStore(this).loadAll()
        if (entries.isEmpty()) {
            stopWatching()
            return
        }

        val liveIds = entries.map { it.id }
        arrivalState.forgetAllExcept(liveIds)

        // Named for the day of the week, not the date: [today] is the date,
        // and the two are used a few lines apart.
        val weekday = todayIsoWeekday()
        voiceSpeedMps = if (location.hasSpeed() && location.speed.isFinite() && location.speed in 0f..70f &&
            (Build.VERSION.SDK_INT < 26 || !location.hasSpeedAccuracy() || location.speedAccuracyMetersPerSecond <= 3)) location.speed.toDouble() else null
        val course = if (location.hasBearing() && location.bearing.isFinite() && (voiceSpeedMps ?: 0.0) >= 2 && location.accuracy <= 40 &&
            (Build.VERSION.SDK_INT < 26 || !location.hasBearingAccuracy() || location.bearingAccuracyDegrees <= 30)) location.bearing.toDouble() else null
        val passageEntries = entries.filter { it.repeatOnEveryEntry && it.ringsOn(weekday) }
        val applicable = passageEntries.filter { TravelDirection.applies(it.travelBearingDegrees, course) }.map { it.id }.toSet()
        val entriesById = passageEntries.associateBy { it.id }
        val passagePoints = passageEntries.map {
            PassageTracker.Point(it.id, it.label, it.latitude, it.longitude, it.radius)
        }
        val previousPoints = passageTracker.points()
        val pointDefinitions = passagePoints.associateBy { it.id }
        announcedCues.keys.removeAll { previousPoints[it] != pointDefinitions[it] || it !in pointDefinitions }
        val update = passageTracker.update(
            PassageTracker.Fix(location.latitude, location.longitude, location.accuracy.toDouble(), fixTime),
            now, passagePoints, applicable)
        passageStatus = update?.presented ?: passageStatus?.takeIf { old ->
            now - old.elapsed <= 5000 && pointDefinitions.containsKey(old.id) && old.id in applicable
        }?.copy(changed = false)
        handler.removeCallbacks(stalePassageCheck)
        if (passageStatus != null) handler.postDelayed(stalePassageCheck, 5500)

        // Every point that changed gets its cue, not only the one on screen:
        // with 1 km zones, two radar points overlap on most of a journey.
        var cuePlayed = false
        voiceStatuses = update?.observed?.filter { it.id in applicable }?.associateBy { it.id } ?: emptyMap()
        update?.observed?.sortedBy { it.distance }?.forEach { status ->
            if (status.changed && status.stage in setOf("exited", "entered")) announcedCues.remove(status.id)
            if (status.id !in applicable) return@forEach
            val played = announcedCues.getOrPut(status.id) { mutableSetOf() }
            val pending = if (PassageVoice.enabled(this)) SpokenPassagePolicy.pending(status, played, level2Enabled(this), voiceSpeedMps) else PassageCuePolicy.pending(status, played)
            for (cue in pending) {
                if (playPassageCue(cue, status, entries.firstOrNull { it.id == status.id })) {
                    played.add(cue)
                    cuePlayed = true
                }
            }
        }

        if (update != null) {
            announcedCues.keys.retainAll(passageTracker.points().keys)
            passageState.save(passageTracker, announcedCues, durable = update.changed.isNotEmpty() || cuePlayed)
        }

        // Notification focus must not hide a simultaneous point with a known limit.
        val speedWarning = PassageSpeedPolicy.select(update?.observed ?: emptyList(),
            entriesById, voiceSpeedMps, applicable)
        speedNote = speedWarning?.let { "${it.kmh} km/h · limite ${it.point.speedLimitKmh}" }
        if (speedWarning != null) {
            val nowMs = SystemClock.elapsedRealtime()
            if (nowMs - lastSpeedWarningAt >= SPEED_WARNING_INTERVAL_MS &&
                playPassageCue("speed", speedWarning.status, speedWarning.point)) {
                lastSpeedWarningAt = nowMs
            }
        }
        var closest: Pair<AlarmEntry, Double>? = null

        for (entry in entries) {
            val distance = distanceBetween(location, entry)

            if (entry.repeatOnEveryEntry) {
                // Passage mode uses short cues and continuous status, never the looping wake-up alarm.
            } else if (distance <= entry.radius) {
                // Time spent waiting cannot make a coarse position more precise.
                val confirmed = ArrivalQuality.confirms(distance, if (location.hasAccuracy()) location.accuracy.toDouble() else null, entry.radius)

                if (!confirmed) {
                    Log.i(TAG, "Arrival awaits a more precise position")
                } else {

                    if (!entry.ringsOn(weekday)) {
                        // Armed, but not for today. Deliberately checked before
                        // the suppression test so the alarm is not left needing
                        // an exit it already made: the user genuinely arrived,
                        // the schedule simply says not today, and tomorrow's
                        // arrival should be treated as an arrival.
                        Log.i(TAG, "Reminder is not scheduled today")
                        arrivalState.suppressUntilExit(entry.id)
                    } else if (entry.oncePerDay && arrivalState.hasRungToday(entry.id, today())) {
                        // Left the radius and came back the same day. One ring a
                        // day is what a repeating reminder means.
                        Log.i(TAG, "Daily reminder already handled")
                        arrivalState.suppressUntilExit(entry.id)
                    } else if (arrivalState.shouldSuppress(entry.id)) {
                        // Arrival means crossing *into* the radius. Being inside
                        // already the first time this alarm is seen is not an
                        // arrival, so an alarm set for where you're standing
                        // doesn't ring at once.
                        Log.i(TAG, "Reminder awaits an exit before a new arrival")
                    } else {
                        triggerAlarm(entry)
                        return
                    }
                }
            } else {
                arrivalState.markOutside(entry.id)
            }

            if (entry.ringsOn(weekday) &&
                !(entry.oncePerDay && arrivalState.hasRungToday(entry.id, today())) &&
                (closest == null || distance < closest.second)) {
                closest = entry to distance
            }
        }

        closest?.let { (entry, distance) ->
            nearestLabel = entry.label
            nearestDistance = distance
            updateNotification()
        }
        adaptIntervalTo(location, entries, weekday)
    }

    /**
     * The short cues, in two strengths.
     *
     * Level 1 is the single soft beep this service has always played. Level 2
     * is three beeps at full notification volume, used when the phone is close
     * to the point and — through [playPassageCue] with "speed" — when the
     * measured speed is above the limit the source states. ToneGenerator fixes
     * its volume at construction, so the two strengths are two generators
     * rather than one turned up.
     */

    /**
     * Attempts one cue; a successful tone start does not prove human audibility.
     *
     * The return value matters: a cue used to be recorded as announced before
     * the tone was even attempted, so a notification volume at zero or a
     * failed generator left the driver in silence while the app believed it
     * had warned. `STREAM_ALARM` rather than `STREAM_NOTIFICATION`: the latter
     * follows the notification volume and silent mode, which is exactly the
     * state a phone is in when it sits in a car mount.
     */
    private fun playPassageCue(cue: String, status: PassageTracker.Status? = null, point: AlarmEntry? = null): Boolean {
        if (!passageAudioEnabled(this)) return false
        if (cue == "speed" && !speedAlertsEnabled(this)) return false
        if (PassageVoice.enabled(this)) {
            if (status == null || point == null || !SpokenPassagePolicy.fresh(status, SystemClock.elapsedRealtime())) return false
            val projected = SpokenPassagePolicy.distanceAtPlayback(status, SystemClock.elapsedRealtime(), voiceSpeedMps) ?: return false
            val asset = SpokenPassagePolicy.asset(point.poiType, cue, projected, voiceSpeedMps)
            voice.play(asset, urgent = cue == "speed", sourceId = status.id, valid = {
                val latest = voiceStatuses[status.id]
                passageAudioEnabled(this) && PassageVoice.enabled(this) && latest != null &&
                    SpokenPassagePolicy.fresh(latest, SystemClock.elapsedRealtime()) && latest.approachAligned &&
                    latest.stage in setOf("entered", "approaching", "before25") &&
                    (cue != "speed" || (speedAlertsEnabled(this) && PassageSpeedPolicy.eligible(latest, point, voiceSpeedMps))) &&
                    (SpokenPassagePolicy.distanceAtPlayback(latest, SystemClock.elapsedRealtime(), voiceSpeedMps)?.let { distance ->
                        SpokenPassagePolicy.asset(point.poiType, cue, distance, voiceSpeedMps) == asset
                    } == true)
            }, onStarted = {
                if (cue == "speed") lastSpeedWarningAt = SystemClock.elapsedRealtime()
                else {
                    announcedCues.getOrPut(status.id) { mutableSetOf() }.add(cue)
                    passageState.save(passageTracker, announcedCues, durable = true)
                }
            }, onFailed = {
                announcedCues[status.id]?.remove(cue)
                passageState.save(passageTracker, announcedCues, durable = true)
            })
            // Consumption is committed by onStarted, never by queue acceptance.
            return false
        }
        try {
            val loud = cue == "speed" || (cue == "near" && level2Enabled(this))
            val tone = if (loud) {
                passageToneLoud ?: android.media.ToneGenerator(
                    android.media.AudioManager.STREAM_ALARM, 100,
                ).also { passageToneLoud = it }
            } else {
                passageTone ?: android.media.ToneGenerator(
                    android.media.AudioManager.STREAM_ALARM, 70,
                ).also { passageTone = it }
            }
            val toneId = when (cue) {
                "near" -> android.media.ToneGenerator.TONE_PROP_BEEP2
                "passed" -> android.media.ToneGenerator.TONE_PROP_ACK
                "speed" -> android.media.ToneGenerator.TONE_CDMA_ALERT_CALL_GUARD
                else -> android.media.ToneGenerator.TONE_PROP_BEEP
            }
            val repeats = when {
                cue == "speed" -> 1
                loud -> 3
                else -> 1
            }
            if (toneSequence.busy) return false
            selectedTone = tone
            return toneSequence.start(toneId, repeats)
        } catch (_: Exception) {
            return false
        }
    }

    private fun distanceBetween(location: Location, entry: AlarmEntry): Double {
        val results = FloatArray(1)
        Location.distanceBetween(
            location.latitude,
            location.longitude,
            entry.latitude,
            entry.longitude,
            results,
        )
        return results[0].toDouble()
    }

    /**
     * Today as 1 = Monday through 7 = Sunday, matching Dart's
     * `DateTime.weekday` and so the numbers stored in [AlarmEntry.repeatDays].
     *
     * [Calendar.DAY_OF_WEEK] counts from Sunday = 1, which is the same range
     * meaning different days — storing one and comparing against the other
     * would arm every alarm one day early.
     */
    private fun todayIsoWeekday(): Int =
        ((Calendar.getInstance().get(Calendar.DAY_OF_WEEK) + 5) % 7) + 1

    /** The local calendar date, as the key for "has this rung today". */
    private fun today(): String {
        val cal = Calendar.getInstance()
        return "%04d-%02d-%02d".format(
            cal.get(Calendar.YEAR),
            cal.get(Calendar.MONTH) + 1,
            cal.get(Calendar.DAY_OF_MONTH),
        )
    }

    /**
     * Sets the polling interval from the one thing that actually decides
     * whether an alarm can be missed: how long the user could still be far
     * enough away for the next fix to be worth waiting for.
     *
     * The gap between two fixes is safe as long as it cannot cover the whole
     * distance to the far side of the destination circle — that is
     * `distance + radius` metres. Divided by the speed being travelled and by
     * [SAMPLES_BEFORE_ARRIVAL], it gives an interval that keeps several fixes
     * between here and the stop no matter what the numbers are, and it does
     * so without a table of hand-picked distance bands that were each only
     * ever right for one kind of journey.
     *
     * Where the fix reports a speed, that speed is used. Where it does not —
     * or reports a bus sitting at a light — [CRUISE_SPEED_MPS] stands in for
     * how fast the journey could resume, so a stationary phone is never
     * lulled into an interval it cannot get out of.
     *
     * What this changes in practice: two hours into a 300 km coach journey
     * the old fixed ladder was still waking the GNSS receiver every five
     * minutes, for a stop that could not physically arrive for another hour.
     * It now waits a quarter of an hour, and tightens continuously as the
     * distance falls, reaching ten-second fixes for the final approach
     * exactly as before.
     */
    private fun adaptIntervalTo(location: Location, entries: List<AlarmEntry>, weekday: Int) {
        val reported = if (location.hasSpeed() && location.speed > 1f) location.speed else 0f
        val planned = maxOf(reported, CRUISE_SPEED_MPS)
        val todayStr = today()

        var target = MAX_INTERVAL_MILLIS
        for (entry in entries) {
            if (!entry.ringsOn(weekday)) continue
            // An alarm that has already rung today cannot ring again today.
            // Leaving it in the calculation would pull the polling interval
            // down to 10 seconds while the user sits at their destination for
            // the rest of the workday.
            if (entry.oncePerDay && arrivalState.hasRungToday(entry.id, todayStr)) continue

            val distance = distanceBetween(location, entry)
            if (entry.repeatOnEveryEntry && distance <= entry.radius + 500) {
                // A missing speed reading is not a parked car: the fused
                // provider routinely reports no speed at the start of a
                // journey. At 5 s and 130 km/h, 180 m pass between two fixes,
                // which is most of any useful warning.
                target = minOf(target, 1000L)
                continue
            }
            // Distance to the *near* edge of the zone, not to its far side.
            // d + r was the distance to the opposite edge: at 130 km/h, a
            // point 1 600 m away with a 1 000 m radius produced a 20 s
            // interval, so the first fix after the entry could arrive 122 m
            // and 3.4 s late. What has to be sampled is the entry.
            val reach = maxOf(0.0, distance - entry.radius)
            var safe = (reach / planned / SAMPLES_BEFORE_ARRIVAL * 1000).toLong()

            // If the user is currently inside the radius and suppressed awaiting
            // an exit (e.g. setting an alarm for Home while at home), they are
            // moving away from the stop rather than arriving. Detecting an exit
            // does not require sub-second GPS accuracy: floor it to 60s so the
            // phone can sleep at balanced power rather than burning 10s fixes
            // overnight. Once outside, markOutside clears suppression and approach
            // intervals tighten as normal.
            if (arrivalState.isSuppressed(entry.id)) {
                safe = maxOf(safe, SUPPRESSED_EXIT_INTERVAL_MILLIS)
            }

            target = minOf(target, safe)
        }

        // Quantised, because re-registering restarts the receiver's whole
        // acquisition cycle. Left continuous, a target that drifted by a
        // second between fixes would pay that cost on every single one.
        val stepped = INTERVAL_STEPS_MILLIS.lastOrNull { it <= target } ?: 1000L
        if (stepped != currentIntervalMillis) requestUpdates(stepped)
    }

    private fun triggerAlarm(entry: AlarmEntry) {
        Log.i(TAG, "Arrival confirmed; requesting alarm presentation")
        // We are already a foreground service, so starting the alarm service
        // from here is always permitted.
        val alarmIntent = Intent(this, AlarmForegroundService::class.java).apply {
            action = AlarmForegroundService.ACTION_START
            putExtra(AlarmForegroundService.EXTRA_ALARM_ID, entry.id)
            putExtra(AlarmForegroundService.EXTRA_LABEL, entry.label)
        }
        try {
            ContextCompat.startForegroundService(this, alarmIntent)
        } catch (e: Exception) {
            Log.e(TAG, "Could not start AlarmForegroundService; posting fallback notification", e)
            NotificationHelper.postFallbackAlarmNotification(this, entry.label)
        }

        // A repeating alarm survives the ring, and the user is standing
        // inside its radius as it does. Without this it would ring again on
        // the very next fix, and every fix after that. See
        // [ArrivalState.suppressUntilExit].
        //
        // The day is marked here rather than where it is checked, because
        // here is the only place we know the alarm actually rang.
        if (entry.oncePerDay) arrivalState.markRungToday(entry.id, today())
        arrivalState.suppressUntilExit(entry.id)

        // The alarm service consumes the entry itself, so this deliberately
        // asks only about the *other* entries: whether this one has been
        // removed yet is a race, and whether anything else is armed is not.
        //
        // A repeating alarm is not consumed at all, so it still counts as
        // armed and the watch has to stay up for it. Stopping here would have
        // been the whole feature failing silently on the second week: the
        // alarm survives in the store, the service that watches for it does
        // not, and nothing restarts it until the app is next opened.
        val othersArmed = AlarmStore(this).loadAll().any { it.id != entry.id }
        if (!entry.repeats && !othersArmed) {
            stopWatching()
        } else if (entry.repeats) {
            // A repeating alarm just completed for today. If no other active
            // alarms are scheduled to ring for the rest of today, stand down
            // into dormancy immediately rather than polling GPS every 10s until
            // the next watchdog check.
            applyTodaysSchedule()
        }
    }

    private fun stopWatching() {
        passageState.clear()
        announcedCues.clear()
        handler.removeCallbacks(stalePassageCheck)
        handler.removeCallbacks(staleFixCheck)
        passageStatus = null
        passageTracker.reset()
        voiceStatuses = emptyMap()
        voice.stop()
        toneSequence.cancel()
        selectedTone = null
        passageTone?.release()
        passageTone = null
        passageToneLoud?.release()
        passageToneLoud = null
        isWatching = false
        isReceivingUpdates = false
        isDormant = false
        handler.removeCallbacks(starvationCheck)
        NotificationHelper.clearLocationOffNotification(this)
        try {
            locationManager.removeUpdates(locationListener)
        } catch (_: Exception) {
            // Manager may already be torn down.
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
        stopSelf()
    }

    override fun onDestroy() {
        handler.removeCallbacks(stalePassageCheck)
        handler.removeCallbacks(staleFixCheck)
        passageStatus = null
        passageTracker.reset()
        voiceStatuses = emptyMap()
        voice.stop()
        toneSequence.cancel()
        selectedTone = null
        passageTone?.release()
        passageTone = null
        passageToneLoud?.release()
        passageToneLoud = null
        isWatching = false
        isReceivingUpdates = false
        isDormant = false
        handler.removeCallbacks(starvationCheck)
        try {
            locationManager.removeUpdates(locationListener)
        } catch (_: Exception) {
            // Ignored.
        }
        super.onDestroy()
    }

    /**
     * Re-posts the ongoing notification, but only when it would actually read
     * differently.
     *
     * Every fix used to re-post it, which at ten-second fixes is a wakeup and
     * a round trip to the notification manager six times a minute to redraw
     * the same sentence. The distance only changes the text when the rounded
     * number does.
     */
    private fun updateNotification() {
        val text = notificationText()
        if (text == lastNotificationText) return

        val manager = getSystemService(android.app.NotificationManager::class.java) ?: return
        val notification = buildNotification(text)
        try {
            manager.notify(NOTIFICATION_ID, notification)
        } catch (_: SecurityException) {
            // Notification permission revoked.
        }
    }

    private fun notificationText(): String {
        val distance = nearestDistance
        val label = nearestLabel
        return when {
            isDormant -> getString(R.string.watch_dormant_body)
            !isReceivingUpdates -> getString(R.string.watch_location_off)
            label == null || distance == null -> {
                val armedCount = AlarmStore(this).loadAll().size
                resources.getQuantityString(R.plurals.watch_armed, armedCount, armedCount)
            }
            // A registration that keeps succeeding while no usable fix arrives
            // is the quiet failure the audit named: the notification said
            // "watching" with a distance that could be minutes old.
            lastFixElapsed != 0L &&
                WatchHealth.state(isWatching, isDormant, isReceivingUpdates, lastFixElapsed,
                    SystemClock.elapsedRealtime(), currentIntervalMillis) == "economy" ->
                getString(R.string.watch_waiting_fix)
            lastFixElapsed != 0L &&
                SystemClock.elapsedRealtime() - lastFixElapsed > STALE_FIX_MILLIS ->
                getString(R.string.watch_stale_fix)
            passageStatus?.let { SystemClock.elapsedRealtime() - it.elapsed <= 5000 } == true -> {
                val status = passageStatus!!
                val base = "${stageLabel(status.stage)} · ${status.distance.toInt()} m · ±${status.accuracy.toInt()} m — ${status.label}"
                speedNote?.let { "$base · $it" } ?: base
            }
            passageStatus != null -> "Position à actualiser · étapes suspendues"
            AlarmSettings(this).useMiles() -> {
                val miles = distance / 1609.344
                if (miles >= 0.1) {
                    getString(R.string.watch_distance_mi, "%.1f".format(miles), label)
                } else {
                    val feet = ((distance * 3.28084) / 10).toInt() * 10
                    getString(R.string.watch_distance_ft, maxOf(feet, 10).toString(), label)
                }
            }
            distance >= 1000 ->
                getString(R.string.watch_distance_km, "%.1f".format(distance / 1000), label)
            else ->
                getString(R.string.watch_distance_m, distance.toInt().toString(), label)
        }
    }

    private fun buildNotification(text: String = notificationText()): Notification {
        val openIntent = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        lastNotificationText = text

        return NotificationCompat.Builder(this, NotificationHelper.WATCH_CHANNEL_ID)
            .setContentTitle(
                getString(
                    when {
                        isDormant -> R.string.watch_title_dormant
                        isReceivingUpdates -> R.string.watch_title_active
                        else -> R.string.watch_title_inactive
                    },
                ),
            )
            .setContentText(text)
            .setSmallIcon(R.drawable.ic_stat_red_alert)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setOngoing(true)
            .setSilent(true)
            .setShowWhen(false)
            // Shown the moment the service starts, rather than ten seconds
            // later.
            //
            // Android 12 defers foreground-service notifications by ten
            // seconds, so that a service which starts and finishes quickly
            // does not flash a notification nobody needed to read. Sensible
            // in general, wrong here: this notification is the receipt for
            // "your alarm is armed", and a person who has just set one and
            // sees nothing in the status bar concludes it did not work — then
            // leaves the app and comes back to check, by which time the ten
            // seconds have quietly passed and it is there.
            //
            // The deferral only applies to notifications with nothing urgent
            // about them: no action buttons, a low-importance channel, an
            // unremarkable category. This one is all three, deliberately —
            // it is a status line, not an alert — so it qualifies on every
            // count and this is the way out. The ringing alarm's own
            // notification was never affected: it is MAX priority, on an
            // ALARM category, with a button on it.
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .setContentIntent(openIntent)
            .build()
    }

    override fun dump(fd: java.io.FileDescriptor, writer: java.io.PrintWriter, args: Array<out String>?) {
        // Only test playback metadata: no place, coordinate, speed or travel log.
        val snapshot = VoicePreviewSession.snapshotIfCreated() ?: mapOf("state" to "idle")
        writer.println("RedAlertVoicePreview=" + org.json.JSONObject(snapshot).put("schemaVersion", 1).toString())
    }

    companion object {
        /** One speed cue at most every 20 s, so it insists without nagging. */
        private const val SPEED_WARNING_INTERVAL_MS = 20_000L

        /** After this long without a usable fix, the notification says so. */
        private const val STALE_FIX_MILLIS = WatchHealth.STALE_MILLIS

        private const val RECONFIGURE_INTERVAL_MILLIS = 1000L
        @Volatile private var requestedIntervalMillis: Long = FAR_INTERVAL_MILLIS
        @Volatile private var lastFixElapsed: Long = 0
        fun watchStatus(context: android.content.Context): Map<String, Any?> {
            val now = SystemClock.elapsedRealtime()
            val snapshot = AlarmStore(context).snapshot()
            return mapOf(
                "state" to if (snapshot.corrupt) "storage_error" else if (snapshot.receipts.size >= AlarmStore.MAX_RECEIPTS) "receipt_limit" else WatchHealth.state(isWatching, isDormant, isReceivingUpdates, lastFixElapsed, now, requestedIntervalMillis),
                "armedCount" to snapshot.entries.size,
                "invalidRecords" to snapshot.invalidRecords,
                "fixAgeMillis" to lastFixElapsed.takeIf { it > 0 && it <= now }?.let { now - it },
            )
        }

        @Volatile var passageStatus: PassageTracker.Status? = null
            private set
        fun passageAudioEnabled(context: android.content.Context) =
            prefs(context).getBoolean("audio", true)

        /** Optional close reminder: a short phrase in voice mode, three beeps in tone mode. */
        fun level2Enabled(context: android.content.Context) =
            prefs(context).getBoolean("level2", true)

        fun setLevel2(context: android.content.Context, enabled: Boolean) {
            check(prefs(context).edit().putBoolean("level2", enabled).commit())
        }

        /** Warning when the measured speed is above the point's known limit. */
        fun speedAlertsEnabled(context: android.content.Context) =
            prefs(context).getBoolean("speed_alerts", true)

        fun setSpeedAlerts(context: android.content.Context, enabled: Boolean) {
            check(prefs(context).edit().putBoolean("speed_alerts", enabled).commit())
        }

        private fun prefs(context: android.content.Context) =
            context.getSharedPreferences("passage_preferences", android.content.Context.MODE_PRIVATE)
        fun setPassageAudio(context: android.content.Context, enabled: Boolean) {
            check(context.getSharedPreferences("passage_preferences", android.content.Context.MODE_PRIVATE)
                .edit().putBoolean("audio", enabled).commit())
        }
        fun stageLabel(stage: String) = when(stage) {
            "entered" -> "Entrée dans la zone"
            "approaching" -> "Approche du point"
            "before25" -> "Point imminent · estimé"
            "passed" -> "Point dépassé · estimé"
            "passed_between_fixes" -> "Passage estimé entre deux mesures"
            "after25" -> "Plus de 25 m après · estimé"
            "receding" -> "Éloignement du point"
            "exited" -> "Sortie de la zone"
            else -> "Dans la zone · mouvement indéterminé"
        }

        private const val TAG = "LocationWatchService"
        const val ACTION_STOP = "com.zaifears.locreminder.action.STOP_WATCH"
        private const val NOTIFICATION_ID = 4203
        private const val FAR_INTERVAL_MILLIS = 120_000L
        private const val NEAR_INTERVAL_MILLIS = 10_000L
        private const val SUPPRESSED_EXIT_INTERVAL_MILLIS = 60_000L
        private const val MAX_INTERVAL_MILLIS = 900_000L

        /**
         * The intervals actually used, so that a continuously computed target
         * turns into a handful of stable registrations rather than a new one
         * on every fix.
         */
        private val INTERVAL_STEPS_MILLIS = listOf(
            1000L, 5000L, 10_000L, 15_000L, 20_000L, 30_000L, 45_000L, 60_000L,
            90_000L, 120_000L, 180_000L, 300_000L, 600_000L, MAX_INTERVAL_MILLIS,
        )

        /**
         * How fast to assume the journey could be moving when the fix does not
         * say — 72 km/h, which covers a highway coach and leaves margin for an
         * intercity train that has not reported its speed yet.
         */
        private const val CRUISE_SPEED_MPS = 20f

        /** Fixes to fit between here and the far side of the destination. */
        private const val SAMPLES_BEFORE_ARRIVAL = 3

        /** Above this interval, the expensive always-GNSS tier is not asked for. */
        private const val HIGH_ACCURACY_UP_TO_MILLIS = 30_000L

        /** Above this interval, other apps' fixes are worth listening for. */
        private const val PASSIVE_PIGGYBACK_FROM_MILLIS = 60_000L

        /**
         * Maximum wait for the first fix before rebuilding the registration
         * around the raw providers. Long enough for an ordinary GNSS cold
         * start, but short enough that an offline journey is not invisible
         * for several minutes.
         */
        private const val FIRST_FIX_STARVATION_MILLIS = 90_000L

        /** Slack on top of missed intervals before calling later silence starvation. */
        private const val STARVATION_GRACE_MILLIS = 30_000L

        /** Floor for later starvation checks after at least one fix has arrived. */
        private const val MIN_STARVATION_MILLIS = 120_000L

        var isWatching: Boolean = false
            private set

        /**
         * Whether fixes are actually being delivered, as opposed to the
         * service merely being alive. The two diverge exactly when location is
         * switched off at the OS level: the service runs, holds its
         * notification and looks armed, while nothing can ever trigger. Kept
         * separate so the watchdog can tell that case apart and retry.
         */
        var isReceivingUpdates: Boolean = false
            private set

        /**
         * Whether the service is deliberately not asking for fixes because
         * nothing armed is scheduled to ring today. Distinct from the state
         * above, which is a fault: this one is the service doing its job by
         * doing nothing, and restarting it would not be a repair.
         */
        var isDormant: Boolean = false
            private set
    }
}
