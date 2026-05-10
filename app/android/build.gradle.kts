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
    val proj = this
    val fixNamespace = {
        if (proj.plugins.hasPlugin("com.android.library")) {
            val libExt = proj.extensions.findByType(com.android.build.gradle.LibraryExtension::class.java)
            if (libExt != null && (libExt.namespace == null || libExt.namespace!!.isEmpty())) {
                val manifestFile = proj.file("src/main/AndroidManifest.xml")
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
    
    if (proj.state.executed) {
        fixNamespace()
    } else {
        proj.afterEvaluate { fixNamespace() }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
