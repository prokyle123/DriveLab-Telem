package com.auroramediagroup.drivelab

import kotlin.math.roundToInt

enum class AchievementCategory(val label: String) {
    ALL("All"),
    GENERAL("General"),
    SPEED("Speed & Launch"),
    SHIFTING("Shifting"),
    DRIFT("Drift"),
    BRAKING("Braking"),
    DYNAMICS("Dynamics"),
    ENDURANCE("Endurance"),
    MECHANICAL("Mechanical"),
    IMPACTS("Impacts"),
    WILDCARD("Wildcards")
}

enum class AchievementRarity(val label: String) {
    COMMON("COMMON"),
    SKILLED("SKILLED"),
    EXPERT("EXPERT"),
    EXTREME("EXTREME"),
    INSANE("INSANE"),
    LEGENDARY("LEGENDARY")
}

enum class AchievementComparison {
    AT_LEAST,
    AT_MOST
}

enum class AchievementMetric(
    val displayName: String,
    val unit: String = "",
    val lowerIsBetter: Boolean = false
) {
    LEGACY_COUNT("legacy achievements"),
    TOTAL_XP("driver XP", " XP"),
    DRIVER_LEVEL("driver level"),
    ACHIEVEMENTS_UNLOCKED("achievements"),
    TOP_SPEED_MPH("top speed", " MPH"),
    TOTAL_DISTANCE_MILES("distance", " mi"),
    TOTAL_DRIVE_HOURS("drive time", " hr"),
    SESSION_COUNT("completed drives"),
    CLEAN_SESSION_COUNT("clean drives"),
    TOTAL_SHIFTS("shifts"),
    QUARTER_MILE_RUNS("quarter-mile runs"),
    BRAKE_RUNS("braking tests"),
    TOTAL_CRASHES("impacts"),
    BEST_DRIFT_SCORE("drift score", " pts"),
    BEST_DRIFT_ANGLE("drift angle", "°"),

    RECORDS_BROKEN("records broken"),
    MULTI_DISCIPLINE_DRIVES("multi-discipline drives"),
    LOW_ABUSE_DRIVES("low-abuse drives"),
    NO_LIMITER_DRIVES("limiter-free drives"),
    CLEAN_HIGH_SPEED_DRIVES("clean high-speed drives"),
    CLEAN_DRIFT_DRIVES("clean drift drives"),
    CLEAN_DRIVE_STREAK("clean-drive streak"),

    TIME_ABOVE_60_SECONDS("time above 60 MPH", " sec"),
    TIME_ABOVE_100_SECONDS("time above 100 MPH", " sec"),
    TIME_ABOVE_150_SECONDS("time above 150 MPH", " sec"),
    TIME_ABOVE_200_SECONDS("time above 200 MPH", " sec"),
    LONGEST_HIGH_SPEED_SECONDS("longest 100+ MPH hold", " sec"),
    LONGEST_FULL_THROTTLE_SECONDS("longest full-throttle hold", " sec"),
    FULL_THROTTLE_SECONDS("full-throttle time", " sec"),
    BEST_ZERO_TO_60_SECONDS("0–60 time", " sec", true),
    BEST_QUARTER_SECONDS("quarter-mile time", " sec", true),
    BEST_QUARTER_TRAP_MPH("quarter-mile trap", " MPH"),
    MAX_LAUNCH_G("launch force", " G"),
    HARD_LAUNCHES("hard launches"),
    MAX_REVERSE_SPEED_MPH("reverse speed", " MPH"),
    REVERSE_SECONDS("reverse time", " sec"),
    LONGEST_REVERSE_SECONDS("longest reverse run", " sec"),
    HIGH_SPEED_STOPS("high-speed stops"),

    PERFECT_SHIFTS("perfect shifts"),
    GOOD_SHIFTS("good shifts"),
    EARLY_SHIFTS("early shifts"),
    LATE_SHIFTS("late shifts"),
    SLOW_SHIFTS("slow shifts"),
    PERFECT_SHIFT_STREAK("perfect-shift streak"),
    BEST_SHIFT_MS("best shift", " ms", true),
    BEST_SHIFT_SCORE("shift score"),
    BEST_PERFECT_SHIFT_RATIO("perfect-shift ratio", "%"),
    HIGH_RPM_SHIFTS("high-RPM shifts"),
    CLUTCHLESS_SHIFTS("clutchless shifts"),
    THROTTLE_LIFT_SHIFTS("throttle-lift shifts"),
    GEAR_BURSTS("four-gear bursts"),

    BEST_DRIFT_DURATION("drift duration", " sec"),
    MAX_DRIFT_COMBO("drift combo", "x"),
    DRIFT_TRANSITIONS("drift transitions"),
    DRIFT_SAVES("high-angle saves"),
    NO_BRAKE_DRIFTS("no-brake drifts"),
    HIGH_SPEED_DRIFTS("high-speed drifts"),
    LONGEST_LEFT_DRIFT_SECONDS("longest left drift", " sec"),
    LONGEST_RIGHT_DRIFT_SECONDS("longest right drift", " sec"),
    SPINS("spins"),

    BEST_60_TO_0_SECONDS("60–0 time", " sec", true),
    BEST_100_TO_0_SECONDS("100–0 time", " sec", true),
    BEST_60_TO_0_METERS("60–0 distance", " m", true),
    BEST_100_TO_0_METERS("100–0 distance", " m", true),
    MAX_BRAKING_G("braking force", " G"),
    HARD_BRAKES("hard braking events"),
    STOP_AND_GO_EVENTS("stop-and-go events"),
    ABS_FREE_STOPS("ABS-free stops"),
    SMOOTH_BRAKE_EVENTS("smooth hard stops"),

    MAX_TOTAL_G("total force", " G"),
    MAX_LATERAL_G("lateral force", " G"),
    MAX_VERTICAL_G("vertical force", " G"),
    MAX_ROLL_DEG("roll angle", "°"),
    MAX_PITCH_DEG("pitch angle", "°"),
    MAX_YAW_RATE("yaw rate", "°/s"),
    LONGEST_AIRBORNE_SECONDS("estimated airtime", " sec"),
    ROLLOVERS("rollovers"),
    UPRIGHT_RECOVERIES("upright recoveries"),
    CLEAN_DYNAMICS_EVENTS("clean high-force events"),

    LONGEST_DRIVE_SECONDS("longest drive", " sec"),
    LONGEST_NO_BRAKE_SECONDS("longest no-brake run", " sec"),
    LONGEST_COAST_SECONDS("longest coast", " sec"),
    NO_BRAKE_DRIVES("brake-free drives"),
    ECO_DRIVES("economy drives"),

    MAX_RPM("engine speed", " RPM"),
    REDLINE_SECONDS("redline time", " sec"),
    LIMITER_EVENTS("limiter events"),
    OVERHEAT_EVENTS("overheat events"),
    MAX_ENGINE_TEMP_C("engine temperature", "°C"),
    MAX_OIL_TEMP_C("oil temperature", "°C"),
    MAX_TURBO_BAR("boost", " bar"),
    COOLDOWN_RECOVERIES("cooldown recoveries"),
    SHOCK_EVENTS("shock events"),

    HARDEST_IMPACT_G("hardest impact", " G"),
    HIGH_SPEED_IMPACTS("high-speed impacts"),
    LOW_SPEED_IMPACTS("low-speed impacts"),
    CRASH_RECOVERIES("crash recoveries"),
    CONTINUED_AFTER_CRASH_EVENTS("continued-after-impact events"),
    MULTI_IMPACT_DRIVES("multi-impact drives"),
    LONGEST_POST_CRASH_SECONDS("longest post-impact run", " sec"),

    THROTTLE_BRAKE_SECONDS("throttle-and-brake time", " sec"),
    LONGEST_THROTTLE_BRAKE_SECONDS("longest throttle-and-brake hold", " sec"),
    ALL_PEDALS_SECONDS("three-pedal time", " sec"),
    LONGEST_ALL_PEDALS_SECONDS("longest three-pedal hold", " sec"),
    NEUTRAL_COAST_SECONDS("neutral-coast time", " sec"),
    LONGEST_NEUTRAL_COAST_SECONDS("longest neutral coast", " sec"),
    LONGEST_SPEED_HOLD_SECONDS("longest steady-speed hold", " sec"),
    LONGEST_NO_THROTTLE_SECONDS("longest zero-throttle run", " sec"),
    DRIFT_BRAKE_COMBOS("drift-brake combinations"),
    CHAOS_COMBO_EVENTS("chaos combinations")
}

