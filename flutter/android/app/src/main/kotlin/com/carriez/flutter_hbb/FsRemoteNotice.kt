package com.carriez.flutter_hbb

/**
 * FS Support (mode « Écran client ») : information discrète « Prise en main par FS Solutions ».
 *
 * Remplace, sur un écran géré à distance, la carte / le dialogue / la notification à boutons de
 * la demande de prise en main : personne n'est là pour répondre, et en mode « mot de passe
 * seulement » il ne restait qu'un bouton « Refuser ». Le contrôleur saisit le mot de passe
 * permanent de son côté ; l'écran affiche seulement qui prend la main, sans rien bloquer :
 *   - bandeau en haut de l'écran, ni focalisable ni touchable (les touchers passent dessous) ;
 *   - retiré seul après quelques secondes ;
 *   - une fois par connexion ;
 *   - sans autorisation de superposition : simple Toast.
 */

import android.content.Context
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.util.Log
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast

class FsRemoteNotice(private val context: Context) {
    private val logTag = "FsRemoteNotice"
    private val mainHandler = Handler(Looper.getMainLooper())
    private val windowManager by lazy { context.getSystemService(Context.WINDOW_SERVICE) as WindowManager }

    // Connexions déjà annoncées (thread principal uniquement), bornées.
    private val announced = LinkedHashSet<Int>()
    private var banner: View? = null
    private val hideBanner = Runnable { removeBanner() }

    /** Annonce la prise en main de la connexion [clientId] (une seule fois). Sûr depuis tout fil. */
    fun show(clientId: Int, name: String, peerId: String) {
        mainHandler.post {
            try {
                if (!announced.add(clientId)) return@post
                while (announced.size > 32) announced.remove(announced.first())
                display(name, peerId)
            } catch (e: Exception) {
                Log.w(logTag, "FS Support : information de prise en main non affichée", e)
            }
        }
    }

    /** Oublie une connexion terminée (une reconnexion sera de nouveau annoncée). */
    fun forget(clientId: Int) {
        mainHandler.post { announced.remove(clientId) }
    }

    fun release() {
        mainHandler.post {
            mainHandler.removeCallbacks(hideBanner)
            removeBanner()
        }
    }

    private fun display(name: String, peerId: String) {
        val id = if (peerId.all { it.isDigit() }) peerId.chunked(3).joinToString(" ") else peerId
        val who = when {
            name.isNotBlank() && id.isNotBlank() -> "$name · ID $id"
            name.isNotBlank() -> name
            else -> "ID $id"
        }
        val canOverlay = Build.VERSION.SDK_INT < Build.VERSION_CODES.M || Settings.canDrawOverlays(context)
        if (!canOverlay) {
            Toast.makeText(context, "Prise en main par FS Solutions\n$who", Toast.LENGTH_LONG).show()
            return
        }
        mainHandler.removeCallbacks(hideBanner)
        removeBanner()
        val view = buildBanner(who)
        @Suppress("DEPRECATION")
        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            WindowManager.LayoutParams.TYPE_PHONE
        }
        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            type,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL
            y = dp(24)
            title = "FS Support - prise en main"
        }
        try {
            windowManager.addView(view, params)
            banner = view
            mainHandler.postDelayed(hideBanner, SHOW_MS)
        } catch (e: RuntimeException) {
            Log.w(logTag, "FS Support : bandeau refusé, repli sur un Toast", e)
            Toast.makeText(context, "Prise en main par FS Solutions\n$who", Toast.LENGTH_LONG).show()
        }
    }

    private fun removeBanner() {
        val view = banner ?: return
        banner = null
        try {
            windowManager.removeView(view)
        } catch (e: IllegalArgumentException) {
            // Déjà retiré par le système.
        }
    }

    private fun buildBanner(who: String): View {
        val box = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(20), dp(12), dp(20), dp(12))
            background = GradientDrawable().apply {
                setColor(ENCRE_TRANSLUCIDE)
                setStroke(dp(1), OLIVE)
            }
        }
        box.addView(TextView(context).apply {
            text = "Prise en main par FS Solutions"
            setTextColor(CREME)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
            typeface = Typeface.DEFAULT_BOLD
        })
        box.addView(TextView(context).apply {
            text = who
            setTextColor(CREME_SOURDINE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
        })
        return box
    }

    private fun dp(value: Int): Int =
        TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, value.toFloat(), context.resources.displayMetrics).toInt()

    private companion object {
        const val SHOW_MS = 6_000L
        // Charte FS (flutter/packages/fs_ui/lib/src/tokens.dart). Jamais de bleu.
        val ENCRE_TRANSLUCIDE = 0xE611140D.toInt()
        val OLIVE = 0xFF3A422D.toInt()
        val CREME = 0xFFF7F4EA.toInt()
        val CREME_SOURDINE = 0xCCF7F4EA.toInt()
    }
}
