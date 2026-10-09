package com.carriez.flutter_hbb

import android.Manifest.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS
import android.Manifest.permission.SYSTEM_ALERT_WINDOW
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import android.widget.Toast
import com.hjq.permissions.XXPermissions
import io.flutter.embedding.android.FlutterActivity
import java.io.File

const val DEBUG_BOOT_COMPLETED = "fr.fssolutions.support.DEBUG_BOOT_COMPLETED"
// FS Support : action de test (e2e emulateur UNIQUEMENT) pour declencher l'installation de la
// propre mise a jour sans personne devant l'ecran. Strictement gardee (voir handleDebugInstall).
const val DEBUG_INSTALL_APK = "fr.fssolutions.support.DEBUG_INSTALL_APK"
const val EXT_DEBUG_INSTALL_PATH = "path"

class BootReceiver : BroadcastReceiver() {
    private val logTag = "tagBootReceiver"

    override fun onReceive(context: Context, intent: Intent) {
        Log.d(logTag, "onReceive ${intent.action}")

        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED,
            DEBUG_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED -> handleStart(context)
            DEBUG_INSTALL_APK -> handleDebugInstall(context, intent)
            else -> {}
        }
    }

    // Demarrage du service hote : au boot, et apres une mise a jour de l'appli (MY_PACKAGE_REPLACED,
    // pour relancer la capture sans personne devant l'ecran).
    private fun handleStart(context: Context) {
        // FS Support acces direct : reactive seul le service d'accessibilite si l'appareil est
        // prepare (WRITE_SECURE_SETTINGS). No-op sans la permission (appareil grand public).
        FsDirectAccess.reactivateAccessibilityIfPossible(context)

        val clientScreen = FsClientScreen.isEnabled(context)
        val prefs = context.getSharedPreferences(KEY_SHARED_PREFERENCES, FlutterActivity.MODE_PRIVATE)
        val startOnBoot = prefs.getBoolean(KEY_START_ON_BOOT_OPT, false)

        // En mode « Ecran client », on demarre TOUJOURS, sans attendre le reglage ni la batterie/
        // superposition (la capture n'en depend pas) : c'est tout l'interet d'un ecran non surveille.
        // Hors de ce mode, comportement RustDesk historique : reglage + permissions requis.
        if (!clientScreen) {
            if (!startOnBoot) {
                Log.d(logTag, "KEY_START_ON_BOOT_OPT is false")
                return
            }
            if (!XXPermissions.isGranted(context, REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, SYSTEM_ALERT_WINDOW)) {
                Log.d(logTag, "REQUEST_IGNORE_BATTERY_OPTIMIZATIONS or SYSTEM_ALERT_WINDOW is not granted")
                return
            }
        }

        val it = Intent(context, MainService::class.java).apply {
            action = ACT_INIT_MEDIA_PROJECTION_AND_SERVICE
            putExtra(EXT_INIT_FROM_BOOT, true)
        }
        if (!clientScreen) {
            Toast.makeText(context, "RustDesk is Open", Toast.LENGTH_LONG).show()
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.startForegroundService(it)
        } else {
            context.startService(it)
        }
    }

    // FS Support (test e2e emulateur) : installe la propre mise a jour deja poussee sur l'appareil.
    // Gardes : mode « Ecran client » actif ; fichier sous getExternalFilesDir ; FsSelfUpdate verifie
    // en plus que l'APK est bien celui de FS Support. Inerte sur un appareil de production.
    private fun handleDebugInstall(context: Context, intent: Intent) {
        if (!FsClientScreen.isEnabled(context)) {
            Log.w(logTag, "FS Support : DEBUG_INSTALL_APK ignore (mode Ecran client inactif)")
            return
        }
        val path = intent.getStringExtra(EXT_DEBUG_INSTALL_PATH)
        if (path.isNullOrEmpty()) {
            Log.w(logTag, "FS Support : DEBUG_INSTALL_APK sans chemin")
            return
        }
        val file = try {
            File(path).canonicalFile
        } catch (e: Exception) {
            Log.w(logTag, "FS Support : chemin DEBUG_INSTALL_APK invalide : $e")
            return
        }
        val root = try {
            (context.getExternalFilesDir(null) ?: context.filesDir).canonicalFile
        } catch (e: Exception) {
            null
        }
        if (root == null || !file.path.startsWith(root.path + File.separator)) {
            Log.w(logTag, "FS Support : DEBUG_INSTALL_APK hors du dossier de l'appli : $file")
            return
        }
        FsSelfUpdate.installFromFile(context, file)
    }
}
