package com.zaifears.locreminder

import android.content.Context
import android.hardware.display.DisplayManager
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.os.SystemClock
import android.view.Display

/** One in-memory test per app process, independent of Activity recreation. */
internal object VoicePreviewSession {
    private var instance: VoicePreviewController? = null

    fun controller(context: Context): VoicePreviewController {
        instance?.let { return it }
        val app = context.applicationContext
        val power = app.getSystemService(PowerManager::class.java)
        val displays = app.getSystemService(DisplayManager::class.java)
        val player = PassageVoice(app)
        val handler = Handler(Looper.getMainLooper())
        return VoicePreviewController(
            state = VoicePreviewState({ SystemClock.elapsedRealtime() }, {
                // Ambient/dozing displays are not proof of a fully off screen.
                power.isInteractive || displays.getDisplay(Display.DEFAULT_DISPLAY)?.state != Display.STATE_OFF
            }),
            schedule = { delay, action ->
                val task = Runnable { action() }
                check(handler.postDelayed(task, delay))
                val cancel: () -> Unit = { handler.removeCallbacks(task) }
                cancel
            },
            keepAwake = { timeout ->
                val lock = power.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "RedAlert:voice-preview")
                lock.setReferenceCounted(false)
                lock.acquire(timeout)
                val release: () -> Unit = { if (lock.isHeld) lock.release() }
                release
            },
            play = { asset, started, failed, completed ->
                player.play(asset, preview = true, onStarted = started,
                    onFailed = failed, onCompleted = completed)
            },
            stopPlayer = { player.stop() },
            clock = { SystemClock.elapsedRealtime() },
            failureReason = { player.failureCode },
        ).also { instance = it }
    }

    fun cancelIfCreated(reason: String) { instance?.cancel(reason) }
    fun snapshotIfCreated(): Map<String, Any?>? = instance?.snapshot()
}
