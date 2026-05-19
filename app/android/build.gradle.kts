allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// FlutterFire 플러그인이 참조하는 rootProject 속성
extra["FlutterFire"] = mapOf(
    "FirebaseSDKVersion" to "33.16.0",
    "compileSdk" to 35,
    "minSdk" to 23,
    "targetSdk" to 34,
)

val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
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
