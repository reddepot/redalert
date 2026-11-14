package com.zaifears.locreminder

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.MediaPlayer
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock

/** No synthesis, network, queue or engine dependency while driving. */
class PassageVoice(private val context: Context) {
    private val handler = Handler(Looper.getMainLooper())
    private val audio = context.getSystemService(AudioManager::class.java)
    private val attributes = AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_ASSISTANCE_NAVIGATION_GUIDANCE)
        .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH).build()
    private var player: MediaPlayer? = null
    private var request: AudioFocusRequest? = null
    private var failure: (() -> Unit)? = null
    private val cadence = PassageVoiceCadence()
    var failureCode: String? = null
        private set
    private val focusListener = AudioManager.OnAudioFocusChangeListener { change ->
        if (change < 0) {
            failureCode = "audio_focus_lost:$change"; lastError = "Sortie audio interrompue"
            failure?.invoke(); stop()
        }
    }
    private val timeout = Runnable { failureCode = "timeout"; lastError = "Lecture interrompue"; failure?.invoke(); stop() }
    val busy get() = player != null

    fun play(asset: String, preview: Boolean = false, urgent: Boolean = false, sourceId: String? = null, valid: () -> Boolean = { true }, onStarted: () -> Unit = {}, onFailed: () -> Unit = {}, onCompleted: () -> Unit = {}): Boolean {
        val now = SystemClock.elapsedRealtime()
        if (busy || !cadence.allows(sourceId, now, preview, urgent) || !valid()) {
            failureCode = "not_available"; return false
        }
        failureCode = null
        val focus = if (Build.VERSION.SDK_INT >= 26) {
            AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK).setAudioAttributes(attributes)
                .setOnAudioFocusChangeListener(focusListener, handler).setAcceptsDelayedFocusGain(false).build().also { request = it }
                .let { audio.requestAudioFocus(it) }
        } else {
            @Suppress("DEPRECATION")
            audio.requestAudioFocus(focusListener, AudioManager.STREAM_MUSIC, AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK)
        }
        if (focus != AudioManager.AUDIOFOCUS_REQUEST_GRANTED) { failureCode = "focus_refused"; lastError = "Sortie audio occupée"; releaseFocus(); return false }
        return try {
            val p = MediaPlayer(); player = p; failure = onFailed
            p.setAudioAttributes(attributes)
            p.setWakeMode(context, android.os.PowerManager.PARTIAL_WAKE_LOCK)
            context.assets.openFd("flutter_assets/assets/voice/fr/$asset.ogg").use { fd -> p.setDataSource(fd.fileDescriptor, fd.startOffset, fd.length) }
            p.setOnPreparedListener {
                if (player !== p) return@setOnPreparedListener
                if (SystemClock.elapsedRealtime() - now > 2000 || !valid()) { failureCode = "preparation_expired"; onFailed(); stop(); return@setOnPreparedListener }
                try { p.start(); cadence.record(sourceId, SystemClock.elapsedRealtime()); lastError = null; onStarted() }
                catch (_: Exception) { failureCode = "start_failure"; lastError = "Lecture vocale indisponible"; onFailed(); stop() }
            }
            p.setOnCompletionListener { if (player === p) { try { onCompleted() } finally { stop() } } }
            p.setOnErrorListener { _, what, extra -> if (player !== p) return@setOnErrorListener true; failureCode = "media_error:$what:$extra"; lastError = "Lecture vocale indisponible"; onFailed(); stop(); true }
            handler.postDelayed(timeout, 7000)
            p.prepareAsync()
            true
        } catch (_: Exception) { failureCode = "asset_unavailable"; lastError = "Fichier vocal indisponible"; onFailed(); stop(); false }
    }
    private fun releaseFocus() {
        if (Build.VERSION.SDK_INT >= 26) request?.let { audio.abandonAudioFocusRequest(it) }
        else { @Suppress("DEPRECATION") audio.abandonAudioFocus(focusListener) }
        request = null
    }
    fun stop() {
        handler.removeCallbacks(timeout)
        player?.release(); player = null; failure = null
        releaseFocus()
    }
    companion object {
        @Volatile var lastError: String? = null
        fun enabled(context: Context) = context.getSharedPreferences("passage_preferences", Context.MODE_PRIVATE).getBoolean("voice", true)
        fun setEnabled(context: Context, value: Boolean) { check(context.getSharedPreferences("passage_preferences", Context.MODE_PRIVATE).edit().putBoolean("voice", value).commit()) }
    }
}
