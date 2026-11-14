package com.zaifears.locreminder

import kotlin.math.*
import java.io.DataInputStream
import java.io.DataOutputStream

/**
 * Tracks overlapping zones independently, and reports both what to show and
 * what happened.
 *
 * The display needs one target: two sentences about two radars in a
 * notification is noise. The *sound* needs every transition: a point whose
 * approach fires while another point still holds the focus used to be
 * discarded here, and the driver never heard it. So the coordinator returns
 * the presented status for the UI, plus every status that changed on this
 * fix, whatever the focus.
 */
class PassageCoordinator {
    data class Update(
        val presented: PassageTracker.Status?,
        val changed: List<PassageTracker.Status>,
        val observed: List<PassageTracker.Status>,
    )

    private val trackers = mutableMapOf<String, PassageTracker>()
    private val definitions = mutableMapOf<String, PassageTracker.Point>()
    private val recent = mutableMapOf<String, PassageTracker.Status>()
    private var focus: String? = null
    private var lastFixTime = -1L

    fun reset() {
        trackers.clear(); definitions.clear(); recent.clear(); focus = null; lastFixTime = -1L
    }

    internal fun points(): Map<String, PassageTracker.Point> = definitions.toMap()

    internal fun writeCheckpoint(out: DataOutputStream) = with(out) {
        writeLong(lastFixTime)
        writeBoolean(focus != null); focus?.let { writeUTF(it) }
        writeInt(trackers.size)
        for ((id, tracker) in trackers) {
            val point = definitions.getValue(id)
            writeUTF(point.id); writeUTF(point.label)
            writeDouble(point.lat); writeDouble(point.lon); writeDouble(point.radius)
            tracker.writeCheckpoint(this)
        }
    }

    internal fun readCheckpoint(input: DataInputStream, now: Long) {
        reset()
        lastFixTime = input.readLong().also { require(it in -1..now) }
        focus = if (input.readBoolean()) input.readUTF() else null
        val count = input.readInt().also { require(it in 0..5000) }
        repeat(count) {
            val point = PassageTracker.Point(input.readUTF(), input.readUTF(), input.readDouble(), input.readDouble(), input.readDouble())
            require(point.lat.isFinite() && abs(point.lat) <= 90 && point.lon.isFinite() && abs(point.lon) <= 180)
            require(point.radius.isFinite() && point.radius > 0 && point.id !in trackers)
            definitions[point.id] = point
            trackers[point.id] = PassageTracker().also { it.readCheckpoint(input) }
        }
        // No status is restored to the notification: only a fresh fix may present a position.
    }

    fun update(fix: PassageTracker.Fix, now: Long, points: List<PassageTracker.Point>,
               applicable: Set<String>? = null): Update? {
        if (now - fix.elapsed !in 0..5000 || fix.elapsed <= lastFixTime ||
            !fix.accuracy.isFinite() || fix.accuracy !in 0.0..100.0 ||
            !fix.lat.isFinite() || abs(fix.lat) > 90 || !fix.lon.isFinite() || abs(fix.lon) > 180) return null
        lastFixTime = fix.elapsed
        val nearby = points.filter { point ->
            val dx = (fix.lon - point.lon) * 111195 * cos(Math.toRadians(point.lat))
            val dy = (fix.lat - point.lat) * 111195
            hypot(dx, dy) <= point.radius + 1500
        }.associateBy { it.id }
        trackers.keys.retainAll(nearby.keys)
        recent.keys.retainAll(nearby.keys)
        definitions.keys.retainAll(nearby.keys)

        val changed = mutableListOf<PassageTracker.Status>()
        for (point in nearby.values) {
            if (definitions[point.id] != point) {
                trackers.remove(point.id)
                recent.remove(point.id)
            }
            definitions[point.id] = point
            val tracker = trackers.getOrPut(point.id) { PassageTracker() }
            val status = tracker.update(fix, now, listOf(point))
            if (status != null) {
                recent[point.id] = status
                if (status.changed) changed.add(status)
            } else {
                recent.remove(point.id)
            }
        }

        // A temporary course mismatch hides a target, but must not destroy its
        // motion history or checkpoint. All observations still reach storage.
        val eligible = recent.filterKeys { applicable == null || it in applicable }
        val current = eligible[focus]
        val upcoming = eligible.values.filter { it.stage in setOf("before25", "approaching", "entered", "in_zone") }
            .minWithOrNull(compareBy<PassageTracker.Status> { if (it.stage == "before25") 0 else 1 }.thenBy { it.distance })
        val retained = current != null && current.stage != "exited" &&
            // Present crossing/after25 transitions once, then allow the next approaching point.
            (current.stage in setOf("passed", "passed_between_fixes", "after25") ||
             current.stage != "receding" && (upcoming?.stage != "before25" || upcoming.id == current.id))
        val selected = if (retained) current else upcoming ?: current ?: eligible.values.minByOrNull { it.distance }
        focus = selected?.id
        return Update(selected, changed, recent.values.toList())
    }
}
