package com.zaifears.locreminder

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

/**
 * A saved destination alarm, mirrored on the native side so the
 * BroadcastReceiver / BootReceiver can act without the Flutter engine running.
 */
data class AlarmEntry(
    val id: String,
    val label: String,
    val latitude: Double,
    val longitude: Double,
    val radius: Double,
    /**
     * Weekdays this alarm is armed on, 1 = Monday through 7 = Sunday, matching
     * Dart's `DateTime.weekday`. Empty means it fires once and is deleted,
     * which is what every alarm saved before repeats existed becomes.
     */
    val repeatDays: Set<Int> = emptySet(),
    val repeatOnEveryEntry: Boolean = false,
    /**
     * Posted limit in km/h when the catalogue states one. Null means the
     * source is silent, which must stay distinct from a 0 limit: the speed
     * warning only fires where a real number is known.
     */
    val speedLimitKmh: Int? = null,
    /** Department the point was imported for, used to group reference points. */
    val department: String? = null,
    val poiType: String = "other",
    val travelBearingDegrees: Double? = null,
) {
    val repeats: Boolean get() = repeatOnEveryEntry || repeatDays.isNotEmpty()
    val oncePerDay: Boolean get() = repeats && !repeatOnEveryEntry

    /** Whether this alarm is allowed to ring on [isoWeekday] (1 = Monday). */
    fun ringsOn(isoWeekday: Int): Boolean =
        repeatDays.isEmpty() || isoWeekday in repeatDays
}

/**
 * Plain SharedPreferences-backed store, independent from the
 * shared_preferences Flutter plugin's own storage so native code never
 * depends on the Dart side being alive to read alarm metadata.
 */
internal interface AlarmPersistence {
    fun read(key: String): String?
    /** All keys are committed atomically, including removals represented by null. */
    fun write(values: Map<String, String?>)
}

private class AndroidAlarmPersistence(context: Context) : AlarmPersistence {
    private val prefs = context.getSharedPreferences("locreminder_geofences", Context.MODE_PRIVATE)
    override fun read(key: String): String? = prefs.getString(key, null)
    override fun write(values: Map<String, String?>) {
        val editor = prefs.edit()
        values.forEach { (key, value) -> if (value == null) editor.remove(key) else editor.putString(key, value) }
        check(editor.commit()) { "Alarm storage write failed" }
    }
}

internal data class AlarmSnapshot(
    val entries: List<AlarmEntry>,
    val receipts: Map<String, String>,
    val invalidRecords: Int = 0,
    val corrupt: Boolean = false,
)

internal class AlarmStorageCorrupt : IllegalStateException("Alarm storage needs repair")

class AlarmStore internal constructor(private val persistence: AlarmPersistence) {
    constructor(context: Context) : this(AndroidAlarmPersistence(context))


    internal fun snapshot(): AlarmSnapshot {
        val raw = persistence.read(KEY_ENTRIES)
        if (!hasCache || raw != cachedRaw) {
            val parsed = decodeEntries(raw)
            cachedEntries = parsed.entries
            cachedInvalid = parsed.invalidRecords
            cachedCorrupt = parsed.corrupt
            cachedRaw = raw
            hasCache = true
        }
        val receipts = decodeReceipts(persistence.read(KEY_RECEIPTS))
        return AlarmSnapshot(cachedEntries, receipts.first, cachedInvalid, cachedCorrupt || receipts.second)
    }

    /** Valid records remain monitorable; corrupt bytes are preserved until explicit repair. */
    fun loadAll(): List<AlarmEntry> = snapshot().entries
    fun getById(id: String): AlarmEntry? = loadAll().find { it.id == id }

    fun save(entry: AlarmEntry) = replaceSelected(setOf(entry.id), listOf(entry))

    fun replaceSelected(ids: Set<String>, entries: List<AlarmEntry>) {
        require(entries.all { it.id in ids })
        val before = healthy()
        persist(before.entries.filterNot { it.id in ids } + entries, before.receipts - ids)
    }

    fun remove(id: String) = replaceSelected(setOf(id), emptyList())

    /** Consumption and its positive service receipt are one durable write. */
    internal fun consumeOnce(id: String): Boolean {
        val before = healthy()
        val entry = before.entries.firstOrNull { it.id == id } ?: return false
        if (entry.repeats) return false
        // Never silently evict an unacknowledged receipt and later resurrect its alarm.
        check(before.receipts.size < MAX_RECEIPTS) { "Receipt capacity reached" }
        persist(before.entries.filterNot { it.id == id }, before.receipts + (id to java.util.UUID.randomUUID().toString()))
        return true
    }

    internal fun acknowledge(receipts: Map<String, String>) {
        val before = healthy()
        val retained = before.receipts.filterNot { (id, token) -> receipts[id] == token }
        if (retained != before.receipts) persist(before.entries, retained)
    }

    /** The UI explicitly confirms repair from its saved list; unrelated valid rows survive. */
    internal fun repairSelected(ids: Set<String>, entries: List<AlarmEntry>) {
        require(entries.all { it.id in ids })
        val before = snapshot()
        val repaired = before.entries.filterNot { it.id in ids } + entries
        val values = encoded(repaired, before.receipts - ids).toMutableMap()
        values[KEY_BACKUP] = persistence.read(KEY_ENTRIES)
        values[KEY_BACKUP_RECEIPTS] = persistence.read(KEY_RECEIPTS)
        persistence.write(values)
        hasCache = false
    }

    fun clear() {
        persistence.write(mapOf(KEY_ENTRIES to null, KEY_RECEIPTS to null, KEY_BACKUP to null, KEY_BACKUP_RECEIPTS to null))
        hasCache = false
    }

