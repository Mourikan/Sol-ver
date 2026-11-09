// Android module only included when an SDK is present (CI / dev machine).
// Engine (pure Kotlin/JVM) builds and tests anywhere.
val localProps = file("local.properties").takeIf { it.exists() }?.readText().orEmpty()
val androidSdk = System.getenv("ANDROID_HOME") ?: System.getenv("ANDROID_SDK_ROOT")
    ?: Regex("""sdk\.dir=(.+)""").find(localProps)?.groupValues?.get(1)

dependencyResolutionManagement {
    repositories {
        if (androidSdk != null) google()
        mavenCentral()
    }
}

rootProject.name = "SolVer"
include(":engine")
if (androidSdk != null) include(":app")
