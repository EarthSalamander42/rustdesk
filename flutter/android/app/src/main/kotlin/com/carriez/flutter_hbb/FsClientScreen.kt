package com.carriez.flutter_hbb

/**
 * FS Support — Mode « Ecran client ».
 *
 * Ce mode (prolonge et englobe l'ancien « Acces direct ») prepare un ecran mural de client pour
 * une gestion a distance sans intervention sur place. Il autorise, UNIQUEMENT quand il est actif,
 * deux validations automatiques par le service d'accessibilite (voir InputService) :
 *   - la fenetre systeme de consentement a la capture d'ecran (MediaProjection) ;
 *   - l'installateur de paquets, pour la propre mise a jour de FS Support.
 *
 * Source de verite cote Kotlin : un booleen dans les SharedPreferences RustDesk
 * (KEY_SHARED_PREFERENCES / KEY_FS_CLIENT_SCREEN), ecrit par l'app Flutter via le canal
 * `fs_set_client_screen`. Lu sans FFI pour fonctionner au boot et dans le service d'accessibilite,
 * et pour pouvoir etre pose en test e2e (ecriture directe des SharedPreferences en root).
 *
 * Les deux « fenetres de temps » (capture / installation) bornent dans le temps toute validation
 * automatique : hors de la fenetre ouverte juste apres l'action de l'app, le service ne clique rien.
 * Tout est garde par try/catch : jamais de plantage, seulement des Log.i / Log.w.
 */

import android.content.Context
import android.util.Log
import io.flutter.embedding.android.FlutterActivity

object FsClientScreen {
    private const val logTag = "FsClientScreen"

    // Cle du booleen dans KEY_SHARED_PREFERENCES.
    const val KEY = "KEY_FS_CLIENT_SCREEN"

    // Duree de la fenetre d'auto-validation de la capture d'ecran, apres l'appel de l'app a
    // createScreenCaptureIntent (voir PermissionRequestTransparentActivity). 30 s : large pour un
    // boitier lent, mais borne nette.
    private const val CAPTURE_WINDOW_MS = 30_000L

    // Duree de la fenetre d'auto-validation de l'installateur, apres le lancement de l'installation
    // de la propre mise a jour (voir FsSelfUpdate). L'installateur peut tarder a s'ouvrir.
    private const val INSTALL_WINDOW_MS = 90_000L

    @Volatile
    private var captureConsentUntil = 0L

    @Volatile
    private var installConsentUntil = 0L

    /** Le mode « Ecran client » est-il actif sur cet appareil ? */
    fun isEnabled(context: Context): Boolean {
        return try {
            context.applicationContext
                .getSharedPreferences(KEY_SHARED_PREFERENCES, FlutterActivity.MODE_PRIVATE)
                .getBoolean(KEY, false)
        } catch (e: Exception) {
            Log.w(logTag, "FS Support : lecture du mode Ecran client impossible : $e")
            false
        }
    }

    /** Pose l'etat du mode (appele par le canal Flutter `fs_set_client_screen`). */
    fun setEnabled(context: Context, enabled: Boolean) {
        try {
            context.applicationContext
                .getSharedPreferences(KEY_SHARED_PREFERENCES, FlutterActivity.MODE_PRIVATE)
                .edit()
                .putBoolean(KEY, enabled)
                .apply()
        } catch (e: Exception) {
            Log.w(logTag, "FS Support : ecriture du mode Ecran client impossible : $e")
        }
    }

    /** Ouvre la fenetre d'auto-validation de la capture (a appeler juste avant la fenetre systeme). */
    fun markCaptureConsentWindow() {
        captureConsentUntil = System.currentTimeMillis() + CAPTURE_WINDOW_MS
    }

    /** Ouvre la fenetre d'auto-validation de l'installateur (a appeler juste avant son lancement). */
    fun markInstallConsentWindow() {
        installConsentUntil = System.currentTimeMillis() + INSTALL_WINDOW_MS
    }

    fun captureConsentActive(): Boolean = System.currentTimeMillis() < captureConsentUntil
    fun installConsentActive(): Boolean = System.currentTimeMillis() < installConsentUntil

    /** Referme la fenetre capture (apres une validation reussie, pour ne pas recliquer). */
    fun clearCaptureConsentWindow() {
        captureConsentUntil = 0L
    }

    /** Referme la fenetre installation (apres avoir clique « Terminé »/« Ouvrir »). */
    fun clearInstallConsentWindow() {
        installConsentUntil = 0L
    }
}
