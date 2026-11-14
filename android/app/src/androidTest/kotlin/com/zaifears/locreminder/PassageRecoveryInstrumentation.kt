package com.zaifears.locreminder

import android.app.Activity
import android.app.Instrumentation
import android.os.Bundle
import android.os.SystemClock

/** Synthetic geometry only, in isolated preferences; never reads the user's points or position. */
class PassageRecoveryInstrumentation : Instrumentation() {
    private var phase = ""
    private var lifecycleExpected = ""
    override fun onCreate(arguments: Bundle?) {
        super.onCreate(arguments)
        phase = arguments?.getString("phase") ?: ""
        lifecycleExpected = arguments?.getString("expected") ?: ""
        start()
    }

    override fun onStart() {
        if (phase in setOf("store_write", "store_read")) {
            AlarmStoreRecoveryCheck(this).run(phase)
            return
        }
        if (phase == "voice_lifecycle") {
            VoicePreviewLifecycleCheck(this).run(lifecycleExpected)
            return
        }
        val result = Bundle()
        try {
            val store = PassageStateStore(targetContext, "passage_recovery_instrumentation")
            val metadata = targetContext.getSharedPreferences("passage_recovery_metadata", 0)
            val point = PassageTracker.Point("synthetic-test", "Synthetic point", 0.0, 0.0, 1000.0)
            val coordinator = PassageCoordinator()
            fun step(x: Double, time: Long) = coordinator.update(
                PassageTracker.Fix(0.0, x / 111195, 2.0, time), time, listOf(point))!!.presented!!
            when (phase) {
                "prepare" -> {
                    store.clear()
                    val time = SystemClock.elapsedRealtime()
                    step(-210.0, time - 4000); step(-160.0, time - 3000)
                    check(step(-20.0, time).stage == "before25")
                    store.save(coordinator, mapOf(point.id to setOf("near")))
                    check(metadata.edit().putLong("time", time).commit())
                    result.putString("proof", "Synthetic approach saved to disk")
                }
                "verify" -> {
                    val time = metadata.getLong("time", -1)
                    check(time >= 0)
                    val cues = store.restore(coordinator)
                    check(cues?.get(point.id) == setOf("near"))
                    // Fixed synthetic elapsed times keep this test independent of adb launch latency.
                    check(step(15.0, time + 1000).stage == "passed")
                    check(step(40.0, time + 2000).stage == "after25")
                    val resumed = PassageCoordinator()
                    store.restore(resumed)
                    val late = time + 10000
                    check(resumed.update(PassageTracker.Fix(0.0, 40.0 / 111195, 2.0, late), late, listOf(point))!!.presented!!.stage == "in_zone")
                    store.clear()
                    metadata.edit().clear().commit()
                    result.putString("proof", "Disk restore after process death: crossing, cues and long-gap rejection passed")
                }
                else -> error("Use phase=prepare or phase=verify")
            }
            finish(Activity.RESULT_OK, result)
        } catch (failure: Throwable) {
            result.putString("failure", failure.javaClass.simpleName + ": " + failure.message)
            finish(Activity.RESULT_CANCELED, result)
        }
    }
}
