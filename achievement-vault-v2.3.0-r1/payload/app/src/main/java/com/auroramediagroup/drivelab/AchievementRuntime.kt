package com.auroramediagroup.drivelab

import java.util.ArrayDeque
import kotlin.math.abs
import kotlin.math.floor
import kotlin.math.max

/**
 * Tracks the live and drive-scoped measurements used by Achievement Vault v2.
 * All values come from DriveLab's existing OutGauge, MotionSim, and analyzer data.
 */
class AchievementRuntime {
    private val stats = mutableMapOf<String, Double>()

    private var ready = false
    private var runtimeDriveActive = false
    private var driveSeconds = 0.0
    private var driveMaxSpeedMph = 0.0
    private var driveThrottleIntegral = 0.0
    private var driveBrakeTouched = false
    private var driveHadDrift = false
    private var driveHadQuarter = false
    private var driveHadBrakeTest = false
    private var driveHadCrash = false
    private var driveHadLimiter = false
    private var driveHadRollover = false
    private var driveCrashCount = 0
    private var driveStartAbuse = 0
    private var driveHardBrakeStart = 0
    private val driveDisciplines = mutableSetOf<String>()

    private var lastPerfectShifts = 0
    private var lastGoodShifts = 0
    private var lastEarlyShifts = 0
    private var lastLateShifts = 0
    private var lastSlowShifts = 0
    private var currentPerfectShiftStreak = 0
    private var lastGearRaw = 1
    private var previousRpm = 0.0
    private var previousThrottle = 0.0
    private val gearChangeTimes = ArrayDeque<Long>()
    private var lastGearBurstAtMs = 0L

    private var lastZeroTo60Present = false
    private var lastQuarterPresent = false
    private var lastBrake60Present = false
    private var lastBrake100Present = false
    private var lastCrashId: String? = null
    private var lastSpinCount = 0
    private var lastShockEvents = 0
    private var lastHardBrakeEvents = 0

    private var fullThrottleStreak = 0.0
    private var noBrakeStreak = 0.0
    private var noThrottleStreak = 0.0
    private var coastStreak = 0.0
    private var reverseStreak = 0.0
    private var throttleBrakeStreak = 0.0
    private var allPedalsStreak = 0.0
    private var neutralCoastStreak = 0.0
    private var highSpeedStreak = 0.0
    private var airborneStreak = 0.0
    private var redlineStreak = 0.0
    private var speedHoldStreak = 0.0
    private var speedHoldAnchorMph: Double? = null
    private var postCrashStreak = 0.0

    private var driftStreak = 0.0
    private var leftDriftStreak = 0.0
    private var rightDriftStreak = 0.0
    private var driftStintBrakeMax = 0.0
    private var driftStintSpeedMax = 0.0
    private var lastDriftSign = 0
    private var lastTransitionAtMs = 0L
    private var driftSaveArmed = false
    private var driftSaveCrashId: String? = null
    private var chaosActive = false

    private var limiterActive = false
    private var overheatActive = false
    private var upsideDown = false
    private var highDynamicsActive = false
    private var highDynamicsCrashCount = 0

    private var stopAndGoArmedAtMs = 0L
    private var crashAtMs = 0L
    private var crashRecoveryAwarded = false
    private var postCrashThirtyAwarded = false

    private var topSpeedBucket = 0
    private var driftScoreBucket = 0
    private var driftAngleBucket = 0
    private var totalGBucket = 0

    fun sync(progress: DriverProgress, analyzer: AnalyzerState) {
        stats.clear()
        stats.putAll(progress.achievementStats)
        runtimeDriveActive = false
        resetDriveState(analyzer)
        resetTransientStreaks()
        syncBaselines(analyzer)
        topSpeedBucket = floor(progress.topSpeedMph / 10.0).toInt()
        driftScoreBucket = floor(progress.bestDriftScore / 5_000.0).toInt()
        driftAngleBucket = floor(progress.bestDriftAngleDeg / 5.0).toInt()
        totalGBucket = floor(value(AchievementMetric.MAX_TOTAL_G) / 0.5).toInt()
        ready = true
    }

    fun reset(progress: DriverProgress = DriverProgress(), analyzer: AnalyzerState = AnalyzerState()) {
        ready = false
        gearChangeTimes.clear()
        lastGearBurstAtMs = 0L
        crashAtMs = 0L
        stopAndGoArmedAtMs = 0L
        crashRecoveryAwarded = false
        postCrashThirtyAwarded = false
        sync(progress, analyzer)
    }

