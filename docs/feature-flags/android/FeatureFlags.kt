// FeatureFlags.kt
object FeatureFlags {
    // 本地默认；远程配置(Remote Config)覆盖
    private val defaults = mapOf("checkout_new_ui_enabled" to false)
    fun isEnabled(key: String): Boolean =
        RemoteConfig.getBoolean(key).takeIf { it } ?: defaults[key] ?: false
}
