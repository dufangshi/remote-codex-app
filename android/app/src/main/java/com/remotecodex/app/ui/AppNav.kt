package com.remotecodex.app.ui

sealed class AppRoute {
    data object Connect : AppRoute()
    data object Home : AppRoute()
    data object Guide : AppRoute()
    data object Portal : AppRoute()
    data object Devices : AppRoute()
    data object Account : AppRoute()
    data class Workspaces(val deviceId: String) : AppRoute()
    data class WorkspaceNew(val deviceId: String) : AppRoute()
    data class Threads(val deviceId: String, val workspaceId: String) : AppRoute()
    data class ThreadNew(val deviceId: String, val workspaceId: String?) : AppRoute()
    data class ThreadImport(val deviceId: String) : AppRoute()
    data class ThreadDetail(
        val deviceId: String,
        val threadId: String,
        val workspaceId: String? = null,
    ) : AppRoute()
}

class NavController(initial: AppRoute) {
    private val stack = ArrayDeque<AppRoute>().apply { add(initial) }

    val current: AppRoute get() = stack.last()

    fun canGoBack(): Boolean = stack.size > 1

    fun push(route: AppRoute) {
        if (stack.lastOrNull() == route) return
        stack.addLast(route)
    }

    fun replace(route: AppRoute) {
        if (stack.isNotEmpty()) stack.removeLast()
        stack.addLast(route)
    }

    fun reset(route: AppRoute) {
        stack.clear()
        stack.addLast(route)
    }

    fun pop(): Boolean {
        if (stack.size <= 1) return false
        stack.removeLast()
        return true
    }

    fun popTo(predicate: (AppRoute) -> Boolean): Boolean {
        val index = stack.indexOfLast(predicate)
        if (index < 0) return false
        while (stack.size > index + 1) stack.removeLast()
        return true
    }

    fun backFrom(route: AppRoute): AppRoute? {
        return when (route) {
            is AppRoute.ThreadDetail -> {
                val workspaceId = route.workspaceId
                if (!workspaceId.isNullOrBlank()) AppRoute.Threads(route.deviceId, workspaceId)
                else AppRoute.Workspaces(route.deviceId)
            }
            is AppRoute.ThreadNew -> {
                val workspaceId = route.workspaceId
                if (!workspaceId.isNullOrBlank()) AppRoute.Threads(route.deviceId, workspaceId)
                else AppRoute.Workspaces(route.deviceId)
            }
            is AppRoute.ThreadImport -> AppRoute.Workspaces(route.deviceId)
            is AppRoute.Threads -> AppRoute.Workspaces(route.deviceId)
            is AppRoute.WorkspaceNew -> AppRoute.Workspaces(route.deviceId)
            is AppRoute.Workspaces -> AppRoute.Devices
            AppRoute.Account, AppRoute.Devices, AppRoute.Guide, AppRoute.Portal -> AppRoute.Home
            AppRoute.Home -> if (canGoBack() && stack.first() is AppRoute.Connect) AppRoute.Connect else null
            AppRoute.Connect -> null
        }
    }
}