data class AchievementCondition(
    val metric: AchievementMetric,
    val target: Double,
    val comparison: AchievementComparison =
        if (metric.lowerIsBetter) AchievementComparison.AT_MOST else AchievementComparison.AT_LEAST
) {
    fun current(progress: DriverProgress): Double = metric.current(progress)

    fun isMet(progress: DriverProgress): Boolean {
        val value = current(progress)
        return when (comparison) {
            AchievementComparison.AT_LEAST -> value >= target
            AchievementComparison.AT_MOST -> value > 0.0 && value <= target
        }
    }

    fun fraction(progress: DriverProgress): Double {
        val value = current(progress)
        return when (comparison) {
            AchievementComparison.AT_LEAST ->
                if (target <= 0.0) 1.0 else (value / target).coerceIn(0.0, 1.0)
            AchievementComparison.AT_MOST ->
                if (value <= 0.0) 0.0 else (target / value).coerceIn(0.0, 1.0)
        }
    }

    fun progressText(progress: DriverProgress): String {
        val value = current(progress)
        val operator = if (comparison == AchievementComparison.AT_MOST) "≤" else "/"
        return "${formatMetricValue(metric, value)} $operator ${formatMetricValue(metric, target)}"
    }
}

data class AchievementDefinition(
    val id: String,
    val title: String,
    val description: String,
    val category: AchievementCategory,
    val rarity: AchievementRarity,
    val routes: List<List<AchievementCondition>>,
    val secret: Boolean = false
) {
    init {
        require(routes.isNotEmpty() && routes.all { it.isNotEmpty() })
    }

    fun unlocked(progress: DriverProgress): Boolean =
        routes.any { route -> route.all { it.isMet(progress) } }

    fun progressFraction(progress: DriverProgress): Double =
        routes.maxOf { route -> route.minOf { it.fraction(progress) } }

    fun progressText(progress: DriverProgress): String {
        val route = routes.maxBy { candidate -> candidate.minOf { it.fraction(progress) } }
        val first = route.first().progressText(progress)
        return if (route.size == 1) first else "$first • ${route.size - 1} more condition${if (route.size == 2) "" else "s"}"
    }
}

private data class GoalSpec(
    val description: String,
    val routes: List<List<AchievementCondition>>,
    val secret: Boolean = false,
    val titleOverride: String? = null
)

object AchievementCatalog {
    const val TOTAL_ACHIEVEMENTS = 1001
    const val MASTER_ID = "DRIVELAB_LEGEND"

    private val stageWords = listOf(
        "First", "Rising", "Focused", "Fearless", "Relentless",
        "Elite", "Savage", "Unbound", "Mythic", "Impossible"
    )

    val all: List<AchievementDefinition> by lazy {
        val regular = buildList {
            addAll(buildGeneral())
            addAll(buildSpeed())
            addAll(buildShifting())
            addAll(buildDrift())
            addAll(buildBraking())
            addAll(buildDynamics())
            addAll(buildEndurance())
            addAll(buildMechanical())
            addAll(buildImpacts())
            addAll(buildWildcard())
        }
        check(regular.size == 1000) { "Achievement Vault v2 must contain 1,000 regular goals, found ${regular.size}." }
        check(regular.map { it.id }.toSet().size == regular.size) { "Achievement IDs must be unique." }
        check(regular.map { it.title }.toSet().size == regular.size) { "Achievement titles must be unique." }

        regular + AchievementDefinition(
            id = MASTER_ID,
            title = "DriveLab Legend",
            description = "Complete every other achievement in DriveLab.",
            category = AchievementCategory.GENERAL,
            rarity = AchievementRarity.LEGENDARY,
            routes = listOf(listOf(atLeast(AchievementMetric.ACHIEVEMENTS_UNLOCKED, 1000.0)))
        )
    }

