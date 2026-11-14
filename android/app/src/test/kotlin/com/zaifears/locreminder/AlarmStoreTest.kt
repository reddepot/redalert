package com.zaifears.locreminder

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class AlarmStoreTest {
    private class Memory : AlarmPersistence {
        val values = mutableMapOf<String, String>()
        var fail = false
        override fun read(key: String) = values[key]
        override fun write(values: Map<String, String?>) {
            check(!fail)
            values.forEach { (key, value) -> if (value == null) this.values.remove(key) else this.values[key] = value }
        }
    }
    private fun point(id: String, repeating: Boolean = false) =
        AlarmEntry(id, "Synthetic", 0.0, 0.0, 100.0, repeatOnEveryEntry = repeating)

    @Test fun lastOneShotLeavesAPositiveReceiptAcrossStoreRecreation() {
        val data = Memory(); val store = AlarmStore(data)
        store.save(point("once")); assertTrue(store.consumeOnce("once"))
        val restarted = AlarmStore(data).snapshot()
        assertTrue(restarted.entries.isEmpty())
        assertTrue(restarted.receipts.containsKey("once"))
        assertFalse(restarted.corrupt)
    }
    @Test fun failedConsumptionWritePreservesAlarmAndDoesNotInventReceipt() {
        val data = Memory(); val store = AlarmStore(data)
        store.save(point("once")); data.fail = true
        assertThrows(IllegalStateException::class.java) { store.consumeOnce("once") }
        assertEquals(listOf("once"), store.loadAll().map { it.id })
        assertTrue(store.snapshot().receipts.isEmpty())
    }
    @Test fun repeatingPointCannotBeConsumed() {
        val store = AlarmStore(Memory()); store.save(point("repeat", true))
        assertFalse(store.consumeOnce("repeat"))
        assertEquals(1, store.loadAll().size)
        assertTrue(store.snapshot().receipts.isEmpty())
    }
    @Test fun rearmingClearsOldReceiptAndOldAcknowledgementCannotEraseNewReceipt() {
        val store = AlarmStore(Memory()); store.save(point("once")); store.consumeOnce("once")
        val old = store.snapshot().receipts
        store.save(point("once")); assertTrue(store.snapshot().receipts.isEmpty())
        store.consumeOnce("once")
        val current = store.snapshot().receipts
        assertNotEquals(old, current)
        store.acknowledge(old); assertEquals(current, store.snapshot().receipts)
        store.acknowledge(current); assertTrue(store.snapshot().receipts.isEmpty())
    }
    @Test fun corruptRowDoesNotCrashOrEraseValidRowsAndBlocksNormalWrites() {
        val data = Memory(); val store = AlarmStore(data)
        store.save(point("valid"))
        val raw = JSONArray(data.read(AlarmStore.KEY_ENTRIES)).put(JSONObject().put("id", "broken")).toString()
        data.values[AlarmStore.KEY_ENTRIES] = raw
        val snapshot = store.snapshot()
        assertTrue(snapshot.corrupt); assertEquals(1, snapshot.invalidRecords)
        assertEquals(listOf("valid"), snapshot.entries.map { it.id })
        assertThrows(AlarmStorageCorrupt::class.java) { store.save(point("new")) }
        assertEquals(raw, data.read(AlarmStore.KEY_ENTRIES))
    }
    @Test fun explicitRepairPreservesOriginalBytesAndUnrelatedValidRows() {
        val data = Memory(); val store = AlarmStore(data)
        store.save(point("unrelated")); store.save(point("selected"))
        val raw = JSONArray(data.read(AlarmStore.KEY_ENTRIES)).put("broken").toString()
        data.values[AlarmStore.KEY_ENTRIES] = raw
        store.repairSelected(setOf("selected", "restored"), listOf(point("restored")))
        assertFalse(store.snapshot().corrupt)
        assertEquals(setOf("unrelated", "restored"), store.loadAll().map { it.id }.toSet())
        assertEquals(raw, data.read(AlarmStore.KEY_BACKUP))
    }
    @Test fun failedRepairDoesNotTouchRawStoreOrBackup() {
        val data = Memory(); data.values[AlarmStore.KEY_ENTRIES] = "[truncated"
        val store = AlarmStore(data); data.fail = true
        assertThrows(IllegalStateException::class.java) { store.repairSelected(setOf("one"), listOf(point("one"))) }
        assertEquals("[truncated", data.read(AlarmStore.KEY_ENTRIES))
        assertNull(data.read(AlarmStore.KEY_BACKUP))
    }
    @Test fun malformedReceiptDoesNotBecomeMissingAlarmEvidence() {
        val data = Memory(); val store = AlarmStore(data); store.save(point("one"))
        data.values[AlarmStore.KEY_RECEIPTS] = "[broken"
        assertTrue(store.snapshot().corrupt)
        assertTrue(store.snapshot().receipts.isEmpty())
        assertEquals(1, store.loadAll().size)
    }
    @Test fun receiptSaturationKeepsEveryUnacknowledgedReceiptAndNewAlarm() {
        val data = Memory(); val store = AlarmStore(data); store.save(point("one"))
        val receipts = JSONArray()
        for (i in 0 until AlarmStore.MAX_RECEIPTS) receipts.put(JSONObject().put("id", "old-$i").put("token", "token-$i"))
        data.values[AlarmStore.KEY_RECEIPTS] = receipts.toString()
        assertThrows(IllegalStateException::class.java) { store.consumeOnce("one") }
        assertEquals(AlarmStore.MAX_RECEIPTS, store.snapshot().receipts.size)
        assertEquals(listOf("one"), store.loadAll().map { it.id })
    }
    @Test fun malformedEnvelopeIsReportedAndOnlyExplicitRepairReplacesIt() {
        val data = Memory(); data.values[AlarmStore.KEY_ENTRIES] = "not JSON"
        val store = AlarmStore(data)
        assertTrue(store.snapshot().corrupt); assertTrue(store.loadAll().isEmpty())
        store.repairSelected(setOf("one"), listOf(point("one")))
        assertEquals("not JSON", data.read(AlarmStore.KEY_BACKUP))
        assertEquals(listOf("one"), store.loadAll().map { it.id })
    }
    @Test fun validEscapedIdentifiersRoundTripWithoutExceedingTheReceiptBudget() {
        val data = Memory(); val store = AlarmStore(data); store.save(point("one"))
        val receipts = JSONArray()
        for (i in 0 until AlarmStore.MAX_RECEIPTS) {
            receipts.put(JSONObject().put("id", i.toString() + "\u0001".repeat(117)).put("token", "token-$i"))
        }
        data.values[AlarmStore.KEY_RECEIPTS] = receipts.toString()
        assertFalse(store.snapshot().corrupt)
        val first = store.snapshot().receipts.entries.first()
        store.acknowledge(mapOf(first.key to first.value))
        assertFalse(store.snapshot().corrupt)
        assertEquals(AlarmStore.MAX_RECEIPTS - 1, store.snapshot().receipts.size)
    }
    @Test fun countrySizedSyntheticStoreHasNoFiveThousandPointCeiling() {
        val data = Memory(); val store = AlarmStore(data)
        val points = (0 until 20000).map { point("synthetic-$it", true) }
        val start = System.nanoTime()
        store.replaceSelected(points.map { it.id }.toSet(), points)
        val encoded = System.nanoTime()
        assertEquals(20000, AlarmStore(data).loadAll().size)
        val decoded = System.nanoTime()
        repeat(100) { assertEquals(20000, AlarmStore(data).loadAll().size) }
        val cached = System.nanoTime()
        println("Synthetic host profile: rows=20000 chars=${data.read(AlarmStore.KEY_ENTRIES)!!.length} encodeMs=${(encoded-start)/1000000} decodeMs=${(decoded-encoded)/1000000} cached100Ms=${(cached-decoded)/1000000}")
    }
}
