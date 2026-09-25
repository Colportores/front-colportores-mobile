package com.colportores.colportores_mobile

import android.app.KeyguardManager
import android.content.Context
import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyInfo
import android.security.keystore.KeyProperties
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.security.KeyStore
import javax.crypto.KeyGenerator
import javax.crypto.SecretKeyFactory

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        registrarCanalSeguridadDispositivo(flutterEngine)
    }

    /**
     * Canal `colportores/seguridad_dispositivo` (ADR-006, HU-AUTH-009): lo que la app pregunta del
     * equipo antes de crear la DB local. Del lado de Dart, `SeguridadDispositivoCanal`.
     *
     * - `bloqueoPantalla` → si hay PIN, patrón, contraseña o biometría (`isDeviceSecure`).
     * - `nivelAlmacen` → `"hardware"` (TEE o StrongBox) o `"software"` (Supuesto S10).
     *
     * Nunca devuelve material secreto: la clave de prueba se crea y se borra acá mismo.
     */
    private fun registrarCanalSeguridadDispositivo(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CANAL).setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "bloqueoPantalla" -> result.success(tieneBloqueoPantalla())
                    "nivelAlmacen" -> result.success(nivelAlmacen())
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                // Solo el tipo: el mensaje de una excepción del Keystore no tiene por qué ir a Dart.
                result.error("SEGURIDAD_DISPOSITIVO", e.javaClass.simpleName, null)
            }
        }
    }

    private fun tieneBloqueoPantalla(): Boolean {
        val keyguard = getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
        return keyguard.isDeviceSecure
    }

    /**
     * Crea una clave AES de prueba en el Android Keystore, lee su `KeyInfo` y la borra. El nivel de
     * esa clave es el del Keystore del equipo, el mismo que usa `flutter_secure_storage` para
     * envolver la DEK: `securityLevel` en API 31+, `isInsideSecureHardware` antes.
     */
    private fun nivelAlmacen(): String {
        val keyStore = KeyStore.getInstance(ANDROID_KEYSTORE).apply { load(null) }
        try {
            val generador = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, ANDROID_KEYSTORE)
            generador.init(
                KeyGenParameterSpec.Builder(
                    ALIAS_PRUEBA,
                    KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
                )
                    .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                    .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                    .setKeySize(256)
                    .build(),
            )
            val clave = generador.generateKey()
            val fabrica = SecretKeyFactory.getInstance(clave.algorithm, ANDROID_KEYSTORE)
            val info = fabrica.getKeySpec(clave, KeyInfo::class.java) as KeyInfo
            val enHardware =
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    when (info.securityLevel) {
                        KeyProperties.SECURITY_LEVEL_TRUSTED_ENVIRONMENT,
                        KeyProperties.SECURITY_LEVEL_STRONGBOX,
                        KeyProperties.SECURITY_LEVEL_UNKNOWN_SECURE,
                        -> true
                        // SOFTWARE, y UNKNOWN: ante la duda, se pide el consentimiento.
                        else -> false
                    }
                } else {
                    @Suppress("DEPRECATION")
                    info.isInsideSecureHardware
                }
            return if (enHardware) "hardware" else "software"
        } finally {
            try {
                keyStore.deleteEntry(ALIAS_PRUEBA)
            } catch (e: Exception) {
                // Una clave de prueba huérfana no guarda nada: no se tapa el resultado por esto.
            }
        }
    }

    companion object {
        private const val CANAL = "colportores/seguridad_dispositivo"
        private const val ANDROID_KEYSTORE = "AndroidKeyStore"
        private const val ALIAS_PRUEBA = "colportores_sonda_nivel_keystore"
    }
}