    private val byId: Map<String, AchievementDefinition> by lazy { all.associateBy { it.id } }

    fun definition(id: String): AchievementDefinition? = byId[id]

    fun forCategory(category: AchievementCategory): List<AchievementDefinition> =
        if (category == AchievementCategory.ALL) all else all.filter { it.category == category }

    fun unlockedIds(progress: DriverProgress): Set<String> = resolvedUnlocked(progress, emptySet())

    fun resolvedUnlocked(progress: DriverProgress, previous: Set<String>): Set<String> {
        val unlocked = previous.filterTo(mutableSetOf()) { it in byId && it != MASTER_ID }
        var changed: Boolean
        do {
            changed = false
            val snapshot = progress.copy(achievements = unlocked.toSet())
            all.asSequence()
                .filter { it.id != MASTER_ID && it.id !in unlocked }
                .filter { it.unlocked(snapshot) }
                .forEach {
                    unlocked += it.id
                    changed = true
                }
        } while (changed)

        if (unlocked.size >= 1000) unlocked += MASTER_ID
        return unlocked
    }

    private fun buildGeneral(): List<AchievementDefinition> = buildSeries(
        prefix = "GEN",
        category = AchievementCategory.GENERAL,
        familyNames = listOf(
            "Momentum", "Driver Rank", "Seat Time", "Long Road", "Record Breaker",
            "All-Rounder", "Vault Hunter", "Mechanical Sympathy", "Clean Violence", "Original Bloodline"
        )
    ) { family, level ->
        val n = level + 1
        when (family) {
            0 -> GoalSpec(
                "Build ${formatWhole(1_000.0 * n * n)} total driver XP.",
                route(atLeast(AchievementMetric.TOTAL_XP, 1_000.0 * n * n))
            )
            1 -> GoalSpec(
                "Reach Driver Level ${2 + level * 3}.",
                route(atLeast(AchievementMetric.DRIVER_LEVEL, (2 + level * 3).toDouble()))
            )
            2 -> GoalSpec(
                "Complete ${5 + level * 15} drives, including ${2 + level * 5} clean drives.",
                route(
                    atLeast(AchievementMetric.SESSION_COUNT, (5 + level * 15).toDouble()),
                    atLeast(AchievementMetric.CLEAN_SESSION_COUNT, (2 + level * 5).toDouble())
                )
            )
            3 -> GoalSpec(
                "Record ${10 * n * n} miles and ${1 + level * 2} hours of driving.",
                route(
                    atLeast(AchievementMetric.TOTAL_DISTANCE_MILES, (10 * n * n).toDouble()),
                    atLeast(AchievementMetric.TOTAL_DRIVE_HOURS, (1 + level * 2).toDouble())
                )
            )
            4 -> GoalSpec(
                "Break ${2 + level * 3} meaningful personal records.",
                route(atLeast(AchievementMetric.RECORDS_BROKEN, (2 + level * 3).toDouble()))
            )
            5 -> GoalSpec(
                "Finish ${1 + level * 2} drives that combine at least three disciplines.",
                route(atLeast(AchievementMetric.MULTI_DISCIPLINE_DRIVES, (1 + level * 2).toDouble()))
            )
            6 -> GoalSpec(
                "Unlock ${10 + level * 50} other achievements.",
                route(atLeast(AchievementMetric.ACHIEVEMENTS_UNLOCKED, (10 + level * 50).toDouble()))
            )
            7 -> GoalSpec(
                "Complete ${2 + level * 3} low-abuse drives and ${1 + level * 2} limiter-free drives.",
                route(
                    atLeast(AchievementMetric.LOW_ABUSE_DRIVES, (2 + level * 3).toDouble()),
                    atLeast(AchievementMetric.NO_LIMITER_DRIVES, (1 + level * 2).toDouble())
                )
            )
            8 -> GoalSpec(
                "Complete ${1 + level} clean high-speed drives and ${1 + level} clean drift drives.",
                route(
                    atLeast(AchievementMetric.CLEAN_HIGH_SPEED_DRIVES, (1 + level).toDouble()),
                    atLeast(AchievementMetric.CLEAN_DRIFT_DRIVES, (1 + level).toDouble())
                )
            )
            else -> if (level == 0) {
                GoalSpec(
                    "Carry progress from the original Achievement Vault, or earn 250 completed drives in Vault v2.",
                    routes = listOf(
                        listOf(atLeast(AchievementMetric.LEGACY_COUNT, 1.0)),
                        listOf(atLeast(AchievementMetric.SESSION_COUNT, 250.0))
                    ),
                    titleOverride = "Original Driver"
                )
            } else {
                GoalSpec(
                    "Reach ${formatWhole(5_000.0 * n * n)} XP, break ${level * 4} records, and finish ${level * 20} drives.",
                    route(
                        atLeast(AchievementMetric.TOTAL_XP, 5_000.0 * n * n),
                        atLeast(AchievementMetric.RECORDS_BROKEN, (level * 4).toDouble()),
                        atLeast(AchievementMetric.SESSION_COUNT, (level * 20).toDouble())
                    )
                )
            }
        }
    }

