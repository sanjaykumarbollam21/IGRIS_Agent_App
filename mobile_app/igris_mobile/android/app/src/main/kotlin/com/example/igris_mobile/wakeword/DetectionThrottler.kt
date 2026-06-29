package com.example.igris_mobile.wakeword

import android.os.SystemClock

/**
 * Rejects a single-frame false positive by requiring the engine to be
 * confident across [requiredFrames] consecutive frames within
 * [windowMs]. After a confirmed detection, enters a [cooldownMs] silence
 * period during which no further detection can fire.
 *
 * The threshold maps the user-facing sensitivity slider (0.0..1.0) into
 * the model-score domain (0.0..1.0) using a non-linear curve so that the
 * mid-point of the slider corresponds to the model's calibrated decision
 * boundary. The mapping is intentionally generous at the low end (battery
 * saver = more rejections) and tight at the high end (sensitivity = eager
 * to trigger, more false positives).
 */
internal class DetectionThrottler(initialSensitivity: Float) {

    /** User-facing sensitivity 0..1. Mutates [threshold]. */
    var threshold: Float = sensitivityToThreshold(initialSensitivity)

    private val requiredFrames = 3
    private val windowMs = 1_500L
    private val cooldownMs = 2_000L
    private val recentScores = ArrayDeque<Pair<Float, Long>>()
    private var lastEmittedAt = 0L
    private var inCooldown = false

    /**
     * Feed a new score (positive class confidence, 0..1). If the score
     * exceeds [threshold] for [requiredFrames] consecutive frames within
     * [windowMs] and we are not in cooldown, [onFire] is invoked exactly
     * once and a cooldown is started.
     */
    fun offer(score: Float, onFire: (Float) -> Unit) {
        val now = SystemClock.elapsedRealtime()
        if (inCooldown) {
            // Discard scores during cooldown; only reset when ambient drops
            // (see onSilence) so we don't fire on the tail of "Hey IGRIS".
            return
        }
        if (score < threshold) {
            // Below threshold — clear the rolling window so a new phrase
            // has to re-accumulate the required frame count.
            recentScores.clear()
            return
        }
        recentScores.addLast(score to now)
        // Drop scores that fell out of the rolling window.
        while (recentScores.isNotEmpty() && now - recentScores.first().second > windowMs) {
            recentScores.removeFirst()
        }
        if (recentScores.size >= requiredFrames) {
            val maxScore = recentScores.maxOf { it.first }
            recentScores.clear()
            inCooldown = true
            lastEmittedAt = now
            onFire(maxScore)
        }
    }

    /** Called when the VAD gate reports silence. Ends the cooldown. */
    fun onSilence() {
        val now = SystemClock.elapsedRealtime()
        if (inCooldown && now - lastEmittedAt >= cooldownMs) {
            inCooldown = false
        }
        // Always clear the rolling window on silence — if the user stops
        // mid-utterance, we want a fresh start.
        if (recentScores.isNotEmpty() && (now - recentScores.last().second) > windowMs) {
            recentScores.clear()
        }
    }

    /**
     * Maps a 0..1 sensitivity slider into a 0..1 score threshold using a
     * smooth curve. Center of the slider (0.5) maps to 0.5; 0.0 maps to
     * 0.85 (very strict); 1.0 maps to 0.15 (very eager). This is the curve
     * openWakeWord's authors recommend as a starting point.
     */
    private fun sensitivityToThreshold(s: Float): Float {
        val clamped = s.coerceIn(0f, 1f)
        return 0.85f - 0.70f * clamped
    }
}
