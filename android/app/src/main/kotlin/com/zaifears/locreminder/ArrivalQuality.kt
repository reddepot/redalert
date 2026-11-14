package com.zaifears.locreminder

/** The reported uncertainty must fit inside the user-selected destination zone. */
internal object ArrivalQuality {
    fun confirms(distance: Double, accuracy: Double?, radius: Double): Boolean =
        distance.isFinite() && distance >= 0 && accuracy != null && accuracy.isFinite() &&
            accuracy >= 0 && radius.isFinite() && radius > 0 && distance + accuracy <= radius
}
