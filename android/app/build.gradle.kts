plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    // Se aplica más abajo, solo si google-services.json conoce el applicationId de este build.
    id("com.google.gms.google-services") apply false
}

// Variables que pone el workflow de despliegue (.github/workflows/android-build.yml). Sin ellas (desarrollo local, Docker)
// el build es el de siempre: mismo applicationId, mismo nombre y release firmado con la clave de debug.
// - COLPORTORES_APP_ID_SUFFIX: sufijo del applicationId (".staging"), para instalar staging al lado de producción.
// - COLPORTORES_APP_NAME: nombre visible de la app en el lanzador.
// - ANDROID_KEYSTORE_PATH / ANDROID_KEYSTORE_PASSWORD / ANDROID_KEY_ALIAS / ANDROID_KEY_PASSWORD: la clave de firma, que el
//   workflow decodifica desde los secretos del environment a un archivo temporal. Nunca se versiona (.gitignore: *.jks).
val sufijoAppId: String = System.getenv("COLPORTORES_APP_ID_SUFFIX").orEmpty()
val nombreApp: String = System.getenv("COLPORTORES_APP_NAME").orEmpty().ifEmpty { "colportores_mobile" }
val rutaKeystore: String = System.getenv("ANDROID_KEYSTORE_PATH").orEmpty()

android {
    namespace = "com.colportores.colportores_mobile"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // flutter_local_notifications (recordatorios, HU-NOT-002) usa java.time en Android viejos.
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.colportores.colportores_mobile"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        if (sufijoAppId.isNotEmpty()) applicationIdSuffix = sufijoAppId
        manifestPlaceholders["appLabel"] = nombreApp
    }

    signingConfigs {
        if (rutaKeystore.isNotEmpty()) {
            create("release") {
                storeFile = file(rutaKeystore)
                storePassword = System.getenv("ANDROID_KEYSTORE_PASSWORD")
                keyAlias = System.getenv("ANDROID_KEY_ALIAS")
                keyPassword = System.getenv("ANDROID_KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            // Con la clave del environment (CI de staging/production) firma con ella; sin ella, con la de debug, así
            // `flutter run --release` sigue andando en local.
            signingConfig = signingConfigs.getByName(if (rutaKeystore.isNotEmpty()) "release" else "debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

// Firebase Cloud Messaging (push remotas, HU-NOT-003, ADR-014). El plugin de Google Services convierte
// google-services.json en los recursos que lee Firebase.initializeApp(), y falla el build si el archivo no
// tiene un cliente con el applicationId que se compila. Hoy el archivo trae solo la app de staging
// (com.colportores.colportores_mobile.staging, #694): sin sufijo (desarrollo local, Docker) y en producción,
// hasta que se registre esa app en Firebase, el build sigue sin el plugin, la app arranca sin push (main.dart
// deja el fake) y acá se avisa.
val idDeLaApp = "com.colportores.colportores_mobile$sufijoAppId"
val archivoFirebase = file("google-services.json")
val firebaseConoceLaApp: Boolean =
    archivoFirebase.isFile &&
        (groovy.json.JsonSlurper().parse(archivoFirebase) as Map<*, *>)["client"]
            .let { it as? List<*> }
            .orEmpty()
            .any { cliente ->
                val info = (cliente as? Map<*, *>)?.get("client_info") as? Map<*, *>
                val clienteAndroid = info?.get("android_client_info") as? Map<*, *>
                clienteAndroid?.get("package_name") == idDeLaApp
            }
if (firebaseConoceLaApp) {
    apply(plugin = "com.google.gms.google-services")
} else {
    logger.warn(
        "Firebase: google-services.json no tiene la app $idDeLaApp; se compila sin push remotas (HU-NOT-003).",
    )
}
