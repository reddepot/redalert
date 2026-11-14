package com.zaifears.locreminder

/** One bounded tone sequence, with explicit ownership of callbacks and focus. */
class PassageToneSequence(
    private val post: (Runnable, Long) -> Unit,
    private val remove: (Runnable) -> Unit,
    private val requestFocus: () -> Boolean,
    private val releaseFocus: () -> Unit,
    private val play: (Int, Int) -> Boolean,
    private val stop: () -> Unit,
) {
    private var generation = 0L
    private var active = false
    private var focused = false
    private val pending = mutableListOf<Runnable>()

    val busy get() = active

    fun start(toneId: Int, repetitions: Int): Boolean {
        if (active) return false
        active = true
        val ticket = ++generation
        val granted = try { requestFocus() } catch (_: Exception) { false }
        if (!granted) { cancel(); return false }
        if (!active || generation != ticket) { releaseFocus(); return false }
        focused = true
        val count = repetitions.coerceIn(1, 3)
        val duration = if (count == 1) 250 else 150
        if (!playSafely(toneId, duration)) { cancel(); return false }
        for (index in 1 until count) {
            schedule(ticket, index * 260L) {
                if (!playSafely(toneId, duration)) cancel()
            }
        }
        schedule(ticket, (count - 1) * 260L + duration) { cancel() }
        return true
    }

    private fun playSafely(toneId: Int, duration: Int) =
        try { play(toneId, duration) } catch (_: Exception) { false }

    private fun schedule(ticket: Long, delay: Long, action: () -> Unit) {
        lateinit var task: Runnable
        task = Runnable {
            pending.remove(task)
            if (active && generation == ticket) action()
        }
        pending.add(task)
        post(task, delay)
    }

    fun cancel() {
        generation++
        val wasActive = active
        active = false
        pending.forEach(remove)
        pending.clear()
        if (wasActive) try { stop() } catch (_: Exception) { /* Already stopped. */ }
        if (focused) {
            focused = false
            releaseFocus()
        }
    }
}
