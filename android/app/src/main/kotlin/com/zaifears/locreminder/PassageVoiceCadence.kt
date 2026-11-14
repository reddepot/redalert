package com.zaifears.locreminder

/** Repetition protection belongs to a point, not to every nearby point. */
internal class PassageVoiceCadence {
    private val started = LinkedHashMap<String, Long>()
    fun allows(sourceId: String?, now: Long, preview: Boolean, urgent: Boolean): Boolean {
        started.entries.removeAll { now - it.value >= 8000 || now < it.value }
        return preview || urgent || started[sourceId ?: ""]?.let { now - it >= 8000 } != false
    }
    fun record(sourceId: String?, now: Long) {
        started[sourceId ?: ""] = now
        if (started.size > 128) started.remove(started.keys.first())
    }
}