    private fun buildSpeed(): List<AchievementDefinition> = buildSeries(
        "SPD",
        AchievementCategory.SPEED,
        listOf(
            "Velocity Check", "Highway Hold", "Launch Window", "Quarter Crusher", "Trap Hunter",
            "G-Force Launch", "Reverse Rocket", "Stop From Orbit", "Clean Speed", "No-Lift Nerve"
        )
    ) { family, level ->
        val n = level + 1
        when (family) {
            0 -> GoalSpec(
                "Reach ${60 + level * 15} MPH and have at least ${level / 2} clean drives recorded.",
                route(
                    atLeast(AchievementMetric.TOP_SPEED_MPH, (60 + level * 15).toDouble()),
                    atLeast(AchievementMetric.CLEAN_SESSION_COUNT, (level / 2).toDouble())
                )
            )
            1 -> {
                val metric = when {
                    level < 3 -> AchievementMetric.TIME_ABOVE_60_SECONDS
                    level < 6 -> AchievementMetric.TIME_ABOVE_100_SECONDS
                    level < 9 -> AchievementMetric.TIME_ABOVE_150_SECONDS
                    else -> AchievementMetric.TIME_ABOVE_200_SECONDS
                }
                val speed = when (metric) {
                    AchievementMetric.TIME_ABOVE_60_SECONDS -> 60
                    AchievementMetric.TIME_ABOVE_100_SECONDS -> 100
                    AchievementMetric.TIME_ABOVE_150_SECONDS -> 150
                    else -> 200
                }
                GoalSpec(
                    "Accumulate ${10 + level * 10} seconds above $speed MPH.",
                    route(atLeast(metric, (10 + level * 10).toDouble()))
                )
            }
            2 -> {
                val target = 12.0 - level * 0.8
                GoalSpec(
                    "Run 0–60 MPH in ${format1(target)} seconds or less and record ${1 + level} hard launches.",
                    route(
                        atMost(AchievementMetric.BEST_ZERO_TO_60_SECONDS, target),
                        atLeast(AchievementMetric.HARD_LAUNCHES, (1 + level).toDouble())
                    )
                )
            }
            3 -> {
                val target = 20.0 - level * 0.7
                GoalSpec(
                    "Complete the quarter-mile in ${format1(target)} seconds or less after ${1 + level} measured runs.",
                    route(
                        atMost(AchievementMetric.BEST_QUARTER_SECONDS, target),
                        atLeast(AchievementMetric.QUARTER_MILE_RUNS, (1 + level).toDouble())
                    )
                )
            }
            4 -> GoalSpec(
                "Record a quarter-mile trap speed of ${70 + level * 10} MPH with ${1 + level} completed runs.",
                route(
                    atLeast(AchievementMetric.BEST_QUARTER_TRAP_MPH, (70 + level * 10).toDouble()),
                    atLeast(AchievementMetric.QUARTER_MILE_RUNS, (1 + level).toDouble())
                )
            )
            5 -> GoalSpec(
                "Produce a ${format1(0.35 + level * 0.10)} G launch and record ${1 + level} hard launches.",
                route(
                    atLeast(AchievementMetric.MAX_LAUNCH_G, 0.35 + level * 0.10),
                    atLeast(AchievementMetric.HARD_LAUNCHES, (1 + level).toDouble())
                )
            )
            6 -> GoalSpec(
                "Reach ${10 + level * 5} MPH in reverse and accumulate ${5 + level * 5} reverse seconds.",
                route(
                    atLeast(AchievementMetric.MAX_REVERSE_SPEED_MPH, (10 + level * 5).toDouble()),
                    atLeast(AchievementMetric.REVERSE_SECONDS, (5 + level * 5).toDouble())
                )
            )
            7 -> GoalSpec(
                "Complete ${1 + level} high-speed stops after reaching at least ${70 + level * 10} MPH.",
                route(
                    atLeast(AchievementMetric.HIGH_SPEED_STOPS, (1 + level).toDouble()),
                    atLeast(AchievementMetric.TOP_SPEED_MPH, (70 + level * 10).toDouble())
                )
            )
            8 -> GoalSpec(
                "Finish ${1 + level} clean drives that exceed ${80 + level * 10} MPH.",
                route(
                    atLeast(AchievementMetric.CLEAN_HIGH_SPEED_DRIVES, (1 + level).toDouble()),
                    atLeast(AchievementMetric.TOP_SPEED_MPH, (80 + level * 10).toDouble())
                )
            )
            else -> GoalSpec(
                "Hold full throttle for ${3 + level * 2} seconds and reach ${50 + level * 10} MPH.",
                route(
                    atLeast(AchievementMetric.LONGEST_FULL_THROTTLE_SECONDS, (3 + level * 2).toDouble()),
                    atLeast(AchievementMetric.TOP_SPEED_MPH, (50 + level * 10).toDouble())
                ),
                secret = level >= 8
            )
        }
    }

    private fun buildShifting(): List<AchievementDefinition> = buildSeries(
        "SHF",
        AchievementCategory.SHIFTING,
        listOf(
            "Perfect Motion", "Golden Streak", "Lightning Shift", "Redline Exchange", "Clutchless Wonder",
            "Gearbox Storm", "Shift Discipline", "Precision Ratio", "Limiter-Free Hands", "Throttle-Lift Timing"
        )
    ) { family, level ->
        when (family) {
            0 -> GoalSpec("Record ${5 + level * 10} perfect shifts.", route(atLeast(AchievementMetric.PERFECT_SHIFTS, (5 + level * 10).toDouble())))
            1 -> GoalSpec("Chain ${2 + level} perfect shifts without another verdict breaking the streak.", route(atLeast(AchievementMetric.PERFECT_SHIFT_STREAK, (2 + level).toDouble())))
            2 -> {
                val target = 1_200.0 - level * 80.0
                GoalSpec("Complete a measured shift in ${target.roundToInt()} ms or less.", route(atMost(AchievementMetric.BEST_SHIFT_MS, target)))
            }
            3 -> GoalSpec("Complete ${1 + level * 3} shifts above 90% of the configured redline.", route(atLeast(AchievementMetric.HIGH_RPM_SHIFTS, (1 + level * 3).toDouble())))
            4 -> GoalSpec("Complete ${1 + level * 2} forward-gear changes without clutch input.", route(atLeast(AchievementMetric.CLUTCHLESS_SHIFTS, (1 + level * 2).toDouble())))
            5 -> GoalSpec("Trigger ${1 + level} four-gear bursts within five-second windows.", route(atLeast(AchievementMetric.GEAR_BURSTS, (1 + level).toDouble())))
            6 -> GoalSpec(
                "Record ${20 + level * 50} shifts and reach a best shift score of ${60 + level * 4}.",
                route(
                    atLeast(AchievementMetric.TOTAL_SHIFTS, (20 + level * 50).toDouble()),
                    atLeast(AchievementMetric.BEST_SHIFT_SCORE, (60 + level * 4).toDouble())
                )
            )
            7 -> GoalSpec(
                "Reach a best perfect-shift ratio of ${50 + level * 5}% across at least ${10 + level * 10} perfect shifts.",
                route(
                    atLeast(AchievementMetric.BEST_PERFECT_SHIFT_RATIO, (50 + level * 5).toDouble()),
                    atLeast(AchievementMetric.PERFECT_SHIFTS, (10 + level * 10).toDouble())
                )
            )
            8 -> GoalSpec(
                "Finish ${1 + level} limiter-free drives while recording ${5 + level * 5} perfect shifts.",
                route(
                    atLeast(AchievementMetric.NO_LIMITER_DRIVES, (1 + level).toDouble()),
                    atLeast(AchievementMetric.PERFECT_SHIFTS, (5 + level * 5).toDouble())
                )
            )
            else -> GoalSpec("Complete ${2 + level * 4} shifts after a clear throttle lift.", route(atLeast(AchievementMetric.THROTTLE_LIFT_SHIFTS, (2 + level * 4).toDouble())), secret = level >= 8)
        }
    }