    private fun healthy(): AlarmSnapshot = snapshot().also { if (it.corrupt) throw AlarmStorageCorrupt() }
    private fun persist(entries: List<AlarmEntry>, receipts: Map<String, String>) {
        persistence.write(encoded(entries, receipts))
        hasCache = false
    }

    private fun encoded(entries: List<AlarmEntry>, receipts: Map<String, String>): Map<String, String?> {
        require(entries.map { it.id }.toSet().size == entries.size)
        val array = JSONArray()
        entries.forEach { e ->
            AlarmValidation.requireValid(e.id, e.label, e.latitude, e.longitude, e.radius)
            val obj = JSONObject()
            obj.put("id", e.id).put("label", e.label).put("latitude", e.latitude)
                .put("longitude", e.longitude).put("radius", e.radius)
                .put("repeatDays", JSONArray(e.repeatDays.sorted()))
                .put("repeatOnEveryEntry", e.repeatOnEveryEntry).put("poiType", e.poiType)
            e.travelBearingDegrees?.let { obj.put("travelBearingDegrees", it) }
            e.speedLimitKmh?.let { obj.put("speedLimitKmh", it) }
            e.department?.let { obj.put("department", it) }
            array.put(obj)
        }
        val raw = array.toString()
        require(raw.length <= MAX_RAW_CHARS) { "Alarm storage exceeds memory bound" }
        require(receipts.size <= MAX_RECEIPTS)
        val receiptArray = JSONArray()
        receipts.forEach { (id, token) -> receiptArray.put(JSONObject().put("id", id).put("token", token)) }
        val receiptRaw = receiptArray.toString()
        require(receiptRaw.length <= MAX_RECEIPT_CHARS)
        return mapOf(KEY_ENTRIES to raw, KEY_RECEIPTS to receiptRaw)
    }

    companion object {
    private var cachedRaw: String? = null
    private var cachedEntries: List<AlarmEntry> = emptyList()
    private var cachedInvalid = 0
    private var cachedCorrupt = false
    private var hasCache = false

        internal const val KEY_ENTRIES = "entries"
        internal const val KEY_RECEIPTS = "consumed_receipts_v1"
        internal const val KEY_BACKUP = "repair_backup_entries_v1"
        internal const val KEY_BACKUP_RECEIPTS = "repair_backup_receipts_v1"
        internal const val MAX_RECEIPTS = 512
        internal const val MAX_RECEIPT_CHARS = 1024 * 1024
        internal const val MAX_RAW_CHARS = 16 * 1024 * 1024

        internal fun decodeEntries(raw: String?): AlarmSnapshot {
            if (raw == null) return AlarmSnapshot(emptyList(), emptyMap())
            if (raw.length > MAX_RAW_CHARS) return AlarmSnapshot(emptyList(), emptyMap(), 1, true)
            val array = try { JSONArray(raw) } catch (_: Exception) { return AlarmSnapshot(emptyList(), emptyMap(), 1, true) }
            val entries = mutableListOf<AlarmEntry>()
            val ids = mutableSetOf<String>()
            var invalid = 0
            for (i in 0 until array.length()) {
                try {
                    val obj = array.getJSONObject(i)
                    val e = AlarmEntry(
                        obj.getString("id"), obj.getString("label"), obj.getDouble("latitude"),
                        obj.getDouble("longitude"), obj.getDouble("radius"),
                        obj.optJSONArray("repeatDays").toWeekdaySet(), obj.optBoolean("repeatOnEveryEntry", false),
                        obj.optInt("speedLimitKmh", 0).takeIf { it in 1..130 },
                        obj.optString("department", "").takeIf { it.isNotBlank() }, obj.optString("poiType", "other"),
                        obj.optDouble("travelBearingDegrees", Double.NaN).takeIf { it.isFinite() && it >= 0 && it < 360 },
                    )
                    AlarmValidation.requireValid(e.id, e.label, e.latitude, e.longitude, e.radius)
                    require(ids.add(e.id))
                    entries.add(e)
                } catch (_: Exception) { invalid++ }
            }
            return AlarmSnapshot(entries, emptyMap(), invalid, invalid > 0)
        }

        private fun decodeReceipts(raw: String?): Pair<Map<String, String>, Boolean> {
            if (raw == null) return emptyMap<String, String>() to false
            return try {
                require(raw.length <= MAX_RECEIPT_CHARS)
                val array = JSONArray(raw)
                require(array.length() <= MAX_RECEIPTS)
                val values = linkedMapOf<String, String>()
                for (i in 0 until array.length()) {
                    val item = array.getJSONObject(i)
                    val id = item.getString("id"); val token = item.getString("token")
                    require(id.length in 1..120 && token.length in 1..100 && values.put(id, token) == null)
                }
                values to false
            } catch (_: Exception) { emptyMap<String, String>() to true }
        }
    }
}

/**
 * Reads a weekday array, dropping anything outside 1..7.
 *
 * Absent on every record written before repeats existed, and null is the
 * honest answer for those: they were one-shot alarms, and an empty set is
 * exactly that.
 *
 * Top-level rather than a member of the companion: a member extension needs
 * both its receivers in scope at the call site, which is a subtlety this does
 * not need to depend on.
 */
private fun JSONArray?.toWeekdaySet(): Set<Int> {
    if (this == null) return emptySet()
    val days = mutableSetOf<Int>()
    for (i in 0 until length()) {
        val day = optInt(i, -1)
        if (day in 1..7) days.add(day)
    }
    return days
}
