package com.carriez.flutter_hbb

/**
 * FS Support — Acces direct (prise en main sans personne devant l'ecran).
 *
 * Regroupe ce que l'app peut faire SEULE une fois l'appareil prepare par
 * res/fs/android/acces-direct.sh :
 *   - reactiver son propre service d'accessibilite si WRITE_SECURE_SETTINGS est
 *     accordee et que le service n'est pas actif (sans ecraser les autres) ;
 *   - renseigner l'etat reel des prerequis (capture sans fenetre, reglages securises).
 *
 * Tout est garde par try/catch : jamais de plantage, seulement des Log.i / Log.w.
 */

import android.Manifest
import android.app.AppOpsManager
import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Process
import android.provider.Settings
import android.util.Log

object FsDirectAccess {
    private const val logTag = "FsDirectAccess"

    // Op appops de la capture d'ecran : accordee = pas de fenetre de consentement (Android <= 13).
    private const val OPSTR_PROJECT_MEDIA = "android:project_media"

    /** Composant du service d'accessibilite FS Support, forme « applicationId/classe complete ». */
    fun accessibilityComponent(context: Context): String =
        ComponentName(context, InputService::class.java).flattenToString()

    fun hasWriteSecureSettings(context: Context): Boolean {
        return try {
            context.checkPermission(
                Manifest.permission.WRITE_SECURE_SETTINGS,
                Process.myPid(),
                Process.myUid()
            ) == PackageManager.PERMISSION_GRANTED
        } catch (e: Exception) {
            Log.w(logTag, "FS Support : verification WRITE_SECURE_SETTINGS impossible : $e")
            false
        }
    }

    /** La capture d'ecran peut-elle demarrer sans fenetre de consentement ? (appops PROJECT_MEDIA) */
    fun isProjectMediaAllowed(context: Context): Boolean {
        return try {
            val appOps = context.getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
            val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                appOps.unsafeCheckOpNoThrow(OPSTR_PROJECT_MEDIA, Process.myUid(), context.packageName)
            } else {
                @Suppress("DEPRECATION")
                appOps.checkOpNoThrow(OPSTR_PROJECT_MEDIA, Process.myUid(), context.packageName)
            }
            mode == AppOpsManager.MODE_ALLOWED
        } catch (e: Exception) {
            Log.w(logTag, "FS Support : verification PROJECT_MEDIA impossible : $e")
            false
        }
    }

    /** Le service d'accessibilite FS Support est-il present dans la configuration securisee ? */
    fun isAccessibilityServiceEnabled(context: Context): Boolean {
        return try {
            val component = accessibilityComponent(context)
            val enabled = Settings.Secure.getString(
                context.contentResolver,
                Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
            ) ?: ""
            val accessibilityOn = Settings.Secure.getInt(
                context.contentResolver,
                Settings.Secure.ACCESSIBILITY_ENABLED,
                0
            ) == 1
            accessibilityOn && containsComponent(enabled, component)
        } catch (e: Exception) {
            Log.w(logTag, "FS Support : lecture de l'accessibilite impossible : $e")
            false
        }
    }

    /**
     * Reactive le service d'accessibilite si c'est possible et necessaire.
     * @return true si le service est actif a la fin (deja actif ou reactive), false sinon.
     */
    fun reactivateAccessibilityIfPossible(context: Context): Boolean {
        return try {
            // Deja lie et operationnel : rien a faire.
            if (InputService.isOpen) {
                return true
            }
            val component = accessibilityComponent(context)
            if (isAccessibilityServiceEnabled(context)) {
                // Configure mais pas encore lie : le systeme s'en chargera, on ne force rien.
                return true
            }
            if (!hasWriteSecureSettings(context)) {
                Log.i(logTag, "FS Support : accessibilite inactive mais WRITE_SECURE_SETTINGS absente, rien a faire")
                return false
            }
            val cr = context.contentResolver
            val current = Settings.Secure.getString(cr, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES) ?: ""
            val newList = when {
                containsComponent(current, component) -> current
                current.isEmpty() -> component
                else -> "$current:$component"
            }
            Settings.Secure.putString(cr, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES, newList)
            Settings.Secure.putInt(cr, Settings.Secure.ACCESSIBILITY_ENABLED, 1)
            Log.i(logTag, "FS Support : service d'accessibilite reactive automatiquement")
            true
        } catch (e: Exception) {
            Log.w(logTag, "FS Support : reactivation de l'accessibilite en echec : $e")
            false
        }
    }

    /** Appartenance tolerante : chaque entree est deflattee et comparee au composant. */
    private fun containsComponent(list: String, component: String): Boolean {
        if (list.isEmpty()) return false
        val target = ComponentName.unflattenFromString(component)
        for (entry in list.split(':')) {
            if (entry.isEmpty()) continue
            if (entry == component) return true
            val parsed = ComponentName.unflattenFromString(entry)
            if (parsed != null && target != null && parsed == target) return true
        }
        return false
    }
}