    private fun buildDrift(): List<AchievementDefinition> = buildSeries(
        "DRF",
        AchievementCategory.DRIFT,
        listOf(
            "Score Attack", "Angle Authority", "Long Slide", "Combo Chain", "Transition Artist",
            "Impossible Save", "No-Brake Slide", "High-Speed Sideways", "Twin Direction", "Clean Smoke"
        )
    ) { family, level ->
        when (family) {
            0 -> GoalSpec("Reach a single-drive drift score of ${2_000 + level * 5_000} points.", route(atLeast(AchievementMetric.BEST_DRIFT_SCORE, (2_000 + level * 5_000).toDouble())))
            1 -> GoalSpec("Reach ${15 + level * 5}° of measured drift angle.", route(atLeast(AchievementMetric.BEST_DRIFT_ANGLE, (15 + level * 5).toDouble())))
            2 -> GoalSpec("Hold one drift for ${2 + level * 2} seconds.", route(atLeast(AchievementMetric.BEST_DRIFT_DURATION, (2 + level * 2).toDouble())))
            3 -> GoalSpec("Build a drift combo of x${2 + level}.", route(atLeast(AchievementMetric.MAX_DRIFT_COMBO, (2 + level).toDouble())))
            4 -> GoalSpec("Complete ${1 + level * 2} left-to-right or right-to-left drift transitions.", route(atLeast(AchievementMetric.DRIFT_TRANSITIONS, (1 + level * 2).toDouble())))
            5 -> GoalSpec("Recover ${1 + level} drifts after exceeding 45° without immediately spinning or crashing.", route(atLeast(AchievementMetric.DRIFT_SAVES, (1 + level).toDouble())))
            6 -> GoalSpec("Complete ${1 + level} drifts lasting at least three seconds without brake input.", route(atLeast(AchievementMetric.NO_BRAKE_DRIFTS, (1 + level).toDouble())))
            7 -> GoalSpec("Complete ${1 + level} measured drifts above ${35 + level * 5} MPH.", route(atLeast(AchievementMetric.HIGH_SPEED_DRIFTS, (1 + level).toDouble())))
            8 -> GoalSpec(
                "Hold both a left and right drift for at least ${format1(1.0 + level * 1.5)} seconds.",
                route(
                    atLeast(AchievementMetric.LONGEST_LEFT_DRIFT_SECONDS, 1.0 + level * 1.5),
                    atLeast(AchievementMetric.LONGEST_RIGHT_DRIFT_SECONDS, 1.0 + level * 1.5)
                )
            )
            else -> GoalSpec(
                "Finish ${1 + level} clean drift drives and reach ${20 + level * 4}° of angle.",
                route(
                    atLeast(AchievementMetric.CLEAN_DRIFT_DRIVES, (1 + level).toDouble()),
                    atLeast(AchievementMetric.BEST_DRIFT_ANGLE, (20 + level * 4).toDouble())
                ),
                secret = level >= 8
            )
        }
    }

    private fun buildBraking(): List<AchievementDefinition> = buildSeries(
        "BRK",
        AchievementCategory.BRAKING,
        listOf(
            "Sixty Shutdown", "Hundred Hammer", "Short Stop", "Deep Stop", "Decel Force",
            "Brake Habit", "High-Speed Arrest", "Stop And Strike", "ABS Whisper", "Smooth Pressure"
        )
    ) { family, level ->
        when (family) {
            0 -> {
                val target = 6.0 - level * 0.3
                GoalSpec("Stop from 60 MPH in ${format1(target)} seconds or less.", route(atMost(AchievementMetric.BEST_60_TO_0_SECONDS, target)))
            }
            1 -> {
                val target = 9.0 - level * 0.4
                GoalSpec("Stop from 100 MPH in ${format1(target)} seconds or less.", route(atMost(AchievementMetric.BEST_100_TO_0_SECONDS, target)))
            }
            2 -> {
                val target = 70.0 - level * 4.0
                GoalSpec("Stop from 60 MPH within ${target.roundToInt()} estimated meters.", route(atMost(AchievementMetric.BEST_60_TO_0_METERS, target)))
            }
            3 -> {
                val target = 150.0 - level * 8.0
                GoalSpec("Stop from 100 MPH within ${target.roundToInt()} estimated meters.", route(atMost(AchievementMetric.BEST_100_TO_0_METERS, target)))
            }
            4 -> GoalSpec("Reach ${format1(0.4 + level * 0.12)} G of measured braking force.", route(atLeast(AchievementMetric.MAX_BRAKING_G, 0.4 + level * 0.12)))
            5 -> GoalSpec("Record ${2 + level * 5} hard braking events.", route(atLeast(AchievementMetric.HARD_BRAKES, (2 + level * 5).toDouble())))
            6 -> GoalSpec("Complete ${1 + level} measured high-speed stops.", route(atLeast(AchievementMetric.HIGH_SPEED_STOPS, (1 + level).toDouble())))
            7 -> GoalSpec("Come to a measured stop and accelerate back above 60 MPH ${1 + level} times.", route(atLeast(AchievementMetric.STOP_AND_GO_EVENTS, (1 + level).toDouble())))
            8 -> GoalSpec("Complete ${1 + level} measured hard stops without the ABS warning flag.", route(atLeast(AchievementMetric.ABS_FREE_STOPS, (1 + level).toDouble())))
            else -> GoalSpec("Complete ${1 + level} strong but progressive measured stops.", route(atLeast(AchievementMetric.SMOOTH_BRAKE_EVENTS, (1 + level).toDouble())), secret = level >= 8)
        }
    }

