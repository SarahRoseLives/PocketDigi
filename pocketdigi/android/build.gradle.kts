import org.gradle.api.tasks.Delete
import org.gradle.api.file.Directory

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

// --- FIX START: Patch older libraries for Android 12+ support ---
// This block is placed BEFORE evaluationDependsOn to ensure it registers correctly.
subprojects {
    val proj = this

    if (proj.name == "flutter_bluetooth_serial") {
        // Define the logic to patch the library
        val configureLibrary = {
            val android = proj.extensions.findByName("android")
            if (android != null) {
                try {
                    // 1. Fix 'Namespace not specified' error
                    val setNamespace = android.javaClass.getMethod("setNamespace", String::class.java)
                    setNamespace.invoke(android, "io.github.edufolly.flutterbluetoothserial")

                    // 2. Fix 'lStar not found' error (Force SDK 34)
                    val setCompileSdk = android.javaClass.getMethod("setCompileSdkVersion", Int::class.javaPrimitiveType)
                    setCompileSdk.invoke(android, 34)

                    println("SUCCESS: Patched flutter_bluetooth_serial (Namespace & SDK 34)")
                } catch (e: Exception) {
                    println("WARNING: Could not patch flutter_bluetooth_serial: $e")
                }
            }
        }

        // Safety Check: If project is already evaluated, run now. Otherwise, wait.
        if (proj.state.executed) {
            configureLibrary()
        } else {
            proj.afterEvaluate {
                configureLibrary()
            }
        }
    }
}
// --- FIX END ---

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}