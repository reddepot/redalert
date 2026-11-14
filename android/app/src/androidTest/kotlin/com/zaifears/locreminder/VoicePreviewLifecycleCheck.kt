package com.zaifears.locreminder

import android.app.Activity
import android.app.Instrumentation
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.os.SystemClock
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/** Unshrunk-APK lifecycle check, restricted to the isolated Android emulator. */
class VoicePreviewLifecycleCheck(private val runner: Instrumentation) {
    fun run(expected: String) {
        val result = Bundle()
        var replacement: Activity? = null
        try {
            check(Build.HARDWARE in setOf("ranchu", "goldfish")) { "Emulator fixture required" }
            check(expected in setOf("completed", "interrupted")) { "Explicit expectation required" }
            val name = "com.zaifears.locreminder.MainActivity"
            val activity = runner.startActivitySync(Intent().setClassName(runner.targetContext.packageName, name)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            val monitor = runner.addMonitor(name, null, false)
            val started = CountDownLatch(1)
            val completed = CountDownLatch(1)
            var controller: Any? = null
            var accepted = false
            runner.runOnMainSync {
                val accessor = activity.javaClass.declaredMethods.firstOrNull {
                    it.name == "getVoicePreviewController" && it.parameterCount == 0
                }
                if (accessor != null) {
                    accessor.isAccessible = true
                    controller = accessor.invoke(activity)
                    val startMethod = controller!!.javaClass.declaredMethods.first {
                        it.name == "start" && it.parameterCount == 2
                    }
                    accepted = startMethod.invoke(controller, "highSpeedBump_300", 0L) == true
                } else {
                    // Read-only reflection permits the same fixture against catalogue.13.
                    val getter = activity.javaClass.getDeclaredMethod("getPreviewVoice")
                    getter.isAccessible = true
                    val player = getter.invoke(activity)
                    val play = player.javaClass.declaredMethods.first {
                        it.name == "play" && it.parameterCount == 7
                    }
                    val valid: () -> Boolean = { true }
                    val onStart: () -> Unit = { started.countDown() }
                    val failed: () -> Unit = {}
                    val onComplete: () -> Unit = { completed.countDown() }
                    accepted = play.invoke(player, "highSpeedBump_300", true, false,
                        valid, onStart, failed, onComplete) == true
                }
            }
            check(accepted) { "Preview was not accepted" }
            fun snapshot(): Map<*, *> {
                var value: Map<*, *> = emptyMap<Any, Any>()
                runner.runOnMainSync {
                    val method = controller!!.javaClass.getDeclaredMethod("snapshot")
                    value = method.invoke(controller) as Map<*, *>
                }
                return value
            }
            val prepareDeadline = SystemClock.elapsedRealtime() + 3000
            while (controller != null && SystemClock.elapsedRealtime() < prepareDeadline) {
                if (snapshot()["state"] == "playing") { started.countDown(); break }
                Thread.sleep(20)
            }
            check(started.await(3, TimeUnit.SECONDS)) { "Playback never started" }
            runner.runOnMainSync { activity.recreate() }
            replacement = runner.waitForMonitorWithTimeout(monitor, 10000)
            runner.removeMonitor(monitor)
            check(replacement != null && replacement !== activity && activity.isDestroyed) {
                "Activity recreation was not observed"
            }
            val didComplete = if (controller != null) {
                val deadline = SystemClock.elapsedRealtime() + 5000
                while (snapshot()["state"] in setOf("scheduled", "preparing", "playing") &&
                    SystemClock.elapsedRealtime() < deadline) Thread.sleep(30)
                snapshot()["state"] == "completed"
            } else completed.await(4, TimeUnit.SECONDS)
            result.putBoolean("started_before_recreation", true)
            result.putBoolean("activity_recreated", true)
            result.putBoolean("completed_after_recreation", didComplete)
            result.putString("observed", if (didComplete) "completed" else "interrupted")
            check(didComplete == (expected == "completed")) { "Unexpected playback lifecycle outcome" }
            result.putString("proof", "Synthetic APK preview lifecycle matched the explicit expectation")
            runner.runOnMainSync { replacement?.finish() }
            runner.finish(Activity.RESULT_OK, result)
        } catch (failure: Throwable) {
            result.putString("failure", failure.javaClass.simpleName + ": " + failure.message)
            replacement?.let { runner.runOnMainSync { it.finish() } }
            runner.finish(Activity.RESULT_CANCELED, result)
        }
    }
}
