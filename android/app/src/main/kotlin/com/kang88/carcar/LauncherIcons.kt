package com.kang88.carcar

import android.app.Activity
import android.content.ComponentName
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.plugin.common.MethodChannel

/** Stable component names preserve the selected icon across app updates. */
object LauncherIconAliases {
    val aliases: Map<String?, String> = linkedMapOf<String?, String>(null to "LauncherDefault").apply {
        (1..5).forEach { put("floor_f$it", "LauncherFloorF$it") }
        (1..6).forEach { put("floor_b$it", "LauncherFloorB$it") }
    }

    fun aliasFor(iconId: String?): String = aliases[iconId]
        ?: throw IllegalArgumentException("Unsupported launcher icon")

    fun enabled(alias: String, state: Int): Boolean {
        require(alias in aliases.values)
        return state == PackageManager.COMPONENT_ENABLED_STATE_ENABLED ||
            (state == PackageManager.COMPONENT_ENABLED_STATE_DEFAULT && alias == aliasFor(null))
    }

    fun current(states: Map<String, Int>): String? {
        check(states.keys == aliases.values.toSet()) { "Missing launcher components" }
        val selected = states.filter { enabled(it.key, it.value) }.keys
        check(selected.size == 1) { "Ambiguous launcher state" }
        return aliases.entries.single { it.value == selected.single() }.key
    }

    /** Enable the destination first on pre-33 systems, so no step removes every entry. */
    fun changes(iconId: String?): List<Pair<String, Int>> {
        val selected = aliasFor(iconId)
        return listOf(selected to PackageManager.COMPONENT_ENABLED_STATE_ENABLED) +
            aliases.values.filter { it != selected }.map { it to PackageManager.COMPONENT_ENABLED_STATE_DISABLED }
    }
}

class LauncherIcons(private val activity: Activity) {
    private val manager get() = activity.packageManager
    private fun component(alias: String) = ComponentName(activity.packageName, "${activity.packageName}.$alias")
    private fun states() = LauncherIconAliases.aliases.values.associateWith {
        manager.getComponentEnabledSetting(component(it))
    }
    private fun state(): Map<String, Any?> = mapOf("supported" to true, "iconId" to LauncherIconAliases.current(states()))

    fun read(result: MethodChannel.Result) {
        try { result.success(state()) }
        catch (_: Exception) { result.error("icon_state_invalid", "앱 아이콘 상태를 확인하지 못했어요. 다시 시도해 주세요.", null) }
    }

    fun set(args: Map<*, *>, result: MethodChannel.Result) {
        if (!args.containsKey("iconId") || (args["iconId"] != null && args["iconId"] !is String)) {
            result.error("invalid_icon", "변경할 층수 아이콘을 확인해 주세요.", null); return
        }
        val iconId = args["iconId"] as String?
        val changes = try { LauncherIconAliases.changes(iconId) }
        catch (_: IllegalArgumentException) {
            result.error("invalid_icon", "지원하는 층수 아이콘을 선택해 주세요.", null); return
        }
        if (activity.isFinishing || activity.isDestroyed) {
            result.error("icon_change_busy", "앱으로 돌아온 뒤 다시 시도해 주세요.", null); return
        }
        var previous: Map<String, Int>? = null
        try {
            previous = states()
            if (LauncherIconAliases.current(previous) == iconId) { result.success(state()); return }
            apply(changes)
            val actual = state()
            check(actual["iconId"] == iconId)
            result.success(actual)
        } catch (_: Exception) {
            // Restore the exact prior OS settings, enabling old entries before disabling new ones.
            previous?.let { old ->
                try {
                    apply(old.entries.sortedBy { if (LauncherIconAliases.enabled(it.key, it.value)) 0 else 1 }
                        .map { it.key to it.value })
                } catch (_: Exception) { /* Never claim a successful change when rollback is unavailable. */ }
            }
            result.error("icon_change_failed", "아이콘을 바꾸지 못했어요. 잠시 후 다시 시도해 주세요.", null)
        }
    }

    private fun apply(changes: List<Pair<String, Int>>) {
        if (Build.VERSION.SDK_INT >= 33) {
            manager.setComponentEnabledSettings(changes.map { (alias, enabled) ->
                PackageManager.ComponentEnabledSetting(component(alias), enabled, PackageManager.DONT_KILL_APP)
            })
        } else {
            changes.forEach { (alias, enabled) ->
                manager.setComponentEnabledSetting(component(alias), enabled, PackageManager.DONT_KILL_APP)
            }
        }
    }
}