    fun update(
        frame: TelemetryFrame,
        analyzer: AnalyzerState,
        dtSeconds: Double,
        redlineRpm: Int,
        driveActive: Boolean
    ) {
        if (!ready) return
        val dt = dtSeconds.coerceIn(0.0, 0.5)
        val now = maxOf(frame.outGauge?.receivedAtMs ?: 0L, frame.motion?.receivedAtMs ?: 0L)
            .takeIf { it > 0L } ?: System.currentTimeMillis()
        val out = frame.outGauge
        val derived = frame.motionDerived
        val motion = frame.motion
        val speedMph = frame.speedMph
        val throttle = out?.throttle ?: 0.0
        val brake = out?.brake ?: 0.0
        val clutch = out?.clutch ?: 0.0
        val rpm = out?.rpm ?: 0.0
        val gearRaw = out?.gearRaw ?: lastGearRaw
        val driftAngle = derived?.driftAngleDeg ?: 0.0
        val totalG = derived?.totalG ?: motion?.accelerationG ?: 0.0
        val lateralG = abs(derived?.lateralG ?: 0.0)
        val verticalG = abs(derived?.verticalG ?: 0.0)
        val brakingG = abs((derived?.longitudinalG ?: 0.0).coerceAtMost(0.0))
        val rollDeg = abs(derived?.rollDeg ?: motion?.rollDeg ?: 0.0)
        val pitchDeg = abs(derived?.pitchDeg ?: motion?.pitchDeg ?: 0.0)
        val yawRate = abs(derived?.yawRateDegPerSec ?: 0.0)
        val verticalSpeed = abs(derived?.verticalSpeedMps ?: motion?.velZ ?: 0.0)
        val moving = speedMph > 2.0 || throttle > 0.12

        if (driveActive && !runtimeDriveActive) startDrive(analyzer)
        runtimeDriveActive = driveActive

        maxValue(AchievementMetric.MAX_RPM, rpm)
        maxValue(AchievementMetric.MAX_TURBO_BAR, out?.turboBar ?: 0.0)
        maxValue(AchievementMetric.MAX_ENGINE_TEMP_C, out?.engineTempC ?: 0.0)
        maxValue(AchievementMetric.MAX_OIL_TEMP_C, out?.oilTempC ?: 0.0)
        maxValue(AchievementMetric.MAX_TOTAL_G, totalG)
        maxValue(AchievementMetric.MAX_LATERAL_G, lateralG)
        maxValue(AchievementMetric.MAX_VERTICAL_G, verticalG)
        maxValue(AchievementMetric.MAX_BRAKING_G, max(brakingG, analyzer.brake.peakDecelG))
        maxValue(AchievementMetric.MAX_ROLL_DEG, rollDeg)
        maxValue(AchievementMetric.MAX_PITCH_DEG, pitchDeg)
        maxValue(AchievementMetric.MAX_YAW_RATE, yawRate)
        maxValue(AchievementMetric.MAX_LAUNCH_G, analyzer.drag.launchG)
        maxValue(AchievementMetric.BEST_SHIFT_SCORE, analyzer.shift.score.toDouble())
        analyzer.shift.bestShiftMs?.let { minPositive(AchievementMetric.BEST_SHIFT_MS, it.toDouble()) }

        if (runtimeDriveActive && dt > 0.0) {
            driveSeconds += dt
            driveMaxSpeedMph = max(driveMaxSpeedMph, speedMph)
            driveThrottleIntegral += throttle * dt
            if (brake > 0.08) driveBrakeTouched = true
        }

        updateSpeedAndPedalStats(
            dt = dt,
            moving = moving && runtimeDriveActive,
            speedMph = speedMph,
            throttle = throttle,
            brake = brake,
            clutch = clutch,
            gearRaw = gearRaw,
            totalG = totalG,
            verticalSpeed = verticalSpeed
        )
        updateShifting(now, gearRaw, rpm, throttle, clutch, redlineRpm, analyzer)
        updateDrift(now, speedMph, driftAngle, throttle, brake, totalG, analyzer)
        updateDragAndBraking(now, speedMph, out?.showLights ?: 0L, analyzer)
        updateMechanical(dt, rpm, throttle, redlineRpm, out, analyzer)
        updateDynamics(totalG, rollDeg, analyzer)
        updateCrashes(now, speedMph, analyzer)
        updateRecordBuckets(frame, analyzer, totalG)

        if (stopAndGoArmedAtMs > 0L) {
            if (now - stopAndGoArmedAtMs <= 15_000L && speedMph >= 60.0) {
                add(AchievementMetric.STOP_AND_GO_EVENTS)
                stopAndGoArmedAtMs = 0L
            } else if (now - stopAndGoArmedAtMs > 15_000L) {
                stopAndGoArmedAtMs = 0L
            }
        }

        previousRpm = rpm
        previousThrottle = throttle
        lastGearRaw = gearRaw
    }

