package com.zaifears.locreminder

/** A bounded, cancellable test only; never schedules a real passage alert. */
internal class VoicePreviewController(
    private val state: VoicePreviewState,
    private val schedule: (Long, () -> Unit) -> (() -> Unit),
    private val keepAwake: (Long) -> (() -> Unit),
    private val play: (String, () -> Unit, () -> Unit, () -> Unit) -> Boolean,
    private val stopPlayer: () -> Unit,
    private val clock: () -> Long,
    private val failureReason: () -> String? = { null },
) {
    private class Operation(val ticket: Long) {
        var cancelTimer: (() -> Unit)? = null
        var releaseWake: (() -> Unit)? = null
        fun release() { releaseWake?.invoke(); releaseWake = null }
    }
    private var operation: Operation? = null

    fun start(asset: String, delayMillis: Long = 0): Boolean {
        require(delayMillis in 0..5000)
        cancel()
        val op = Operation(state.begin(asset, delayMillis))
        val scheduledFor = clock() + delayMillis
        operation = op
        fun failed() {
            if (operation !== op) return
            state.failed(op.ticket, failureReason() ?: "unavailable")
            op.release()
        }
        fun dispatch(): Boolean {
            if (operation !== op) return false
            op.cancelTimer = null
            if (delayMillis > 0 && clock() - scheduledFor !in 0..2000) {
                state.failed(op.ticket, "countdown_expired")
                op.release()
                return false
            }
            state.preparing(op.ticket)
            return try {
                play(asset, {
                    if (operation === op) {
                        state.started(op.ticket)
                        // MediaPlayer now holds its own playback wake lock.
                        op.release()
                    }
                }, { failed() }, {
                    if (operation === op) { state.completed(op.ticket); op.release() }
                }).also { if (!it) failed() }
            } catch (_: Exception) { failed(); false }
        }
        if (delayMillis == 0L) return dispatch()
        return try {
            // Automatic expiry also bounds the lock if a callback is lost.
            op.releaseWake = keepAwake(delayMillis + 8000)
            op.cancelTimer = schedule(delayMillis) { dispatch() }
            true
        } catch (_: Exception) { failed(); false }
    }

    fun cancel(reason: String = "cancelled") {
        val old = operation
        operation = null
        if (old != null) state.cancel(old.ticket, reason)
        old?.cancelTimer?.invoke()
        old?.release()
        stopPlayer()
    }

    fun snapshot(): Map<String, Any?> = state.snapshot()
}
