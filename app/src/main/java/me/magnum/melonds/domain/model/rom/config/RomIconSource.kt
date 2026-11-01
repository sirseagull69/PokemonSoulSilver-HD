package me.magnum.melonds.domain.model.rom.config

enum class RomIconSource {
    DEFAULT,
    NATIVE,
    RETRO_ACHIEVEMENTS;

    fun resolve(globalCoversEnabled: Boolean): RomIconSource =
        if (this == DEFAULT && !globalCoversEnabled) NATIVE else this

    fun usesRetroAchievements(globalEnabled: Boolean, hasAchievements: Boolean?): Boolean = when (this) {
        DEFAULT -> globalEnabled && hasAchievements != false
        NATIVE -> false
        RETRO_ACHIEVEMENTS -> true
    }
}