    fun finishDrive(analyzer: AnalyzerState) {
        if (!runtimeDriveActive && driveSeconds <= 0.0) return
        val abuseDelta = (analyzer.engine.abuseScore - driveStartAbuse).coerceAtLeast(0)
        val hardBrakeDelta = (analyzer.engine.hardBrakingEvents - driveHardBrakeStart).coerceAtLeast(0)
        val clean = !driveHadCrash && abuseDelta <= 15 && driveSeconds >= 20.0

        maxValue(AchievementMetric.LONGEST_DRIVE_SECONDS, driveSeconds)
        if (clean) {
            val current = internalValue(CURRENT_CLEAN_STREAK) + 1.0
            internalSet(CURRENT_CLEAN_STREAK, current)
            maxValue(AchievementMetric.CLEAN_DRIVE_STREAK, current)
        } else {
            internalSet(CURRENT_CLEAN_STREAK, 0.0)
        }
        if (!driveHadCrash && driveMaxSpeedMph >= 100.0) add(AchievementMetric.CLEAN_HIGH_SPEED_DRIVES)
        if (!driveHadCrash && driveHadDrift) add(AchievementMetric.CLEAN_DRIFT_DRIVES)
        if (!driveBrakeTouched && driveSeconds >= 30.0) add(AchievementMetric.NO_BRAKE_DRIVES)
        if (driveSeconds >= 60.0 && abuseDelta <= 10) add(AchievementMetric.LOW_ABUSE_DRIVES)
        if (driveSeconds >= 60.0 && !driveHadLimiter) add(AchievementMetric.NO_LIMITER_DRIVES)
        if (driveSeconds >= 120.0 && !driveHadCrash && driveThrottleIntegral / driveSeconds <= 0.35) {
            add(AchievementMetric.ECO_DRIVES)
        }
        if (driveDisciplines.size >= 3) add(AchievementMetric.MULTI_DISCIPLINE_DRIVES)
        if (driveHadDrift && hardBrakeDelta > 0) add(AchievementMetric.DRIFT_BRAKE_COMBOS)
        if (driveCrashCount >= 2) add(AchievementMetric.MULTI_IMPACT_DRIVES)
        if (driveDisciplines.size >= 4 || (driveHadCrash && driveHadDrift && driveHadRollover)) {
            add(AchievementMetric.CHAOS_COMBO_EVENTS)
        }

        runtimeDriveActive = false
        resetDriveState(analyzer)
        resetDriveStreaks()
    }

    fun snapshot(): Map<String, Double> = stats.toMap()

    private fun startDrive(analyzer: AnalyzerState) {
        resetDriveState(analyzer)
        runtimeDriveActive = true
    }

    private fun resetDriveState(analyzer: AnalyzerState) {
        driveSeconds = 0.0
        driveMaxSpeedMph = 0.0
        driveThrottleIntegral = 0.0
        driveBrakeTouched = false
        driveHadDrift = false
        driveHadQuarter = false
        driveHadBrakeTest = false
        driveHadCrash = false
        driveHadLimiter = false
        driveHadRollover = false
        driveCrashCount = 0
        driveStartAbuse = analyzer.engine.abuseScore
        driveHardBrakeStart = analyzer.engine.hardBrakingEvents
        driveDisciplines.clear()
    }

    private fun resetTransientStreaks() {
        resetDriveStreaks()
        driftStreak = 0.0
        leftDriftStreak = 0.0
        rightDriftStreak = 0.0
        driftStintBrakeMax = 0.0
        driftStintSpeedMax = 0.0
        lastDriftSign = 0
        driftSaveArmed = false
        chaosActive = false
        limiterActive = false
        overheatActive = false
        upsideDown = false
        highDynamicsActive = false
        speedHoldAnchorMph = null
        currentPerfectShiftStreak = 0
    }

    private fun resetDriveStreaks() {
        fullThrottleStreak = 0.0
        noBrakeStreak = 0.0
        noThrottleStreak = 0.0
        coastStreak = 0.0
        reverseStreak = 0.0
        throttleBrakeStreak = 0.0
        allPedalsStreak = 0.0
        neutralCoastStreak = 0.0
        highSpeedStreak = 0.0
        airborneStreak = 0.0
        redlineStreak = 0.0
        speedHoldStreak = 0.0
        postCrashStreak = 0.0
        speedHoldAnchorMph = null
    }

