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

// Fix for plugins that still use deprecated package= in AndroidManifest.xml (AGP 8.11+)
subprojects {
    afterEvaluate {
        if (project.plugins.hasPlugin("com.android.library")) {
            val libExt = project.extensions.findByType(com.android.build.gradle.LibraryExtension::class.java)
            if (libExt != null && (libExt.namespace == null || libExt.namespace!!.isEmpty())) {
                val manifestFile = project.file("src/main/AndroidManifest.xml")
                if (manifestFile.exists()) {
                    val content = manifestFile.readText()
                    val match = Regex("""package\s*=\s*"([^"]+)"""").find(content)
                    if (match != null) {
                        libExt.namespace = match.groupValues[1]
                    }
                }
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
