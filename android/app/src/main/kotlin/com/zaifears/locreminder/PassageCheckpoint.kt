package com.zaifears.locreminder

import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.DataInputStream
import java.io.DataOutputStream

/** One current state per nearby point, never an append-only location history. */
internal object PassageCheckpoint {
    private const val VERSION = 1
    private const val MAX_BYTES = 4 * 1024 * 1024
    private val cues = setOf("entered", "near", "passed")

    fun encode(coordinator: PassageCoordinator, announced: Map<String, Set<String>>, boot: Int): ByteArray {
        val bytes = ByteArrayOutputStream()
        DataOutputStream(bytes).use { out ->
            out.writeInt(VERSION); out.writeInt(boot)
            coordinator.writeCheckpoint(out)
            val liveIds = coordinator.points().keys
            val live = announced.filterKeys { it in liveIds }
            out.writeInt(live.size)
            for ((id, played) in live) {
                out.writeUTF(id)
                val known = played.intersect(cues)
                out.writeInt(known.size); known.forEach { out.writeUTF(it) }
            }
        }
        return bytes.toByteArray().also { require(it.size <= MAX_BYTES) }
    }

    fun restore(bytes: ByteArray, coordinator: PassageCoordinator, boot: Int, now: Long): Map<String, Set<String>>? {
        return try {
            require(boot >= 0 && bytes.size <= MAX_BYTES)
            // Decode separately: a truncated file must not leave half a restore.
            val restored = PassageCoordinator()
            val announced = mutableMapOf<String, Set<String>>()
            DataInputStream(ByteArrayInputStream(bytes)).use { input ->
                require(input.readInt() == VERSION && input.readInt() == boot)
                restored.readCheckpoint(input, now)
                val liveIds = restored.points().keys
                val count = input.readInt().also { require(it in 0..5000) }
                repeat(count) {
                    val id = input.readUTF()
                    require(id in liveIds && id !in announced)
                    val size = input.readInt().also { require(it in 0..cues.size) }
                    announced[id] = (0 until size).map { input.readUTF().also { cue -> require(cue in cues) } }.toSet()
                }
                require(input.available() == 0)
            }
            val state = ByteArrayOutputStream()
            DataOutputStream(state).use { restored.writeCheckpoint(it) }
            DataInputStream(ByteArrayInputStream(state.toByteArray())).use { coordinator.readCheckpoint(it, now) }
            announced
        } catch (_: Exception) {
            null
        }
    }
}