    private fun syncBaselines(analyzer: AnalyzerState) {
        lastPerfectShifts = analyzer.shift.perfectShifts
        lastGoodShifts = analyzer.shift.goodShifts
        lastEarlyShifts = analyzer.shift.earlyShifts
        lastLateShifts = analyzer.shift.lateShifts
        lastSlowShifts = analyzer.shift.slowShifts
        lastZeroTo60Present = analyzer.drag.zeroTo60 != null
        lastQuarterPresent = analyzer.drag.quarterMile != null
        lastBrake60Present = analyzer.brake.sixtyToZeroSeconds != null
        lastBrake100Present = analyzer.brake.hundredToZeroSeconds != null
        lastCrashId = analyzer.latestCrash?.id
        lastSpinCount = analyzer.drift.spins
        lastShockEvents = analyzer.engine.shockEvents
        lastHardBrakeEvents = analyzer.engine.hardBrakingEvents
    }

    private fun updateSpeedAndPedalStats(
        dt: Double,
        moving: Boolean,
        speedMph: Double,
        throttle: Double,
        brake: Double,
        clutch: Double,
        gearRaw: Int,
        totalG: Double,
        verticalSpeed: Double
    ) {
        if (dt <= 0.0) return

        if (speedMph >= 60.0) add(AchievementMetric.TIME_ABOVE_60_SECONDS, dt)
        if (speedMph >= 100.0) add(AchievementMetric.TIME_ABOVE_100_SECONDS, dt)
        if (speedMph >= 150.0) add(AchievementMetric.TIME_ABOVE_150_SECONDS, dt)
        if (speedMph >= 200.0) add(AchievementMetric.TIME_ABOVE_200_SECONDS, dt)

        fullThrottleStreak = if (moving && throttle >= 0.95) fullThrottleStreak + dt else 0.0
        if (moving && throttle >= 0.95) add(AchievementMetric.FULL_THROTTLE_SECONDS, dt)
        maxValue(AchievementMetric.LONGEST_FULL_THROTTLE_SECONDS, fullThrottleStreak)

        noBrakeStreak = if (moving && brake <= 0.02) noBrakeStreak + dt else 0.0
        maxValue(AchievementMetric.LONGEST_NO_BRAKE_SECONDS, noBrakeStreak)

        noThrottleStreak = if (moving && throttle <= 0.02) noThrottleStreak + dt else 0.0
        maxValue(AchievementMetric.LONGEST_NO_THROTTLE_SECONDS, noThrottleStreak)

        val coasting = moving && speedMph >= 5.0 && throttle <= 0.03 && brake <= 0.03
        coastStreak = if (coasting) coastStreak + dt else 0.0
        if (coasting) add(AchievementMetric.NEUTRAL_COAST_SECONDS, if (gearRaw == 1) dt else 0.0)
        maxValue(AchievementMetric.LONGEST_COAST_SECONDS, coastStreak)

        val reversing = moving && gearRaw == 0
        reverseStreak = if (reversing) reverseStreak + dt else 0.0
        if (reversing) {
            add(AchievementMetric.REVERSE_SECONDS, dt)
            maxValue(AchievementMetric.MAX_REVERSE_SPEED_MPH, speedMph)
        }
        maxValue(AchievementMetric.LONGEST_REVERSE_SECONDS, reverseStreak)

        val throttleBrake = moving && throttle >= 0.30 && brake >= 0.30
        throttleBrakeStreak = if (throttleBrake) throttleBrakeStreak + dt else 0.0
        if (throttleBrake) add(AchievementMetric.THROTTLE_BRAKE_SECONDS, dt)
        maxValue(AchievementMetric.LONGEST_THROTTLE_BRAKE_SECONDS, throttleBrakeStreak)

        val allPedals = moving && throttle >= 0.20 && brake >= 0.20 && clutch >= 0.20
        allPedalsStreak = if (allPedals) allPedalsStreak + dt else 0.0
        if (allPedals) add(AchievementMetric.ALL_PEDALS_SECONDS, dt)
        maxValue(AchievementMetric.LONGEST_ALL_PEDALS_SECONDS, allPedalsStreak)

        val neutralCoast = moving && gearRaw == 1 && throttle <= 0.05 && brake <= 0.05
        neutralCoastStreak = if (neutralCoast) neutralCoastStreak + dt else 0.0
        maxValue(AchievementMetric.LONGEST_NEUTRAL_COAST_SECONDS, neutralCoastStreak)

        highSpeedStreak = if (moving && speedMph >= 100.0) highSpeedStreak + dt else 0.0
        maxValue(AchievementMetric.LONGEST_HIGH_SPEED_SECONDS, highSpeedStreak)
        if (speedMph >= 100.0) driveDisciplines += "SPEED"

        val estimatedAirborne = moving && verticalSpeed >= 1.5 && totalG in 0.0..0.55
        airborneStreak = if (estimatedAirborne) airborneStreak + dt else 0.0
        maxValue(AchievementMetric.LONGEST_AIRBORNE_SECONDS, airborneStreak)
        if (airborneStreak >= 0.5) driveDisciplines += "AIR"

        if (moving && speedMph >= 20.0) {
            val anchor = speedHoldAnchorMph
            if (anchor == null || abs(speedMph - anchor) > 1.5) {
                speedHoldAnchorMph = speedMph
                speedHoldStreak = 0.0
            } else {
                speedHoldStreak += dt
            }
        } else {
            speedHoldAnchorMph = null
            speedHoldStreak = 0.0
        }
        maxValue(AchievementMetric.LONGEST_SPEED_HOLD_SECONDS, speedHoldStreak)
    }

