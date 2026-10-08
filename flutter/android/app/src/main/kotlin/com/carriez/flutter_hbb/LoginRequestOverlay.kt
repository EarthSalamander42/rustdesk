package com.carriez.flutter_hbb

import android.content.Context
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.StateListDrawable
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.widget.LinearLayout
import android.widget.TextView
import kotlin.math.min

/**
 * FS Support : carte « Demande de prise en main » posée par-dessus l'écran, quelle que soit
 * l'appli au premier plan. Vue Android native dans une fenêtre de superposition : elle ne dépend
 * pas du moteur Flutter et s'affiche même si l'activité est en arrière-plan ou détruite.
 *
 * - Une carte par demande, au centre de l'écran ; plusieurs demandes s'empilent, la plus récente
 *   au-dessus.
 * - La carte reçoit le toucher (et le pavé directionnel d'une télécommande) ; hors de la carte,
 *   l'écran reste utilisable (FLAG_NOT_TOUCH_MODAL).
 * - Les vues sont créées et retirées sur le thread principal uniquement.
 *
 * Autorisation requise : « Afficher par-dessus les autres applis » (SYSTEM_ALERT_WINDOW). Sur les
 * ROM qui masquent ce réglage (boîtiers Android TV, Amlogic « Droidlogic ») :
 *   adb shell appops set fr.fssolutions.support SYSTEM_ALERT_WINDOW allow
 */
