plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.kotlin.serialization)
}

android {
    namespace = "com.theagilemonkeys.shepherdr.remote"
    compileSdk = 36

    defaultConfig {
        applicationId = "com.theagilemonkeys.shepherdr.remote"
        // Android 10 is the first with TLS 1.3, which the Mac's relay requires.
        minSdk = 29
        targetSdk = 36
        versionCode = 1
        versionName = "1.0"
    }

    buildTypes {
        debug {
            applicationIdSuffix = ".dev"
        }
        release {
            isMinifyEnabled = false
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildFeatures {
        compose = true
    }

    testOptions {
        unitTests.isReturnDefaultValues = true
    }
}

// The fonts and arcade pictures the Mac and iPhone apps use, from where they live in this repository,
// renamed as Android's resources want them.
val repository = rootDir.parentFile
val sharedResources = tasks.register<Sync>("sharedResources") {
    into(layout.buildDirectory.dir("generated/shared-res"))
    from(repository.resolve("Sources/ShepherdrTerminalUI/Resources/Fonts")) {
        include("FiraCode-Regular.ttf", "FiraCode-Medium.ttf", "FiraCode-SemiBold.ttf", "FiraCode-Bold.ttf")
        rename { it.lowercase().replace('-', '_') }
        into("font")
    }
    val assets = repository.resolve("iOS/ShepherdrRemote/Assets.xcassets")
    from(assets.resolve("ArcadeDog.imageset/icon.png")) { rename { "arcade_dog.png" }; into("drawable-nodpi") }
    from(assets.resolve("ArcadeTitle.imageset/header.png")) { rename { "arcade_title.png" }; into("drawable-nodpi") }
}
android.sourceSets["main"].res.srcDir(sharedResources.map { it.destinationDir })
tasks.named("preBuild") { dependsOn(sharedResources) }

kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}

dependencies {
    implementation(platform(libs.compose.bom))
    implementation(libs.compose.ui)
    implementation(libs.compose.ui.graphics)
    implementation(libs.compose.ui.tooling.preview)
    implementation(libs.compose.foundation)
    implementation(libs.compose.material3)
    implementation(libs.compose.material.icons)
    implementation(libs.activity.compose)
    implementation(libs.lifecycle.process)
    implementation(libs.lifecycle.runtime.compose)
    implementation(libs.okhttp)
    implementation(libs.serialization.json)
    implementation(libs.code.scanner)
    implementation(libs.termux.emulator)
    implementation(libs.termux.view)
    debugImplementation(libs.compose.ui.tooling)

    testImplementation(libs.junit)
}