    private fun updateShifting(
        now: Long,
        gearRaw: Int,
        rpm: Double,
        throttle: Double,
        clutch: Double,
        redlineRpm: Int,
        analyzer: AnalyzerState
    ) {
        val perfectDelta = positiveDelta(analyzer.shift.perfectShifts, lastPerfectShifts)
        val goodDelta = positiveDelta(analyzer.shift.goodShifts, lastGoodShifts)
        val earlyDelta = positiveDelta(analyzer.shift.earlyShifts, lastEarlyShifts)
        val lateDelta = positiveDelta(analyzer.shift.lateShifts, lastLateShifts)
        val slowDelta = positiveDelta(analyzer.shift.slowShifts, lastSlowShifts)
        val nonPerfectDelta = goodDelta + earlyDelta + lateDelta + slowDelta

        if (perfectDelta > 0) {
            add(AchievementMetric.PERFECT_SHIFTS, perfectDelta.toDouble())
            currentPerfectShiftStreak += perfectDelta
            maxValue(AchievementMetric.PERFECT_SHIFT_STREAK, currentPerfectShiftStreak.toDouble())
        }
        if (goodDelta > 0) add(AchievementMetric.GOOD_SHIFTS, goodDelta.toDouble())
        if (earlyDelta > 0) add(AchievementMetric.EARLY_SHIFTS, earlyDelta.toDouble())
        if (lateDelta > 0) add(AchievementMetric.LATE_SHIFTS, lateDelta.toDouble())
        if (slowDelta > 0) add(AchievementMetric.SLOW_SHIFTS, slowDelta.toDouble())
        if (nonPerfectDelta > 0) currentPerfectShiftStreak = 0

        val total = analyzer.shift.totalShifts
        if (total >= 5) {
            val ratio = analyzer.shift.perfectShifts.toDouble() / total.toDouble() * 100.0
            maxValue(AchievementMetric.BEST_PERFECT_SHIFT_RATIO, ratio)
        }

        val forwardGearChange = gearRaw >= 2 && lastGearRaw >= 2 && gearRaw != lastGearRaw
        if (forwardGearChange) {
            if (previousRpm >= redlineRpm.coerceAtLeast(1) * 0.90) add(AchievementMetric.HIGH_RPM_SHIFTS)
            if (clutch <= 0.05) add(AchievementMetric.CLUTCHLESS_SHIFTS)
            if (previousThrottle >= 0.65 && throttle <= 0.35) add(AchievementMetric.THROTTLE_LIFT_SHIFTS)

            gearChangeTimes.addLast(now)
            while (gearChangeTimes.isNotEmpty() && now - gearChangeTimes.first() > 5_000L) {
                gearChangeTimes.removeFirst()
            }
            if (gearChangeTimes.size >= 4 && now - lastGearBurstAtMs > 5_000L) {
                add(AchievementMetric.GEAR_BURSTS)
                lastGearBurstAtMs = now
                gearChangeTimes.clear()
            }
            driveDisciplines += "SHIFT"
        }

        lastPerfectShifts = analyzer.shift.perfectShifts
        lastGoodShifts = analyzer.shift.goodShifts
        lastEarlyShifts = analyzer.shift.earlyShifts
        lastLateShifts = analyzer.shift.lateShifts
        lastSlowShifts = analyzer.shift.slowShifts
    }

