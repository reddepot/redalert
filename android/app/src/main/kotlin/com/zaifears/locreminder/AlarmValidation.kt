package com.zaifears.locreminder

/** The same storage contract applies to individual edits, batches and repair. */
internal object AlarmValidation {
    fun requireValid(id: String, label: String, lat: Double, lon: Double, radius: Double) {
        require(id.length in 1..120 && label.length in 1..140)
        require(lat.isFinite() && lon.isFinite() && lat in -90.0..90.0 && lon in -180.0..180.0)
        require(radius.isFinite() && radius in 100.0..3000.0)
    }
}
