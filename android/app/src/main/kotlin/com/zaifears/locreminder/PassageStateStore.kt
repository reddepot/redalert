package com.zaifears.locreminder

import android.content.Context
import android.os.SystemClock
import android.provider.Settings
import android.util.Base64
import android.util.Log

/** Local, overwritten checkpoint; elapsed times are valid only within the same device boot. */
internal class PassageStateStore(context: Context, preferencesName: String = "passage_state") {
    private val prefs = context.getSharedPreferences(preferencesName, Context.MODE_PRIVATE)
    private val boot = Settings.Global.getInt(context.contentResolver, Settings.Global.BOOT_COUNT, -1)

    fun restore(coordinator: PassageCoordinator): Map<String, Set<String>>? {
        val restored = runCatching {
            val encoded = prefs.getString("checkpoint", null) ?: return null
            require(encoded.length <= 6 * 1024 * 1024)
            PassageCheckpoint.restore(Base64.decode(encoded, Base64.NO_WRAP), coordinator, boot, SystemClock.elapsedRealtime())
        }.getOrNull()
        if (restored == null) clear()
        return restored
    }

    fun save(coordinator: PassageCoordinator, announced: Map<String, Set<String>>, durable: Boolean = true) {
        if (boot < 0) return
        runCatching {
            val encoded = Base64.encodeToString(PassageCheckpoint.encode(coordinator, announced, boot), Base64.NO_WRAP)
            val editor = prefs.edit().putString("checkpoint", encoded)
            // Transitions/cues are flushed before returning. Routine motion uses
            // SharedPreferences' ordered background writer, keeping fsync off the main looper.
            if (durable) check(editor.commit()) else editor.apply()
        }.onFailure { Log.w("PassageStateStore", "Could not persist passage state") }
    }

    fun clear() {
        prefs.edit().remove("checkpoint").apply()
    }
}
