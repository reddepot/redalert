package com.zaifears.locreminder

import kotlin.math.*
import java.io.DataInputStream
import java.io.DataOutputStream

/** Bounded local geometry, checkpointed for process recovery. No route history or road matching. */
class PassageTracker {
    data class Point(val id: String, val label: String, val lat: Double, val lon: Double, val radius: Double)
    data class Fix(val lat: Double, val lon: Double, val accuracy: Double, val elapsed: Long)
    data class Status(val id: String, val label: String, val stage: String, val distance: Double,
                      val accuracy: Double, val elapsed: Long, val changed: Boolean,
                      val approachAligned: Boolean = false)
    private data class Vector(val x: Double, val y: Double) {
        fun length() = hypot(x, y)
        operator fun minus(other: Vector) = Vector(x - other.x, y - other.y)
        fun dot(other: Vector) = x * other.x + y * other.y
    }
    private var target: Point? = null
    private var previous: Fix? = null
    private var motionAnchor: Fix? = null
    private var speed: Double? = null
    private var direction: Vector? = null
    private var crossingAnchor: Fix? = null
    private var approaching = false
    private var passed = false
    private var nearObserved = false
    private var outsideSeen = false
    private var outsideBeforeEntry = 0
    private var afterAnnounced = false
    private var outsideCount = 0
    private var lastStage: String? = null

    fun reset() {
        target = null; previous = null; direction = null; crossingAnchor = null
        motionAnchor = null; speed = null
        approaching = false; passed = false; nearObserved = false
        outsideCount = 0; lastStage = null; afterAnnounced = false
        outsideSeen = false; outsideBeforeEntry = 0
    }

    internal fun writeCheckpoint(out: DataOutputStream) = with(out) {
        writeBoolean(target != null)
        target?.let { writeUTF(it.id); writeUTF(it.label); writeDouble(it.lat); writeDouble(it.lon); writeDouble(it.radius) }
        for (fix in listOf(previous, motionAnchor, crossingAnchor)) {
            writeBoolean(fix != null)
            fix?.let { writeDouble(it.lat); writeDouble(it.lon); writeDouble(it.accuracy); writeLong(it.elapsed) }
        }
        writeBoolean(speed != null); speed?.let { writeDouble(it) }
        writeBoolean(direction != null); direction?.let { writeDouble(it.x); writeDouble(it.y) }
        for (flag in listOf(approaching, passed, nearObserved, outsideSeen, afterAnnounced)) writeBoolean(flag)
        writeInt(outsideBeforeEntry); writeInt(outsideCount)
        writeBoolean(lastStage != null); lastStage?.let { writeUTF(it) }
    }

    internal fun readCheckpoint(input: DataInputStream) {
        reset()
        target = if (input.readBoolean()) Point(input.readUTF(), input.readUTF(), input.readDouble(), input.readDouble(), input.readDouble()) else null
        fun readFix(): Fix? = if (!input.readBoolean()) null else
            Fix(input.readDouble(), input.readDouble(), input.readDouble(), input.readLong()).also {
                require(it.lat.isFinite() && abs(it.lat) <= 90 && it.lon.isFinite() && abs(it.lon) <= 180)
                require(it.accuracy.isFinite() && it.accuracy in 0.0..100.0 && it.elapsed >= 0)
            }
        previous = readFix(); motionAnchor = readFix(); crossingAnchor = readFix()
        speed = if (input.readBoolean()) input.readDouble().also { require(it.isFinite() && it in 0.0..70.0) } else null
        direction = if (input.readBoolean()) Vector(input.readDouble(), input.readDouble()).also {
            require(it.length().isFinite() && abs(it.length() - 1.0) < 0.000001)
        } else null
        approaching = input.readBoolean(); passed = input.readBoolean(); nearObserved = input.readBoolean()
        outsideSeen = input.readBoolean(); afterAnnounced = input.readBoolean()
        outsideBeforeEntry = input.readInt().also { require(it >= 0) }
        outsideCount = input.readInt().also { require(it >= 0) }
        lastStage = if (input.readBoolean()) input.readUTF() else null
    }

    private fun vector(fix: Fix, point: Point): Vector {
        val scale = 111195.0
        return Vector((fix.lon - point.lon) * scale * cos(Math.toRadians(point.lat)),
                      (fix.lat - point.lat) * scale)
    }

