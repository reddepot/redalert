package com.zaifears.locreminder

/** Metadata of a test clip only. No location, preference or travel history. */
internal class VoicePreviewState(private val clock: () -> Long, private val interactive: () -> Boolean) {
    private var sequence = 0L
    private var asset: String? = null
    private var state = "idle"
    private var started: Long? = null
    private var finished: Long? = null
    private var scheduledFor: Long? = null
    private var startedScreenOff: Boolean? = null
    private var finishedScreenOff: Boolean? = null
    private var failureCode: String? = null
    fun begin(value: String, delayMillis: Long = 0): Long {
        sequence++; asset = value; state = if (delayMillis > 0) "scheduled" else "preparing"
        scheduledFor = if (delayMillis > 0) clock() + delayMillis else null
        started = null; finished = null; startedScreenOff = null; finishedScreenOff = null
        failureCode = null
        return sequence
    }
    fun preparing(ticket: Long) {
        if (ticket == sequence && state == "scheduled") state = "preparing"
    }
    fun started(ticket: Long) {
        if (ticket != sequence || state != "preparing") return
        state = "playing"; started = clock(); startedScreenOff = !interactive()
    }
    fun completed(ticket: Long) {
        if (ticket != sequence || state != "playing") return
        state = "completed"; finished = clock(); finishedScreenOff = !interactive()
    }
    fun failed(ticket: Long, reason: String = "unavailable") {
        if (ticket != sequence || state !in setOf("scheduled", "preparing", "playing")) return
        state = "error"; finished = clock(); failureCode = reason
    }
    fun cancel(ticket: Long? = null, reason: String = "cancelled") {
        if (ticket != null && ticket != sequence) return
        sequence++
        if (state in setOf("scheduled", "preparing", "playing")) {
            state = "cancelled"; finished = clock(); finishedScreenOff = null; failureCode = reason
        }
    }
    fun snapshot(): Map<String, Any?> = mapOf("state" to state, "asset" to asset,
        "scheduledForMillis" to scheduledFor, "startedWhileScreenOff" to startedScreenOff,
        "failureCode" to failureCode,
        "startedAtMillis" to started, "finishedAtMillis" to finished,
        "finishedWhileScreenOff" to finishedScreenOff)
}
