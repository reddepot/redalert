package com.zaifears.locreminder

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.os.Build
import android.os.Handler
import android.os.Looper

/** Focus callbacks belong to their acquisition, never to a later playback. */
class TransientAudioFocus(context: Context, private val onLoss: () -> Unit) {
    private val audio = context.getSystemService(AudioManager::class.java)
    private val handler = Handler(Looper.getMainLooper())
    private val attributes = AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_ALARM)
        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build()
    private var request: AudioFocusRequest? = null
    private var listener: AudioManager.OnAudioFocusChangeListener? = null
    private var generation = 0L

    fun acquire(): Boolean {
        release()
        val ticket = ++generation
        val callback = AudioManager.OnAudioFocusChangeListener { change ->
            if (change < 0 && generation == ticket) onLoss()
        }
        listener = callback
        val result = if (Build.VERSION.SDK_INT >= 26) {
            val next = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK)
                .setAudioAttributes(attributes).setAcceptsDelayedFocusGain(false)
                .setOnAudioFocusChangeListener(callback, handler).build()
            request = next
            audio.requestAudioFocus(next)
        } else {
            @Suppress("DEPRECATION")
            audio.requestAudioFocus(callback, AudioManager.STREAM_ALARM, AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK)
        }
        if (result != AudioManager.AUDIOFOCUS_REQUEST_GRANTED || generation != ticket) {
            release()
            return false
        }
        return true
    }

    fun release() {
        generation++
        if (Build.VERSION.SDK_INT >= 26) request?.let { audio.abandonAudioFocusRequest(it) }
        else listener?.let { @Suppress("DEPRECATION") audio.abandonAudioFocus(it) }
        request = null
        listener = null
    }
}