    private fun updateDrift(
        now: Long,
        speedMph: Double,
        driftAngle: Double,
        throttle: Double,
        brake: Double,
        totalG: Double,
        analyzer: AnalyzerState
    ) {
        val absAngle = abs(driftAngle)
        val drifting = runtimeDriveActive && speedMph >= 10.0 && absAngle >= 10.0
        val sign = when {
            driftAngle > 5.0 -> 1
            driftAngle < -5.0 -> -1
            else -> 0
        }

        if (drifting) {
            if (driftStreak <= 0.0) {
                driftStintBrakeMax = 0.0
                driftStintSpeedMax = 0.0
            }
            driftStreak += 0.0.coerceAtLeast(0.0)
            driveHadDrift = true
            driveDisciplines += "DRIFT"
            driftStintBrakeMax = max(driftStintBrakeMax, brake)
            driftStintSpeedMax = max(driftStintSpeedMax, speedMph)
            if (sign > 0) {
                rightDriftStreak += 0.0
                leftDriftStreak = 0.0
            } else if (sign < 0) {
                leftDriftStreak += 0.0
                rightDriftStreak = 0.0
            }
            if (lastDriftSign != 0 && sign != 0 && sign != lastDriftSign && now - lastTransitionAtMs >= 750L) {
                add(AchievementMetric.DRIFT_TRANSITIONS)
                lastTransitionAtMs = now
            }
            if (sign != 0) lastDriftSign = sign
            if (absAngle >= 45.0) {
                driftSaveArmed = true
                driftSaveCrashId = analyzer.latestCrash?.id
            }
            val chaos = absAngle >= 35.0 && throttle >= 0.70 && brake >= 0.30 && totalG >= 1.2
            if (chaos && !chaosActive) add(AchievementMetric.CHAOS_COMBO_EVENTS)
            chaosActive = chaos
        } else {
            if (driftStreak >= 3.0) {
                if (driftStintBrakeMax <= 0.05) add(AchievementMetric.NO_BRAKE_DRIFTS)
                if (driftStintSpeedMax >= 35.0) add(AchievementMetric.HIGH_SPEED_DRIFTS)
                if (driftStintBrakeMax >= 0.70) add(AchievementMetric.DRIFT_BRAKE_COMBOS)
            }
            driftStreak = 0.0
            leftDriftStreak = 0.0
            rightDriftStreak = 0.0
            lastDriftSign = 0
            chaosActive = false
            if (driftSaveArmed && absAngle < 10.0 && speedMph >= 10.0 && analyzer.latestCrash?.id == driftSaveCrashId) {
                add(AchievementMetric.DRIFT_SAVES)
                driftSaveArmed = false
            }
        }

        // Analyzer duration is more stable than packet-time accumulation and is reset per drift.
        maxValue(AchievementMetric.BEST_DRIFT_DURATION, analyzer.drift.durationSeconds)
        maxValue(AchievementMetric.MAX_DRIFT_COMBO, analyzer.drift.combo.toDouble())
        maxValue(AchievementMetric.BEST_DRIFT_SCORE, analyzer.drift.score.toDouble())
        maxValue(AchievementMetric.BEST_DRIFT_ANGLE, analyzer.drift.maxAngleDeg)
        if (sign > 0) maxValue(AchievementMetric.LONGEST_RIGHT_DRIFT_SECONDS, analyzer.drift.durationSeconds)
        if (sign < 0) maxValue(AchievementMetric.LONGEST_LEFT_DRIFT_SECONDS, analyzer.drift.durationSeconds)

        val spinDelta = positiveDelta(analyzer.drift.spins, lastSpinCount)
        if (spinDelta > 0) {
            add(AchievementMetric.SPINS, spinDelta.toDouble())
            driftSaveArmed = false
        }
        lastSpinCount = analyzer.drift.spins
    }