    private fun buildDynamics(): List<AchievementDefinition> = buildSeries(
        "DYN",
        AchievementCategory.DYNAMICS,
        listOf(
            "Total Force", "Lateral Load", "Vertical Violence", "Roll Control", "Pitch Control",
            "Yaw Master", "Air Time", "Rollover Count", "Cat Landing", "Clean Chaos"
        )
    ) { family, level ->
        when (family) {
            0 -> GoalSpec("Reach ${format1(0.8 + level * 0.5)} total G.", route(atLeast(AchievementMetric.MAX_TOTAL_G, 0.8 + level * 0.5)))
            1 -> GoalSpec("Reach ${format1(0.4 + level * 0.15)} lateral G.", route(atLeast(AchievementMetric.MAX_LATERAL_G, 0.4 + level * 0.15)))
            2 -> GoalSpec("Reach ${format1(0.5 + level * 0.25)} vertical G.", route(atLeast(AchievementMetric.MAX_VERTICAL_G, 0.5 + level * 0.25)))
            3 -> GoalSpec("Reach ${10 + level * 8}° of roll while still producing live telemetry.", route(atLeast(AchievementMetric.MAX_ROLL_DEG, (10 + level * 8).toDouble())))
            4 -> GoalSpec("Reach ${5 + level * 5}° of pitch.", route(atLeast(AchievementMetric.MAX_PITCH_DEG, (5 + level * 5).toDouble())))
            5 -> GoalSpec("Reach a yaw rate of ${20 + level * 20}° per second.", route(atLeast(AchievementMetric.MAX_YAW_RATE, (20 + level * 20).toDouble())))
            6 -> GoalSpec("Accumulate an estimated airborne streak of ${format1(0.5 + level * 0.75)} seconds.", route(atLeast(AchievementMetric.LONGEST_AIRBORNE_SECONDS, 0.5 + level * 0.75)))
            7 -> GoalSpec("Record ${1 + level} rollover events.", route(atLeast(AchievementMetric.ROLLOVERS, (1 + level).toDouble())))
            8 -> GoalSpec("Return upright after ${1 + level} rollover events.", route(atLeast(AchievementMetric.UPRIGHT_RECOVERIES, (1 + level).toDouble())))
            else -> GoalSpec(
                "Complete ${1 + level} clean high-force events and reach ${format1(1.0 + level * 0.3)} total G.",
                route(
                    atLeast(AchievementMetric.CLEAN_DYNAMICS_EVENTS, (1 + level).toDouble()),
                    atLeast(AchievementMetric.MAX_TOTAL_G, 1.0 + level * 0.3)
                ),
                secret = level >= 8
            )
        }
    }

    private fun buildEndurance(): List<AchievementDefinition> = buildSeries(
        "END",
        AchievementCategory.ENDURANCE,
        listOf(
            "Road Distance", "Clock Eater", "Long Haul", "Clean Machine", "No-Brake Run",
            "Coast Line", "Brake-Free Drive", "Low-Abuse Run", "Economy Run", "Clean Streak"
        )
    ) { family, level ->
        val n = level + 1
        when (family) {
            0 -> GoalSpec("Record ${25 * n * n} cumulative miles.", route(atLeast(AchievementMetric.TOTAL_DISTANCE_MILES, (25 * n * n).toDouble())))
            1 -> GoalSpec("Accumulate ${1 + level * 5} hours of live driving.", route(atLeast(AchievementMetric.TOTAL_DRIVE_HOURS, (1 + level * 5).toDouble())))
            2 -> GoalSpec("Complete one uninterrupted drive lasting ${2 + level * 3} minutes.", route(atLeast(AchievementMetric.LONGEST_DRIVE_SECONDS, (2 + level * 3) * 60.0)))
            3 -> GoalSpec("Complete ${3 + level * 5} clean drives.", route(atLeast(AchievementMetric.CLEAN_SESSION_COUNT, (3 + level * 5).toDouble())))
            4 -> GoalSpec("Drive for ${10 + level * 15} seconds without touching the brake.", route(atLeast(AchievementMetric.LONGEST_NO_BRAKE_SECONDS, (10 + level * 15).toDouble())))
            5 -> GoalSpec("Coast for ${10 + level * 20} seconds without throttle or brake.", route(atLeast(AchievementMetric.LONGEST_COAST_SECONDS, (10 + level * 20).toDouble())))
            6 -> GoalSpec("Finish ${1 + level} drives of at least 30 seconds without brake input.", route(atLeast(AchievementMetric.NO_BRAKE_DRIVES, (1 + level).toDouble())))
            7 -> GoalSpec("Finish ${2 + level * 2} drives with a very small abuse increase.", route(atLeast(AchievementMetric.LOW_ABUSE_DRIVES, (2 + level * 2).toDouble())))
            8 -> GoalSpec("Finish ${1 + level} two-minute economy drives with restrained average throttle.", route(atLeast(AchievementMetric.ECO_DRIVES, (1 + level).toDouble())))
            else -> GoalSpec("Build a clean-drive streak of ${2 + level}.", route(atLeast(AchievementMetric.CLEAN_DRIVE_STREAK, (2 + level).toDouble())), secret = level >= 8)
        }
    }