    fun update(fix: Fix, now: Long, points: List<Point>): Status? {
        // Reject stale/cached, future, invalid or unordered readings before any transition.
        if (!fix.lat.isFinite() || abs(fix.lat) > 90 || !fix.lon.isFinite() || abs(fix.lon) > 180 ||
            !fix.accuracy.isFinite() || fix.accuracy < 0 || fix.accuracy > 100 ||
            now - fix.elapsed !in 0..5000 ||
            previous?.let { fix.elapsed <= it.elapsed } == true) return null
        if (target != null && points.none { it.id == target!!.id && it == target }) reset()
        var justEntered = false
        if (target == null) {
            target = points.filter { it.radius > 0 && vector(fix, it).length() + fix.accuracy <= it.radius }
                .minByOrNull { vector(fix, it).length() }
            if (target == null) {
                if (points.any { vector(fix, it).length() - fix.accuracy >= it.radius + 100 }) {
                    outsideBeforeEntry++
                    if (outsideBeforeEntry >= 2) outsideSeen = true
                } else outsideBeforeEntry = 0
                previous = fix
                return null
            }
            justEntered = outsideSeen
        }
        val point = target!!
        val pos = vector(fix, point)
        val distance = pos.length()
        val prev = previous
        val dt = if (prev == null) 0L else fix.elapsed - prev.elapsed
        if (dt > 5000) {
            direction = null; crossingAnchor = null; approaching = false
            motionAnchor = null; speed = null
        }
        // Accumulate small movements until they exceed positional uncertainty.
        if (motionAnchor == null || fix.elapsed - motionAnchor!!.elapsed > 5000) {
            motionAnchor = if (dt in 500..5000) prev else fix
        }
        val motionStart = motionAnchor!!
        val motionDt = fix.elapsed - motionStart.elapsed
        val old = vector(motionStart, point)
        // Consecutive short intervals only: a tunnel or restart cannot invent a crossing.
        val movement = pos - old
        val displacement = movement.length()
        val trustworthySegment = motionDt in 500..5000 &&
            displacement > maxOf(5.0, fix.accuracy + motionStart.accuracy) &&
            displacement / (motionDt / 1000.0) <= 70
        var trend: String? = null
        val wasPassed = passed
        if (trustworthySegment) {
            speed = displacement / (motionDt / 1000.0)
            motionAnchor = fix
            val change = distance - old.length()
            val tolerance = maxOf(3.0, (fix.accuracy + motionStart.accuracy) / 2)
            if (change < -tolerance) {
                approaching = true
                trend = "approaching"
                // Establish an incoming axis only while actually heading at the point.
                if (direction == null && distance <= 250 && distance > 25 &&
                    -pos.dot(movement) / maxOf(1.0, distance * displacement) >= 0.85) {
                    direction = Vector(movement.x / displacement, movement.y / displacement)
                }
            } else if (change > tolerance) trend = "receding"
        }
        val axis = direction
        val along = axis?.let { pos.dot(it) }
        // Accuracy gates longitudinal confidence; it must not widen the road corridor.
        val lateral = axis?.let { abs(pos.x * it.y - pos.y * it.x) }
        val beforeDistance = maxOf(30.0, (speed ?: 0.0) * 2.0)
        // Keep the last confidently-before sample across uncertainty around zero.
        // Otherwise a slow -10m -> -1m -> +10m crossing would be lost.
        if (axis != null && along != null && approaching && !passed && fix.accuracy <= 15 &&
            lateral != null && lateral <= 10) {
            if (along < -fix.accuracy) crossingAnchor = fix
            else if (along > fix.accuracy) {
                val anchor = crossingAnchor
                // Two 5 s intervals may straddle an uncertain fix at zero; gaps still reset above.
                if (anchor != null && fix.elapsed - anchor.elapsed in 500..10000 && anchor.accuracy <= 15) {
                    val start = vector(anchor, point)
                    val segment = pos - start
                    val length = segment.length()
                    val duration = (fix.elapsed - anchor.elapsed) / 1000.0
                    if (length > maxOf(5.0, fix.accuracy + anchor.accuracy) && length / duration <= 70) {
                        val fraction = (-start.dot(segment) / (length * length)).coerceIn(0.0, 1.0)
                        val closest = Vector(start.x + segment.x * fraction, start.y + segment.y * fraction).length()
                        if (closest <= 10) passed = true
                    }
                }
            }
        }
        var stage = when {
            justEntered -> "entered"
            passed && !wasPassed -> if (nearObserved) "passed" else "passed_between_fixes"
            passed && along != null && along - fix.accuracy > 25 && !afterAnnounced -> "after25"
            passed -> trend ?: "in_zone"
            approaching && trend != "receding" && along != null && along < -fix.accuracy &&
                lateral != null && lateral <= 10 && distance <= beforeDistance &&
                fix.accuracy <= 15 -> "before25"
            trend != null -> trend
            else -> "in_zone"
        }
        // An early warning at speed does not mean a near fix was actually observed.
        if (stage == "before25" && distance <= 30) nearObserved = true
        if (stage == "after25") afterAnnounced = true
        if (distance - fix.accuracy >= point.radius + 100) {
            outsideCount++
            if (outsideCount >= 2) stage = "exited"
        } else outsideCount = 0
        // An early spoken warning may use this fresh motion segment. Do not
        // freeze the crossing axis at long range: a later curve must still
        // establish its own near-point geometry before passage is confirmed.
        val warningAxis = axis ?: if (distance > 250 && trustworthySegment && trend == "approaching")
            Vector(movement.x / displacement, movement.y / displacement) else null
        val warningAlong = warningAxis?.let { pos.dot(it) }
        val warningLateral = warningAxis?.let { abs(pos.x * it.y - pos.y * it.x) }
        val aligned = approaching && !passed && warningAlong != null &&
            warningAlong < -fix.accuracy && warningLateral != null && warningLateral <= 10 && fix.accuracy <= 15
        val status = Status(point.id, point.label, stage, distance, fix.accuracy, fix.elapsed, stage != lastStage, aligned)
        lastStage = stage
        previous = fix
        if (stage == "exited") { reset(); outsideSeen = true }
        return status
    }
}
