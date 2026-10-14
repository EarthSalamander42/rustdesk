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
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.Looper
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

    // Fenetres RESSERREES : clic tolere en l'absence totale de texte lisible (cas (c) : certaines
    // ROM / emulateurs n'exposent pas le libelle a l'accessibilite). Bien plus court, une seule fois.
    private const val CAPTURE_TIGHT_MS = 10_000L
    private const val INSTALL_TIGHT_MS = 15_000L

    @Volatile
    private var captureConsentUntil = 0L

    @Volatile
    private var captureTightUntil = 0L

    @Volatile
    private var installConsentUntil = 0L

    @Volatile
    private var installTightUntil = 0L

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
        val now = System.currentTimeMillis()
        captureConsentUntil = now + CAPTURE_WINDOW_MS
        captureTightUntil = now + CAPTURE_TIGHT_MS
    }

    /** Ouvre la fenetre d'auto-validation de l'installateur (a appeler juste avant son lancement). */
    fun markInstallConsentWindow() {
        val now = System.currentTimeMillis()
        installConsentUntil = now + INSTALL_WINDOW_MS
        installTightUntil = now + INSTALL_TIGHT_MS
    }

    fun captureConsentActive(): Boolean = System.currentTimeMillis() < captureConsentUntil
    fun installConsentActive(): Boolean = System.currentTimeMillis() < installConsentUntil

    /** Fenetre resserree : clic tolere sans texte lisible (cas (c)). */
    fun captureTightActive(): Boolean = System.currentTimeMillis() < captureTightUntil
    fun installTightActive(): Boolean = System.currentTimeMillis() < installTightUntil

    /** Referme la fenetre capture (apres une validation reussie, pour ne pas recliquer). */
    fun clearCaptureConsentWindow() {
        captureConsentUntil = 0L
        captureTightUntil = 0L
    }

    // Relance automatique du service : au plus AUTO_START_MAX fois par AUTO_START_WINDOW_MS, pour
    // ne jamais boucler si le demarrage de la capture fait lui-meme tomber l'appli.
    private const val KEY_AUTO_STARTS = "KEY_FS_CLIENT_SCREEN_AUTO_STARTS"
    private const val AUTO_START_MAX = 3
    private const val AUTO_START_WINDOW_MS = 15 * 60_000L

    @Volatile
    private var autoStartScheduled = false

    /**
     * Mode « Ecran client » : relance le service de partage (comme au demarrage de l'appareil)
     * s'il ne tourne pas. Appele quand le systeme relie le service d'accessibilite — ce qu'il fait
     * aussi apres un arret brutal de l'appli — et a l'ouverture de l'appli. Sans cela, apres un
     * plantage, le partage restait arrete jusqu'a ce que quelqu'un touche « Demarrer le partage ».
     */
    fun ensureServiceStarted(context: Context, reason: String, delayMs: Long = 3_000L) {
        if (!isEnabled(context)) {
            return
        }
        val app = context.applicationContext
        if (autoStartScheduled) {
            return
        }
        autoStartScheduled = true
        Handler(Looper.getMainLooper()).postDelayed({
            autoStartScheduled = false
            try {
                // Service deja vivant (demarrage de l'appareil, partage lance a la main) : il gere
                // lui-meme sa capture ; on ne double jamais la demande de capture.
                if (MainService.running != null) {
                    return@postDelayed
                }
                val prefs = app.getSharedPreferences(KEY_SHARED_PREFERENCES, FlutterActivity.MODE_PRIVATE)
                val now = System.currentTimeMillis()
                val recent = (prefs.getString(KEY_AUTO_STARTS, "") ?: "")
                    .split(',')
                    .mapNotNull { it.toLongOrNull() }
                    .filter { now - it < AUTO_START_WINDOW_MS }
                if (recent.size >= AUTO_START_MAX) {
                    Log.w(logTag, "FS Support : relance du partage suspendue ($reason) : ${recent.size} relances en 15 min")
                    return@postDelayed
                }
                prefs.edit().putString(KEY_AUTO_STARTS, (recent + now).joinToString(",")).apply()
                Log.i(logTag, "FS Support : relance automatique du partage ($reason)")
                val intent = Intent(app, MainService::class.java).apply {
                    action = ACT_INIT_MEDIA_PROJECTION_AND_SERVICE
                    putExtra(EXT_INIT_FROM_BOOT, true)
                }
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    app.startForegroundService(intent)
                } else {
                    app.startService(intent)
                }
            } catch (e: Exception) {
                Log.w(logTag, "FS Support : relance automatique du partage impossible ($reason) : $e")
            }
        }, delayMs)
    }

    /** Referme la fenetre installation (apres avoir clique « Terminé »/« Ouvrir »). */
    fun clearInstallConsentWindow() {
        installConsentUntil = 0L
        installTightUntil = 0L
    }
}