    private fun buildMechanical(): List<AchievementDefinition> = buildSeries(
        "MEC",
        AchievementCategory.MECHANICAL,
        listOf(
            "RPM Climber", "Redline Residence", "Limiter Visitor", "Heat Warning", "Engine Furnace",
            "Oil Furnace", "Boost Pressure", "Cool Down", "Shock Load", "Gentle Machine"
        )
    ) { family, level ->
        when (family) {
            0 -> GoalSpec("Reach ${4_000 + level * 500} RPM.", route(atLeast(AchievementMetric.MAX_RPM, (4_000 + level * 500).toDouble())))
            1 -> GoalSpec("Accumulate ${2 + level * 5} seconds above 95% of the configured redline.", route(atLeast(AchievementMetric.REDLINE_SECONDS, (2 + level * 5).toDouble())))
            2 -> GoalSpec("Enter the limiter zone ${1 + level * 3} times.", route(atLeast(AchievementMetric.LIMITER_EVENTS, (1 + level * 3).toDouble())))
            3 -> GoalSpec("Enter an inferred overheat state ${1 + level} times.", route(atLeast(AchievementMetric.OVERHEAT_EVENTS, (1 + level).toDouble())))
            4 -> GoalSpec("Reach an engine temperature of ${100 + level * 5}°C.", route(atLeast(AchievementMetric.MAX_ENGINE_TEMP_C, (100 + level * 5).toDouble())))
            5 -> GoalSpec("Reach an oil temperature of ${100 + level * 5}°C.", route(atLeast(AchievementMetric.MAX_OIL_TEMP_C, (100 + level * 5).toDouble())))
            6 -> GoalSpec("Reach ${format1(0.2 + level * 0.25)} bar of reported boost.", route(atLeast(AchievementMetric.MAX_TURBO_BAR, 0.2 + level * 0.25)))
            7 -> GoalSpec("Recover from an inferred hot state into the normal range ${1 + level} times.", route(atLeast(AchievementMetric.COOLDOWN_RECOVERIES, (1 + level).toDouble())))
            8 -> GoalSpec("Record ${1 + level * 3} inferred shock events.", route(atLeast(AchievementMetric.SHOCK_EVENTS, (1 + level * 3).toDouble())))
            else -> GoalSpec(
                "Complete ${2 + level * 2} limiter-free drives and ${2 + level * 2} low-abuse drives.",
                route(
                    atLeast(AchievementMetric.NO_LIMITER_DRIVES, (2 + level * 2).toDouble()),
                    atLeast(AchievementMetric.LOW_ABUSE_DRIVES, (2 + level * 2).toDouble())
                ),
                secret = level >= 8
            )
        }
    }

    private fun buildImpacts(): List<AchievementDefinition> = buildSeries(
        "IMP",
        AchievementCategory.IMPACTS,
        listOf(
            "Impact Count", "Heavy Hit", "High-Speed Hit", "Parking-Lot Punch", "Crash Recovery",
            "Still Moving", "Multiple Choice", "Roof Inspector", "Back On Four", "Aftershock Run"
        )
    ) { family, level ->
        when (family) {
            0 -> GoalSpec("Record ${1 + level * 3} impact events.", route(atLeast(AchievementMetric.TOTAL_CRASHES, (1 + level * 3).toDouble())))
            1 -> GoalSpec("Record an impact of ${format1(2.0 + level * 1.5)} G or more.", route(atLeast(AchievementMetric.HARDEST_IMPACT_G, 2.0 + level * 1.5)))
            2 -> GoalSpec("Record ${1 + level} impacts above 50 MPH.", route(atLeast(AchievementMetric.HIGH_SPEED_IMPACTS, (1 + level).toDouble())))
            3 -> GoalSpec("Record ${1 + level} impacts below 15 MPH.", route(atLeast(AchievementMetric.LOW_SPEED_IMPACTS, (1 + level).toDouble())))
            4 -> GoalSpec("Return above 30 MPH after an impact ${1 + level} times.", route(atLeast(AchievementMetric.CRASH_RECOVERIES, (1 + level).toDouble())))
            5 -> GoalSpec("Keep driving for at least 30 seconds after an impact ${1 + level} times.", route(atLeast(AchievementMetric.CONTINUED_AFTER_CRASH_EVENTS, (1 + level).toDouble())))
            6 -> GoalSpec("Finish ${1 + level} drives containing multiple impacts.", route(atLeast(AchievementMetric.MULTI_IMPACT_DRIVES, (1 + level).toDouble())))
            7 -> GoalSpec("Record ${1 + level} rollover events.", route(atLeast(AchievementMetric.ROLLOVERS, (1 + level).toDouble())))
            8 -> GoalSpec("Return upright after ${1 + level} rollover events.", route(atLeast(AchievementMetric.UPRIGHT_RECOVERIES, (1 + level).toDouble())))
            else -> GoalSpec("Continue moving for ${5 + level * 10} seconds after a detected impact.", route(atLeast(AchievementMetric.LONGEST_POST_CRASH_SECONDS, (5 + level * 10).toDouble())), secret = level >= 6)
        }
    }

