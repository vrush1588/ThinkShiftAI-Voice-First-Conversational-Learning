// agora_rtc_engine's own android/build.gradle falls back to compileSdkVersion 31
// if these extra properties aren't set, which conflicts with AndroidX deps that
// require compileSdk 34+. Setting them here makes the plugin pick up the same
// values as the app module (see app/build.gradle.kts).
rootProject.extra["compileSdkVersion"] = 34
rootProject.extra["minSdkVersion"] = 24

allprojects {
    repositories {
        google()
        mavenCentral()
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

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