class LoginRequestOverlay(
    private val context: Context,
    private val onAnswer: (clientId: Int, accept: Boolean) -> Unit,
) {
    private val logTag = "FsLoginOverlay"
    private val mainHandler = Handler(Looper.getMainLooper())
    private val windowManager = context.getSystemService(Context.WINDOW_SERVICE) as WindowManager

    // Cartes affichées, par identifiant de connexion (thread principal uniquement).
    private val cards = LinkedHashMap<Int, View>()
    private var released = false

    /** Affiche la carte d'une demande ; sans effet si elle est déjà affichée. */
    fun show(clientId: Int, name: String, peerId: String, detail: String) {
        runOnMain { addCard(clientId, name, peerId, detail) }
    }

    /** Retire la carte d'une demande traitée (carte, dialogue de l'appli, notification, départ du demandeur). */
    fun dismiss(clientId: Int) {
        runOnMain { removeCard(clientId) }
    }

    /** Retire toutes les cartes ; aucune ne sera plus affichée ensuite (MainService.onDestroy). */
    fun release() {
        runOnMain {
            released = true
            for (id in cards.keys.toList()) {
                removeCard(id)
            }
        }
    }

    private fun runOnMain(block: () -> Unit) {
        if (Looper.myLooper() == Looper.getMainLooper()) {
            block()
        } else {
            mainHandler.post { block() }
        }
    }

    private fun addCard(clientId: Int, name: String, peerId: String, detail: String) {
        if (released || cards.containsKey(clientId)) {
            return
        }
        val card = buildCard(clientId, name, peerId, detail)
        try {
            windowManager.addView(card, layoutParams())
            cards[clientId] = card
        } catch (e: RuntimeException) {
            // Autorisation retirée entre-temps, ou ROM qui refuse la superposition.
            Log.w(logTag, "FS Support : carte de la demande $clientId non affichée", e)
        }
    }

    private fun removeCard(clientId: Int) {
        val card = cards.remove(clientId) ?: return
        try {
            windowManager.removeView(card)
        } catch (e: IllegalArgumentException) {
            // Vue déjà détachée par le système.
            Log.w(logTag, "FS Support : carte de la demande $clientId déjà retirée", e)
        }
    }

    private fun answer(clientId: Int, accept: Boolean) {
        // Une seule réponse par carte, même sur un double appui.
        if (!cards.containsKey(clientId)) {
            return
        }
        removeCard(clientId)
        onAnswer(clientId, accept)
    }

    private fun layoutParams(): WindowManager.LayoutParams {
        @Suppress("DEPRECATION")
        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            WindowManager.LayoutParams.TYPE_PHONE
        }
        val screenWidth = getScreenSize(windowManager).first
        val width = min(screenWidth - dp(32), dp(600)).coerceAtLeast(dp(280))
        return WindowManager.LayoutParams(
            width,
            WindowManager.LayoutParams.WRAP_CONTENT,
            type,
            // Pas de FLAG_NOT_FOCUSABLE : une télécommande doit pouvoir choisir un bouton.
            // FLAG_NOT_TOUCH_MODAL : les touchers hors de la carte vont aux applis du dessous.
            WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.CENTER
            title = "FS Support - demande de prise en main"
        }
    }

    private fun buildCard(clientId: Int, name: String, peerId: String, detail: String): View {
        val id = formatPeerId(peerId)
        val card = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(28), dp(24), dp(28), dp(28))
            background = shape(CREME, ENCRE, dp(2))
        }
        card.addView(label("FS SUPPORT", 13f, SOURDINE, bold = true).apply { letterSpacing = 0.12f })
        card.addView(label("Demande de prise en main", 26f, ENCRE, bold = true), marginTop(dp(6)))
        card.addView(label(name.ifBlank { id }, 22f, ENCRE, bold = true), marginTop(dp(18)))
        if (name.isNotBlank() && id.isNotBlank()) {
            card.addView(label("ID $id", 18f, SOURDINE), marginTop(dp(2)))
        }
        card.addView(label(detail, 18f, ENCRE), marginTop(dp(10)))

        val refuse = button("Refuser", filled = false) { answer(clientId, false) }
        val accept = button("Accepter", filled = true) { answer(clientId, true) }
        val row = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            addView(refuse, LinearLayout.LayoutParams(0, dp(72), 1f))
            addView(accept, LinearLayout.LayoutParams(0, dp(72), 1f).apply { marginStart = dp(16) })
        }
        card.addView(row, marginTop(dp(28)))
        return card
    }

    private fun label(value: String, sizeSp: Float, color: Int, bold: Boolean = false): TextView {
        return TextView(context).apply {
            text = value
            setTextColor(color)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, sizeSp)
            if (bold) {
                typeface = Typeface.DEFAULT_BOLD
            }
        }
    }

    // Bouton plein (olive) ou contour (encre), grande cible tactile ; un TextView plutôt qu'un
    // Button pour ne rien hériter du thème système (majuscules, ombre, couleurs).
    private fun button(value: String, filled: Boolean, onClick: () -> Unit): TextView {
        return TextView(context).apply {
            text = value
            gravity = Gravity.CENTER
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 20f)
            typeface = Typeface.DEFAULT_BOLD
            setTextColor(if (filled) CREME else ENCRE)
            background = if (filled) {
                buttonBackground(OLIVE, OLIVE_APPUI, OLIVE)
            } else {
                buttonBackground(CREME, SELECTION, ENCRE)
            }
            isClickable = true
            isFocusable = true
            setOnClickListener { onClick() }
        }
    }

    private fun buttonBackground(fill: Int, pressed: Int, stroke: Int): StateListDrawable {
        return StateListDrawable().apply {
            addState(intArrayOf(android.R.attr.state_pressed), shape(pressed, stroke, dp(2)))
            addState(intArrayOf(android.R.attr.state_focused), shape(fill, ENCRE, dp(4)))
            addState(intArrayOf(), shape(fill, stroke, dp(2)))
        }
    }

    // Angles droits et filet, comme la charte FS.
    private fun shape(fill: Int, stroke: Int, strokeWidth: Int): GradientDrawable {
        return GradientDrawable().apply {
            setColor(fill)
            setStroke(strokeWidth, stroke)
        }
    }

    private fun marginTop(px: Int): LinearLayout.LayoutParams {
        return LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            LinearLayout.LayoutParams.WRAP_CONTENT
        ).apply { topMargin = px }
    }

    private fun dp(value: Int): Int {
        return TypedValue.applyDimension(
            TypedValue.COMPLEX_UNIT_DIP,
            value.toFloat(),
            context.resources.displayMetrics
        ).toInt()
    }

    // « 123456789 » devient « 123 456 789 », comme dans l'appli.
    private fun formatPeerId(peerId: String): String {
        return if (peerId.all { it.isDigit() }) peerId.chunked(3).joinToString(" ") else peerId
    }

    private companion object {
        // Charte FS : flutter/packages/fs_ui/lib/src/tokens.dart (thème clair). Jamais de bleu.
        val CREME = 0xFFF7F4EA.toInt()
        val ENCRE = 0xFF11140D.toInt()
        val SOURDINE = 0xFF515844.toInt()
        val OLIVE = 0xFF3A422D.toInt()
        val OLIVE_APPUI = 0xFF2A3020.toInt()
        val SELECTION = 0x173A422D
    }
}
