pluginManagement {
    repositories {
        // Kotlin/Android plugin markers are published here first. Keep the
        // dedicated portal ahead of mirrors to avoid transient marker misses.
        gradlePluginPortal()
        google()
        mavenCentral()
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.name = "MCTier-Android"
include(":app")