    private fun updateDragAndBraking(now: Long, speedMph: Double, showLights: Long, analyzer: AnalyzerState) {
        val zeroPresent = analyzer.drag.zeroTo60 != null
        if (zeroPresent && !lastZeroTo60Present) {
            analyzer.drag.zeroTo60?.let {
                if (minPositive(AchievementMetric.BEST_ZERO_TO_60_SECONDS, it)) add(AchievementMetric.RECORDS_BROKEN)
            }
            maxValue(AchievementMetric.MAX_LAUNCH_G, analyzer.drag.launchG)
            if (analyzer.drag.launchG >= 0.40) add(AchievementMetric.HARD_LAUNCHES)
            driveDisciplines += "LAUNCH"
        }
        lastZeroTo60Present = zeroPresent

        val quarterPresent = analyzer.drag.quarterMile != null
        if (quarterPresent && !lastQuarterPresent) {
            analyzer.drag.quarterMile?.let {
                if (minPositive(AchievementMetric.BEST_QUARTER_SECONDS, it)) add(AchievementMetric.RECORDS_BROKEN)
            }
            analyzer.drag.quarterTrapMph?.let {
                if (maxValue(AchievementMetric.BEST_QUARTER_TRAP_MPH, it)) add(AchievementMetric.RECORDS_BROKEN)
            }
            driveHadQuarter = true
            driveDisciplines += "QUARTER"
        }
        lastQuarterPresent = quarterPresent

        val brake60Present = analyzer.brake.sixtyToZeroSeconds != null
        val brake100Present = analyzer.brake.hundredToZeroSeconds != null
        val newBrake60 = brake60Present && !lastBrake60Present
        val newBrake100 = brake100Present && !lastBrake100Present
        if (newBrake60 || newBrake100) {
            analyzer.brake.sixtyToZeroSeconds?.let {
                if (minPositive(AchievementMetric.BEST_60_TO_0_SECONDS, it)) add(AchievementMetric.RECORDS_BROKEN)
            }
            analyzer.brake.hundredToZeroSeconds?.let {
                if (minPositive(AchievementMetric.BEST_100_TO_0_SECONDS, it)) add(AchievementMetric.RECORDS_BROKEN)
            }
            analyzer.brake.sixtyToZeroMeters?.let { minPositive(AchievementMetric.BEST_60_TO_0_METERS, it) }
            analyzer.brake.hundredToZeroMeters?.let { minPositive(AchievementMetric.BEST_100_TO_0_METERS, it) }
            maxValue(AchievementMetric.MAX_BRAKING_G, analyzer.brake.peakDecelG)
            if (newBrake100 || analyzer.brake.startSpeedMph >= 80.0) add(AchievementMetric.HIGH_SPEED_STOPS)
            if (showLights and 1024L == 0L) add(AchievementMetric.ABS_FREE_STOPS)
            if (analyzer.brake.peakDecelG in 0.45..1.30) add(AchievementMetric.SMOOTH_BRAKE_EVENTS)
            stopAndGoArmedAtMs = now
            driveHadBrakeTest = true
            driveDisciplines += "BRAKE"
        }
        lastBrake60Present = brake60Present
        lastBrake100Present = brake100Present

        val hardBrakeDelta = positiveDelta(analyzer.engine.hardBrakingEvents, lastHardBrakeEvents)
        if (hardBrakeDelta > 0) add(AchievementMetric.HARD_BRAKES, hardBrakeDelta.toDouble())
        lastHardBrakeEvents = analyzer.engine.hardBrakingEvents

        if (speedMph >= 100.0) driveDisciplines += "SPEED"
    }

    private fun updateMechanical(
        dt: Double,
        rpm: Double,
        throttle: Double,
        redlineRpm: Int,
        out: OutGaugeData?,
        analyzer: AnalyzerState
    ) {
        val ratio = rpm / redlineRpm.coerceAtLeast(1).toDouble()
        val redline = runtimeDriveActive && ratio >= 0.95 && throttle >= 0.40
        redlineStreak = if (redline) redlineStreak + dt else 0.0
        if (redline && dt > 0.0) add(AchievementMetric.REDLINE_SECONDS, dt)

        val limiter = runtimeDriveActive && ratio >= 0.99 && throttle >= 0.50
        if (limiter && !limiterActive) {
            add(AchievementMetric.LIMITER_EVENTS)
            driveHadLimiter = true
        }
        limiterActive = limiter

        val hot = (out?.engineTempC ?: 0.0) >= 120.0 || (out?.oilTempC ?: 0.0) >= 130.0
        if (hot && !overheatActive) add(AchievementMetric.OVERHEAT_EVENTS)
        if (!hot && overheatActive && (out?.engineTempC ?: 0.0) in 1.0..105.0 && (out?.oilTempC ?: 0.0) in 1.0..115.0) {
            add(AchievementMetric.COOLDOWN_RECOVERIES)
        }
        overheatActive = hot

        val shockDelta = positiveDelta(analyzer.engine.shockEvents, lastShockEvents)
        if (shockDelta > 0) add(AchievementMetric.SHOCK_EVENTS, shockDelta.toDouble())
        lastShockEvents = analyzer.engine.shockEvents
    }

    private fun updateDynamics(totalG: Double, rollDeg: Double, analyzer: AnalyzerState) {
        val inverted = rollDeg >= 100.0
        if (inverted && !upsideDown) {
            add(AchievementMetric.ROLLOVERS)
            driveHadRollover = true
            driveDisciplines += "ROLLOVER"
        }
        if (!inverted && upsideDown && rollDeg <= 45.0) add(AchievementMetric.UPRIGHT_RECOVERIES)
        upsideDown = inverted

        val highForce = totalG >= 2.0
        if (highForce && !highDynamicsActive) highDynamicsCrashCount = driveCrashCount
        if (!highForce && highDynamicsActive && driveCrashCount == highDynamicsCrashCount) {
            add(AchievementMetric.CLEAN_DYNAMICS_EVENTS)
        }
        highDynamicsActive = highForce

        maxValue(AchievementMetric.MAX_ROLL_DEG, analyzer.dynamics.maxRollDeg)
        maxValue(AchievementMetric.MAX_PITCH_DEG, analyzer.dynamics.maxPitchDeg)
        maxValue(AchievementMetric.MAX_YAW_RATE, analyzer.dynamics.maxYawRateDegPerSec)
    }