    private fun buildWildcard(): List<AchievementDefinition> = buildSeries(
        "WLD",
        AchievementCategory.WILDCARD,
        listOf(
            "Reverse Time", "Reverse Speed", "Two-Pedal Trouble", "Three-Pedal Circus", "Neutral Glide",
            "Speed Lock", "Zero-Throttle Travel", "Everything Everywhere", "Drift Brake Combo", "Chaos Theory"
        )
    ) { family, level ->
        when (family) {
            0 -> GoalSpec("Accumulate ${5 + level * 10} seconds in reverse.", route(atLeast(AchievementMetric.REVERSE_SECONDS, (5 + level * 10).toDouble())))
            1 -> GoalSpec("Reach ${10 + level * 5} MPH in reverse.", route(atLeast(AchievementMetric.MAX_REVERSE_SPEED_MPH, (10 + level * 5).toDouble())))
            2 -> GoalSpec("Hold throttle and brake together for ${format1(1.0 + level * 1.5)} seconds.", route(atLeast(AchievementMetric.LONGEST_THROTTLE_BRAKE_SECONDS, 1.0 + level * 1.5)))
            3 -> GoalSpec("Hold throttle, brake, and clutch together for ${format1(0.5 + level * 0.75)} seconds.", route(atLeast(AchievementMetric.LONGEST_ALL_PEDALS_SECONDS, 0.5 + level * 0.75)))
            4 -> GoalSpec("Coast in Neutral for ${3 + level * 5} seconds.", route(atLeast(AchievementMetric.LONGEST_NEUTRAL_COAST_SECONDS, (3 + level * 5).toDouble())))
            5 -> GoalSpec("Hold speed within a narrow window for ${5 + level * 5} seconds.", route(atLeast(AchievementMetric.LONGEST_SPEED_HOLD_SECONDS, (5 + level * 5).toDouble())))
            6 -> GoalSpec("Keep moving with zero throttle for ${10 + level * 15} seconds.", route(atLeast(AchievementMetric.LONGEST_NO_THROTTLE_SECONDS, (10 + level * 15).toDouble())))
            7 -> GoalSpec("Finish ${1 + level} drives combining at least three different disciplines.", route(atLeast(AchievementMetric.MULTI_DISCIPLINE_DRIVES, (1 + level).toDouble())))
            8 -> GoalSpec("Trigger ${1 + level} events combining a drift with a hard braking phase.", route(atLeast(AchievementMetric.DRIFT_BRAKE_COMBOS, (1 + level).toDouble())), secret = level >= 6)
            else -> GoalSpec("Trigger ${1 + level} rare chaos combinations detected from live telemetry.", route(atLeast(AchievementMetric.CHAOS_COMBO_EVENTS, (1 + level).toDouble())), secret = true)
        }
    }

    private fun buildSeries(
        prefix: String,
        category: AchievementCategory,
        familyNames: List<String>,
        spec: (family: Int, level: Int) -> GoalSpec
    ): List<AchievementDefinition> {
        require(familyNames.size == 10)
        return buildList(100) {
            for (family in 0 until 10) {
                for (level in 0 until 10) {
                    val goal = spec(family, level)
                    add(
                        AchievementDefinition(
                            id = "${prefix}_${family.toString().padStart(2, '0')}_${level.toString().padStart(2, '0')}",
                            title = goal.titleOverride ?: "${stageWords[level]} ${familyNames[family]}",
                            description = goal.description,
                            category = category,
                            rarity = rarityFor(level),
                            routes = goal.routes,
                            secret = goal.secret
                        )
                    )
                }
            }
        }
    }

    private fun rarityFor(level: Int): AchievementRarity = when (level) {
        in 0..2 -> AchievementRarity.COMMON
        in 3..4 -> AchievementRarity.SKILLED
        in 5..6 -> AchievementRarity.EXPERT
        in 7..8 -> AchievementRarity.EXTREME
        else -> AchievementRarity.INSANE
    }
}

private fun AchievementMetric.current(progress: DriverProgress): Double = when (this) {
    AchievementMetric.LEGACY_COUNT -> progress.legacyAchievementCount.toDouble()
    AchievementMetric.TOTAL_XP -> progress.totalXp.toDouble()
    AchievementMetric.DRIVER_LEVEL -> progress.level.toDouble()
    AchievementMetric.ACHIEVEMENTS_UNLOCKED -> progress.achievements.count { it != AchievementCatalog.MASTER_ID }.toDouble()
    AchievementMetric.TOP_SPEED_MPH -> progress.topSpeedMph
    AchievementMetric.TOTAL_DISTANCE_MILES -> progress.totalDistanceMeters / 1609.344
    AchievementMetric.TOTAL_DRIVE_HOURS -> progress.totalDriveSeconds / 3600.0
    AchievementMetric.SESSION_COUNT -> progress.sessionsCompleted.toDouble()
    AchievementMetric.CLEAN_SESSION_COUNT -> progress.cleanSessions.toDouble()
    AchievementMetric.TOTAL_SHIFTS -> progress.totalShifts.toDouble()
    AchievementMetric.QUARTER_MILE_RUNS -> progress.quarterMileRuns.toDouble()
    AchievementMetric.BRAKE_RUNS -> progress.brakeRuns.toDouble()
    AchievementMetric.TOTAL_CRASHES -> progress.totalCrashes.toDouble()
    AchievementMetric.BEST_DRIFT_SCORE -> maxOf(progress.bestDriftScore.toDouble(), progress.achievementStats[name] ?: 0.0)
    AchievementMetric.BEST_DRIFT_ANGLE -> maxOf(progress.bestDriftAngleDeg, progress.achievementStats[name] ?: 0.0)
    else -> progress.achievementStats[name] ?: 0.0
}

private fun atLeast(metric: AchievementMetric, target: Double) =
    AchievementCondition(metric, target, AchievementComparison.AT_LEAST)

private fun atMost(metric: AchievementMetric, target: Double) =
    AchievementCondition(metric, target, AchievementComparison.AT_MOST)

private fun route(vararg conditions: AchievementCondition): List<List<AchievementCondition>> =
    listOf(conditions.toList())

private fun formatMetricValue(metric: AchievementMetric, value: Double): String {
    if (value <= 0.0 && metric.lowerIsBetter) return "not set"
    val body = when {
        metric == AchievementMetric.BEST_PERFECT_SHIFT_RATIO -> "${value.roundToInt()}"
        metric.unit == " sec" && value >= 60.0 -> {
            val minutes = value / 60.0
            if (minutes >= 60.0) "${format1(minutes / 60.0)} hr" else "${format1(minutes)} min"
        }
        value >= 10_000.0 -> formatWhole(value)
        value >= 100.0 -> value.roundToInt().toString()
        value >= 10.0 -> format1(value)
        else -> format2(value)
    }
    return if (body.endsWith(" hr") || body.endsWith(" min")) body else body + metric.unit
}

private fun formatWhole(value: Double): String = "%,.0f".format(value)
private fun format1(value: Double): String = "%.1f".format(value)
private fun format2(value: Double): String = "%.2f".format(value)
