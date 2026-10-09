package com.carriez.flutter_hbb

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import androidx.core.app.NotificationManagerCompat

/**
 * FS Support : boutons Accepter / Refuser de la notification « Demande de prise en main »
 * (MainService.loginRequestNotification). Récepteur non exporté : seuls les PendingIntent de
 * l'appli l'atteignent. La réponse suit le même chemin que la carte par-dessus l'écran.
 */
class LoginRequestReceiver : BroadcastReceiver() {
    private val logTag = "FsLoginReceiver"

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ACT_LOGIN_REQ_NOTIFY || !intent.hasExtra(EXT_LOGIN_REQ_CLIENT_ID)) {
            Log.w(logTag, "FS Support : intention inattendue : ${intent.action}")
            return
        }
        val clientId = intent.getIntExtra(EXT_LOGIN_REQ_CLIENT_ID, 0)
        val accept = intent.getBooleanExtra(EXT_LOGIN_REQ_NOTIFY, false)
        val service = MainService.running
        if (service == null) {
            // Service arrêté : plus aucune demande en attente, on retire la notification restée.
            Log.w(logTag, "FS Support : service arrêté, demande $clientId sans suite")
            NotificationManagerCompat.from(context).cancel(clientId + NOTIFY_ID_OFFSET)
            return
        }
        service.answerLoginRequest(clientId, accept)
    }
}