    private fun updateCrashes(now: Long, speedMph: Double, analyzer: AnalyzerState) {
        val crash = analyzer.latestCrash
        if (crash != null && crash.id != lastCrashId) {
            maxValue(AchievementMetric.HARDEST_IMPACT_G, crash.peakG)
            if (crash.speedBeforeMph >= 50.0) add(AchievementMetric.HIGH_SPEED_IMPACTS)
            if (crash.speedBeforeMph < 15.0) add(AchievementMetric.LOW_SPEED_IMPACTS)
            driveHadCrash = true
            driveCrashCount += 1
            driveDisciplines += "IMPACT"
            crashAtMs = now
            postCrashStreak = 0.0
            crashRecoveryAwarded = false
            postCrashThirtyAwarded = false
            driftSaveArmed = false
        }
        lastCrashId = crash?.id

        if (crashAtMs > 0L && runtimeDriveActive) {
            if (speedMph > 2.0) {
                postCrashStreak += 0.0.coerceAtLeast(0.0)
                val elapsedSeconds = (now - crashAtMs).coerceAtLeast(0L) / 1000.0
                maxValue(AchievementMetric.LONGEST_POST_CRASH_SECONDS, elapsedSeconds)
                if (!crashRecoveryAwarded && elapsedSeconds >= 2.0 && elapsedSeconds <= 30.0 && speedMph >= 30.0) {
                    add(AchievementMetric.CRASH_RECOVERIES)
                    crashRecoveryAwarded = true
                }
                if (!postCrashThirtyAwarded && elapsedSeconds >= 30.0) {
                    add(AchievementMetric.CONTINUED_AFTER_CRASH_EVENTS)
                    postCrashThirtyAwarded = true
                }
            }
        }
    }

    private fun updateRecordBuckets(frame: TelemetryFrame, analyzer: AnalyzerState, totalG: Double) {
        val speedBucket = floor(frame.speedMph / 10.0).toInt()
        if (speedBucket > topSpeedBucket) {
            add(AchievementMetric.RECORDS_BROKEN, (speedBucket - topSpeedBucket).toDouble())
            topSpeedBucket = speedBucket
        }
        val scoreBucket = floor(analyzer.drift.score / 5_000.0).toInt()
        if (scoreBucket > driftScoreBucket) {
            add(AchievementMetric.RECORDS_BROKEN, (scoreBucket - driftScoreBucket).toDouble())
            driftScoreBucket = scoreBucket
        }
        val angleBucket = floor(analyzer.drift.maxAngleDeg / 5.0).toInt()
        if (angleBucket > driftAngleBucket) {
            add(AchievementMetric.RECORDS_BROKEN, (angleBucket - driftAngleBucket).toDouble())
            driftAngleBucket = angleBucket
        }
        val gBucket = floor(totalG / 0.5).toInt()
        if (gBucket > totalGBucket) {
            add(AchievementMetric.RECORDS_BROKEN, (gBucket - totalGBucket).toDouble())
            totalGBucket = gBucket
        }
    }

    private fun value(metric: AchievementMetric): Double = stats[metric.name] ?: 0.0

    private fun add(metric: AchievementMetric, amount: Double = 1.0) {
        if (amount > 0.0 && amount.isFinite()) stats[metric.name] = value(metric) + amount
    }

    private fun maxValue(metric: AchievementMetric, candidate: Double): Boolean {
        if (!candidate.isFinite() || candidate <= value(metric)) return false
        stats[metric.name] = candidate
        return true
    }

    private fun minPositive(metric: AchievementMetric, candidate: Double): Boolean {
        if (!candidate.isFinite() || candidate <= 0.0) return false
        val old = value(metric)
        if (old > 0.0 && candidate >= old) return false
        stats[metric.name] = candidate
        return true
    }

    private fun positiveDelta(current: Int, previous: Int): Int = if (current >= previous) current - previous else current

    private fun internalValue(key: String): Double = stats[key] ?: 0.0
    private fun internalSet(key: String, value: Double) { stats[key] = value }

    companion object {
        private const val CURRENT_CLEAN_STREAK = "_CURRENT_CLEAN_STREAK"
    }
}
