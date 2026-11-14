package com.zaifears.locreminder

import android.app.DownloadManager
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.net.Uri
import android.os.Environment
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.io.File

/** DownloadManager owns resumable Wi-Fi transfers even after Flutter exits. */
class OfflineMapPacks(private val context: Context) {
    private val prefs = context.getSharedPreferences("offline_packs", Context.MODE_PRIVATE)
    private val manager = context.getSystemService(DownloadManager::class.java)
    private val executor = java.util.concurrent.Executors.newSingleThreadExecutor()
    private val tileExecutor = java.util.concurrent.Executors.newSingleThreadExecutor()
    private val main = android.os.Handler(android.os.Looper.getMainLooper())
    private val databases = object : LinkedHashMap<String, SQLiteDatabase>(4, 0.75f, true) {
        override fun removeEldestEntry(eldest: MutableMap.MutableEntry<String, SQLiteDatabase>?): Boolean {
            if (size <= 4) return false
            eldest?.value?.close()
            return true
        }
    }
    private val root get() = File(requireNotNull(context.getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS)), "maps")
    private val packs by lazy {
        val json = context.assets.open("flutter_assets/assets/maps/packs.json").bufferedReader().use { JSONObject(it.readText()) }
        val list = json.getJSONArray("packs")
        (0 until list.length()).map { list.getJSONObject(it) }
    }

    fun handle(method: String, enabled: Boolean?, result: MethodChannel.Result) {
        executor.execute {
            try {
                if (method == "delete") {
                    check(prefs.edit().putBoolean("enabled", false).commit())
                    synchronized(databases) { databases.values.forEach { it.close() }; databases.clear() }
                    packs.forEach { p ->
                        val id = p.getString("id")
                        manager.remove(prefs.getLong("download:$id", -1))
                        val file = File(root, "$id.mbtiles")
                        check(!file.exists() || file.delete())
                    }
                    check(prefs.edit().clear().putBoolean("enabled", false).commit())
                }
                if (method == "setEnabled") {
                    check(prefs.edit().putBoolean("enabled", enabled == true).commit())
                    if (enabled != true) packs.forEach { pack ->
                        val id = pack.getString("id")
                        if (!prefs.getBoolean("valid:$id", false)) {
                            manager.remove(prefs.getLong("download:$id", -1))
                            prefs.edit().remove("download:$id").remove("failed:$id").apply()
                        }
                    }
                }
                if (method == "retry") packs.forEach { p ->
                    val id = p.getString("id")
                    manager.query(DownloadManager.Query().setFilterById(prefs.getLong("download:$id", -1))).use { c ->
                        if (prefs.getBoolean("failed:$id", false) || (c.moveToFirst() && c.getInt(c.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS)) == DownloadManager.STATUS_FAILED)) {
                            manager.remove(prefs.getLong("download:$id", -1))
                            prefs.edit().remove("download:$id").remove("failed:$id").apply()
                        }
                    }
                }
                if (prefs.getBoolean("enabled", true)) scheduleMissing()
                val rows = packs.map { status(it) }
                val response = mapOf("enabled" to prefs.getBoolean("enabled", true), "packs" to rows,
                    "freeBytes" to root.usableSpace, "requiredBytes" to packs.sumOf { it.getLong("bytes") })
                main.post { result.success(response) }
            } catch (_: Exception) {
                main.post { result.error("maps", "Téléchargement indisponible ; vérifier le stockage et réessayer.", null) }
            }
        }
    }

    private fun scheduleMissing() {
        check(root.mkdirs() || root.isDirectory)
        var remaining = 0L
        packs.forEach { p -> if (!prefs.getBoolean("valid:${p.getString("id")}", false)) remaining += p.getLong("bytes") }
        // Reserve headroom; never fill the phone with a country download.
        if (root.usableSpace < remaining + 512L * 1024 * 1024) return
        packs.forEach { p ->
            val id = p.getString("id")
            val download = prefs.getLong("download:$id", -1)
            val exists = if (download < 0) false else manager.query(DownloadManager.Query().setFilterById(download)).use { it.moveToFirst() }
            if (!exists && !prefs.getBoolean("valid:$id", false)) {
                val file = File(root, "$id.mbtiles")
                if (file.exists()) file.delete()
                val uri = Uri.parse(p.getString("url"))
                require(uri.scheme == "https")
                val request = DownloadManager.Request(uri)
                    .setTitle("RedAlert · carte ${id.replace('-', ' ')}")
                    .setDescription("France hors ligne · Wi-Fi uniquement")
                    .setAllowedNetworkTypes(DownloadManager.Request.NETWORK_WIFI)
                    .setAllowedOverMetered(false).setAllowedOverRoaming(false)
                    .setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE)
                    .setDestinationUri(Uri.fromFile(file))
                check(prefs.edit().putLong("download:$id", manager.enqueue(request)).commit())
            }
        }
    }

    private fun status(p: JSONObject): Map<String, Any?> {
        val id = p.getString("id")
        val file = File(root, "$id.mbtiles")
        var state = "absent"
        var bytes = 0L
        var total = p.getLong("bytes")
        val download = prefs.getLong("download:$id", -1)
        manager.query(DownloadManager.Query().setFilterById(download)).use { c ->
            if (c.moveToFirst()) {
                bytes = c.getLong(c.getColumnIndexOrThrow(DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR))
                total = c.getLong(c.getColumnIndexOrThrow(DownloadManager.COLUMN_TOTAL_SIZE_BYTES)).takeIf { it > 0 } ?: total
                state = when (c.getInt(c.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS))) {
                    DownloadManager.STATUS_SUCCESSFUL -> "downloaded"
                    DownloadManager.STATUS_FAILED -> "failed"
                    DownloadManager.STATUS_RUNNING -> "running"
                    else -> "waiting"
                }
            }
        }
        if (!file.exists() || (prefs.getBoolean("valid:$id", false) && file.length() != prefs.getLong("size:$id", -1))) {
            prefs.edit().remove("valid:$id").apply()
        }
        if (state == "downloaded" && !prefs.getBoolean("valid:$id", false)) {
            try {
                // A provider's rolling archive can change size: validate its actual HTTP size and schema.
                check(file.length() == total && total > 0)
                SQLiteDatabase.openDatabase(file.path, null, SQLiteDatabase.OPEN_READONLY).use { db ->
                    db.rawQuery("PRAGMA quick_check(1)", null).use { c -> check(c.moveToFirst() && c.getString(0) == "ok") }
                    db.rawQuery("SELECT length(tile_data) FROM tiles LIMIT 1", null).use { c -> check(c.moveToFirst() && c.getLong(0) in 1..(8L * 1024 * 1024)) }
                    val metadata = mutableMapOf<String, String>()
                    db.rawQuery("SELECT name,value FROM metadata", null).use { c -> while (c.moveToNext()) metadata[c.getString(0)] = c.getString(1) }
                    check(metadata["format"] in setOf("pbf", "mvt"))
                    check(metadata["json"]?.contains("streets") == true)
                    metadata["bounds"]?.let { prefs.edit().putString("bounds:$id", it).apply() }
                }
                check(prefs.edit().putBoolean("valid:$id", true).putLong("size:$id", file.length()).remove("failed:$id").commit())
            } catch (_: Exception) { state = "failed"; prefs.edit().putBoolean("failed:$id", true).apply() }
        }
        if (prefs.getBoolean("valid:$id", false)) { state = "ready"; bytes = file.length(); total = bytes }
        return mapOf("id" to id, "state" to state, "bytes" to bytes, "total" to total,
            "bounds" to prefs.getString("bounds:$id", ""),
            "path" to if (state == "ready") file.path else null)
    }

    fun tile(z: Int, x: Int, y: Int, result: MethodChannel.Result) {
        tileExecutor.execute {
            try {
                require(z in 0..16 && x in 0 until (1 shl z) && y in 0 until (1 shl z))
                val n = (1 shl z).toDouble()
                val west = x / n * 360 - 180
                val east = (x + 1) / n * 360 - 180
                fun latitude(row: Int) = Math.toDegrees(kotlin.math.atan(kotlin.math.sinh(Math.PI * (1 - 2 * row / n))))
                val south = latitude(y + 1)
                val north = latitude(y)
                val data = mutableListOf<ByteArray>()
                var batchBytes = 0L
                synchronized(databases) { packs.forEach { p ->
                    val id = p.getString("id")
                    if (!prefs.getBoolean("valid:$id", false)) return@forEach
                    val b = prefs.getString("bounds:$id", "")?.split(',')?.mapNotNull { it.toDoubleOrNull() }
                    if (b?.size == 4 && (east < b[0] || west > b[2] || north < b[1] || south > b[3])) return@forEach
                    val db = databases[id] ?: SQLiteDatabase.openDatabase(File(root, "$id.mbtiles").path, null, SQLiteDatabase.OPEN_READONLY).also { databases[id] = it }
                    val args = arrayOf(z.toString(), x.toString(), ((1 shl z) - 1 - y).toString())
                    // Inspect size before a blob is allocated or crosses the Flutter channel.
                    val size = db.rawQuery("SELECT length(tile_data) FROM tiles WHERE zoom_level=? AND tile_column=? AND tile_row=? LIMIT 1", args).use { c ->
                        if (c.moveToFirst()) c.getLong(0) else 0L
                    }
                    require(size in 0..(8L * 1024 * 1024) && batchBytes + size <= 16L * 1024 * 1024)
                    if (size > 0) db.rawQuery("SELECT tile_data FROM tiles WHERE zoom_level=? AND tile_column=? AND tile_row=? LIMIT 1", args).use { c ->
                        if (c.moveToFirst()) { val bytes = c.getBlob(0); require(bytes.size.toLong() == size); data.add(bytes); batchBytes += size }
                    }
                }
                }
                main.post { result.success(data) }
            } catch (_: Exception) { main.post { result.error("tile", "Carte locale indisponible", null) } }
        }
    }

    fun close() { tileExecutor.execute { synchronized(databases) { databases.values.forEach { it.close() }; databases.clear() } }; tileExecutor.shutdown(); executor.shutdown() }
}
