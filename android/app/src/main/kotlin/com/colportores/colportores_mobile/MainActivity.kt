package com.colportores.colportores_mobile

import android.app.KeyguardManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.StatFs
import android.provider.Settings
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
        registrarCanalAlmacenamientoTiles(flutterEngine)
    }

    /**
     * Canal `colportores/almacenamiento_tiles` (HU-SYNC-010, #189): lo que la descarga de los mapas
     * offline pregunta del almacenamiento. Del lado de Dart, `AlmacenamientoTilesCanal`. Los dos
     * métodos reciben `{ruta}`.
     *
     * - `bytesLibres` → bytes que la app puede usar en el volumen de `ruta` (`StatFs.availableBytes`).
     * - `excluirDeBackup` → `true` sin hacer nada: en Android la app ya tiene `allowBackup="false"`
     *   (AndroidManifest.xml), así que ni los mapas ni nada de la app viajan a la copia de seguridad.
     */
    private fun registrarCanalAlmacenamientoTiles(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CANAL_TILES).setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "bytesLibres" -> {
                        val ruta = call.argument<String>("ruta")
                        if (ruta == null) {
                            result.error("ALMACENAMIENTO_TILES", "falta la ruta", null)
                        } else {
                            result.success(StatFs(ruta).availableBytes)
                        }
                    }
                    "excluirDeBackup" -> result.success(true)
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("ALMACENAMIENTO_TILES", e.javaClass.simpleName, null)
            }
        }
    }

    /**
     * Canal `colportores/seguridad_dispositivo` (ADR-006, HU-AUTH-009): lo que la app pregunta del
     * equipo antes de crear la DB local. Del lado de Dart, `SeguridadDispositivoCanal`.
     *
     * - `bloqueoPantalla` → si hay PIN, patrón, contraseña o biometría (`isDeviceSecure`).
     * - `nivelAlmacen` → `"hardware"` (TEE o StrongBox) o `"software"` (Supuesto S10).
     * - `abrirAjustesSeguridad` / `abrirAjustesAlmacenamiento` / `abrirAjustesRed` → abre esa pantalla
     *   de los ajustes (vista 13, #222; «Activar datos» del mapa, #190) y devuelve si pudo.
     *
     * - `abrirEnlace` → abre `{url}` con el sistema (chat de soporte por WhatsApp, vista 13) y
     *   devuelve si pudo. Solo `https://wa.me/...`: cualquier otro enlace se rechaza.
     *
     * Nunca devuelve material secreto: la clave de prueba se crea y se borra acá mismo.
     */
    private fun registrarCanalSeguridadDispositivo(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CANAL).setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "bloqueoPantalla" -> result.success(tieneBloqueoPantalla())
                    "nivelAlmacen" -> result.success(nivelAlmacen())
                    "abrirAjustesSeguridad" -> result.success(abrirAjustes(Settings.ACTION_SECURITY_SETTINGS))
                    "abrirAjustesAlmacenamiento" ->
                        result.success(abrirAjustes(Settings.ACTION_INTERNAL_STORAGE_SETTINGS))
                    "abrirAjustesRed" -> result.success(abrirAjustes(Settings.ACTION_WIRELESS_SETTINGS))
                    "abrirEnlace" -> result.success(abrirEnlace(call.argument<String>("url")))
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                // Solo el tipo: el mensaje de una excepción del Keystore no tiene por qué ir a Dart.
                result.error("SEGURIDAD_DISPOSITIVO", e.javaClass.simpleName, null)
            }
        }
    }

    /**
     * Abre la pantalla de ajustes [accion] y devuelve `true`. Si el equipo no la tiene, abre los
     * ajustes generales pero devuelve `false`: no llegó a la pantalla pedida, y la app le dice al
     * usuario cómo llegar a mano. También `false` si ninguna abre.
     */
    private fun abrirAjustes(accion: String): Boolean {
        try {
            startActivity(Intent(accion).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            return true
        } catch (e: Exception) {
            // Sin esa pantalla: se intenta con los ajustes generales.
        }
        try {
            startActivity(Intent(Settings.ACTION_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        } catch (e: Exception) {
            // Tampoco abren.
        }
        return false
    }

    /**
     * Abre [url] (solo `https://wa.me/...`) con la app que la resuelva: WhatsApp si está instalado
     * (`wa.me` es un enlace verificado suyo) y, si no, el navegador. `false` si el enlace no es de
     * `wa.me` o ninguna app lo abre.
     */
    private fun abrirEnlace(url: String?): Boolean {
        if (url == null) return false
        val uri = Uri.parse(url)
        if (uri.scheme != "https" || uri.host != "wa.me") return false
        return try {
            startActivity(Intent(Intent.ACTION_VIEW, uri).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            true
        } catch (e: Exception) {
            false
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
        private const val CANAL_TILES = "colportores/almacenamiento_tiles"
        private const val ANDROID_KEYSTORE = "AndroidKeyStore"
        private const val ALIAS_PRUEBA = "colportores_sonda_nivel_keystore"
    }
}
