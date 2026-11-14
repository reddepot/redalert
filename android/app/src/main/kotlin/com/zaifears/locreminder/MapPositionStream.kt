package com.zaifears.locreminder

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Build
import android.os.Bundle
import android.os.Looper
import android.os.SystemClock
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.EventChannel

internal fun Location.positionPayload(): Map<String, Any?> = mapOf(
    "latitude" to latitude, "longitude" to longitude, "accuracy" to accuracy.toDouble(),
    "speed" to if (hasSpeed() && speed.isFinite() && speed >= 0) speed.toDouble() else null,
    "speedAccuracy" to if (Build.VERSION.SDK_INT >= 26 && hasSpeedAccuracy()) speedAccuracyMetersPerSecond.toDouble() else null,
    "bearing" to if (hasBearing() && bearing.isFinite() && (!hasSpeed() || speed >= 2) &&
        (Build.VERSION.SDK_INT < 26 || !hasBearingAccuracy() || bearingAccuracyDegrees <= 30)) bearing.toDouble() else null,
    "time" to time, "elapsedMillis" to elapsedRealtimeNanos / 1_000_000,
    "ageMillis" to (SystemClock.elapsedRealtimeNanos() - elapsedRealtimeNanos) / 1_000_000,
)

/** Foreground map fixes are independent of armed alarms and stop with the map. */
class MapPositionStream(context: Context) : EventChannel.StreamHandler {
    private val context = context.applicationContext
    private val manager = context.getSystemService(LocationManager::class.java)
    private var sink: EventChannel.EventSink? = null
    private val listener = object : LocationListener {
        override fun onLocationChanged(location: Location) { sink?.success(location.positionPayload()) }
        override fun onProviderEnabled(provider: String) {}
        override fun onProviderDisabled(provider: String) {}
        @Deprecated("Deprecated in Java") override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) {}
    }
    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        onCancel(null); sink = events
        if (ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_FINE_LOCATION) != PackageManager.PERMISSION_GRANTED) {
            events.error("permission", "Autorisation de position précise requise", null); return
        }
        var registered = false
        for (provider in listOf(LocationManager.GPS_PROVIDER, LocationManager.NETWORK_PROVIDER)) {
            try {
                if (manager.isProviderEnabled(provider)) {
                    manager.requestLocationUpdates(provider, 1000L, 0f, listener, Looper.getMainLooper()); registered = true
                }
            } catch (_: Exception) { /* Another provider may remain available. */ }
        }
        if (!registered) events.error("location", "Aucun fournisseur de position disponible", null)
    }
    override fun onCancel(arguments: Any?) {
        runCatching { manager.removeUpdates(listener) }; sink = null
    }
}
