package com.zaifears.locreminder

import android.app.Activity
import android.app.Instrumentation
import android.os.Build
import android.os.Bundle
import org.json.JSONArray
import org.json.JSONObject

/** Android's real JSON and SharedPreferences, isolated from every production key. */
class AlarmStoreRecoveryCheck(private val runner: Instrumentation) {
    fun run(phase: String) {
        val result = Bundle()
        try {
            check(Build.HARDWARE in setOf("ranchu", "goldfish")) { "Emulator fixture required" }
            runner.runOnMainSync {
                val prefs = runner.targetContext.getSharedPreferences("alarm_store_recovery_fixture", 0)
                val persistence = object : AlarmPersistence {
                    override fun read(key: String) = prefs.getString(key, null)
                    override fun write(values: Map<String, String?>) {
                        val editor = prefs.edit()
                        values.forEach { (key, value) -> if (value == null) editor.remove(key) else editor.putString(key, value) }
                        check(editor.commit())
                    }
                }
                val store = AlarmStore(persistence)
                fun point(id: String) = AlarmEntry(id, "Synthetic", 0.0, 0.0, 100.0)
                when (phase) {
                    "store_write" -> {
                        check(prefs.edit().clear().commit())
                        store.save(point("one"))
                        check(store.consumeOnce("one"))
                        check(store.loadAll().isEmpty() && store.snapshot().receipts.containsKey("one"))
                    }
                    "store_read" -> {
                        val receipt = store.snapshot().receipts
                        check(store.loadAll().isEmpty() && receipt.containsKey("one"))
                        store.save(point("one"))
                        check(store.snapshot().receipts.isEmpty())
                        check(store.consumeOnce("one"))
                        val newer = store.snapshot().receipts
                        store.acknowledge(receipt)
                        check(store.snapshot().receipts == newer)
                        store.acknowledge(newer)
                        store.save(point("unrelated"))
                        val broken = JSONArray(prefs.getString(AlarmStore.KEY_ENTRIES, "[]"))
                            .put(JSONObject().put("id", "malformed")).toString()
                        check(prefs.edit().putString(AlarmStore.KEY_ENTRIES, broken).commit())
                        check(store.snapshot().corrupt && store.loadAll().single().id == "unrelated")
                        store.repairSelected(setOf("restored"), listOf(point("restored")))
                        check(!store.snapshot().corrupt)
                        check(store.loadAll().map { it.id }.toSet() == setOf("unrelated", "restored"))
                        check(prefs.getString(AlarmStore.KEY_BACKUP, null) == broken)
                        check(prefs.edit().clear().commit())
                    }
                    else -> error("Explicit phase required")
                }
            }
            result.putString("result", "passed:$phase")
            runner.finish(Activity.RESULT_OK, result)
        } catch (_: Throwable) {
            result.putString("result", "failed:$phase")
            runner.finish(Activity.RESULT_CANCELED, result)
        }
    }
}
