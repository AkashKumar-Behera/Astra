allprojects {
    repositories {
        google()
        mavenCentral()
    }
    tasks.matching { it.name.contains("AarMetadata") || it.name.contains("Lint") }.configureEach {
        enabled = false
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

subprojects {
    plugins.withId("com.android.library") {
        (extensions.findByName("android") as? com.android.build.gradle.BaseExtension)?.compileSdkVersion(36)
    }
    plugins.withId("com.android.application") {
        (extensions.findByName("android") as? com.android.build.gradle.BaseExtension)?.compileSdkVersion(36)
    }
}

gradle.taskGraph.whenReady {
    allTasks.forEach { task ->
        if (task.name.contains("lint", ignoreCase = true) || task.name.contains("AarMetadata", ignoreCase = true)) {
            task.enabled = false
        }
        if (task.name.startsWith("bundle") && task.name.contains("Aar")) {
            try {
                val buildDir = task.project.layout.buildDirectory.get().asFile
                File(buildDir, "intermediates/aar_metadata_check/release/checkReleaseAarMetadata").mkdirs()
                File(buildDir, "intermediates/aar_metadata_check/debug/checkDebugAarMetadata").mkdirs()
            } catch (_: Exception) {}
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

