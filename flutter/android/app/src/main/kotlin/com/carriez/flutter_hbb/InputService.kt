package com.carriez.flutter_hbb

/**
 * Handle remote input and dispatch android gesture
 *
 * Inspired by [droidVNC-NG] https://github.com/bk138/droidVNC-NG
 */

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.content.Intent
import android.graphics.Path
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.util.Log
import android.widget.EditText
import android.view.accessibility.AccessibilityEvent
import android.view.ViewGroup.LayoutParams
import android.view.accessibility.AccessibilityNodeInfo
import android.view.accessibility.AccessibilityWindowInfo
import android.view.KeyEvent as KeyEventAndroid
import android.view.ViewConfiguration
import android.graphics.Rect
import android.media.AudioManager
import android.accessibilityservice.AccessibilityServiceInfo
import android.accessibilityservice.AccessibilityServiceInfo.FLAG_INPUT_METHOD_EDITOR
import android.accessibilityservice.AccessibilityServiceInfo.FLAG_RETRIEVE_INTERACTIVE_WINDOWS
import android.view.inputmethod.EditorInfo
import androidx.annotation.RequiresApi
import java.util.*
import java.util.concurrent.atomic.AtomicInteger
import java.lang.Character
import kotlin.math.abs
import kotlin.math.max
import hbb.MessageOuterClass.KeyEvent
import hbb.MessageOuterClass.KeyboardMode
import hbb.KeyEventConverter
import ffi.FFI

// const val BUTTON_UP = 2
// const val BUTTON_BACK = 0x08

const val LEFT_DOWN = 9
const val LEFT_MOVE = 8
const val LEFT_UP = 10
const val RIGHT_UP = 18
// (BUTTON_BACK << 3) | BUTTON_UP
const val BACK_UP = 66
const val WHEEL_BUTTON_DOWN = 33
const val WHEEL_BUTTON_UP = 34
const val WHEEL_DOWN = 523331
const val WHEEL_UP = 963

const val TOUCH_SCALE_START = 1
const val TOUCH_SCALE = 2
const val TOUCH_SCALE_END = 3
const val TOUCH_PAN_START = 4
const val TOUCH_PAN_UPDATE = 5
const val TOUCH_PAN_END = 6

const val WHEEL_STEP = 120
const val WHEEL_DURATION = 50L
const val LONG_TAP_DELAY = 200L

class InputService : AccessibilityService() {

    companion object {
        var ctx: InputService? = null
        val isOpen: Boolean
            get() = ctx != null

        // FS Support : refus consécutifs de gestes avant de passer au mode de secours
        private const val FS_GESTURE_REFUSAL_THRESHOLD = 2
        // FS Support : écart minimal entre deux défilements de secours à la molette (une action = une page)
        private const val FS_WHEEL_FALLBACK_INTERVAL = 350L
        // FS Support : profondeur maximale explorée dans l'arbre des nœuds
        private const val FS_MAX_NODE_DEPTH = 64

        // FS Support (mode Ecran client) : écart minimal entre deux clics automatiques de
        // validation (fenêtre de consentement / installateur), pour ne pas cliquer en rafale.
        private const val FS_AUTO_CLICK_THROTTLE = 500L
        // FS Support : le texte de la fenêtre système DOIT mentionner l'appli avant tout clic.
        private const val FS_APP_LABEL = "fs support"
        // FS Support : paquets hôtes de la fenêtre de consentement MediaProjection.
        private val FS_MEDIA_PROJECTION_PACKAGES = setOf(
            "com.android.systemui",
            "android",
        )
        // FS Support : installateurs de paquets connus (validation de la propre mise à jour).
        private val FS_PACKAGE_INSTALLER_PACKAGES = setOf(
            "com.android.packageinstaller",
            "com.google.android.packageinstaller",
            "com.android.packageinstaller.permission",
        )
        // FS Support : tous les libellés ci-dessous sont en forme REPLIEE (minuscules, sans accents),
        // comparés à fsFold(texte du nœud). Le bouton doit être cliquable (ou avoir un ancêtre
        // cliquable) ; les libellés négatifs ci-dessous excluent explicitement « Annuler » / « Don't
        // allow » (qui contient « allow »), etc.
        // Identifiants connus du bouton positif (Android ≤ 13 : button1 ; SystemUI récent : autre id).
        private val FS_BUTTON_IDS = listOf(
            "android:id/button1",
            "com.android.systemui:id/button_start",
        )
        // Bouton positif de consentement de capture.
        private val FS_CAPTURE_POS_TEXTS = listOf(
            "commencer", "demarrer", "start now", "start", "autoriser", "allow",
        )
        // Sélecteur Android 14+ « Tout l'écran » (choisi avant le bouton positif).
        private val FS_CAPTURE_ENTIRE_TEXTS = listOf(
            "tout l'ecran", "l'integralite de l'ecran", "entire screen", "whole screen", "full screen",
        )
        // Bouton d'installation / de mise à jour de l'installateur.
        private val FS_INSTALL_POS_TEXTS = listOf(
            "mettre a jour", "installer", "update", "install",
        )
        // Bouton de fin de l'installateur. « Terminé » d'abord (ne couvre pas l'écran du client),
        // « Ouvrir » en repli ; le redémarrage réel passe par ACTION_MY_PACKAGE_REPLACED.
        private val FS_INSTALL_DONE_TEXTS = listOf("termine", "fermer", "ok", "done", "close")
        private val FS_INSTALL_OPEN_TEXTS = listOf("ouvrir", "open")
        // Libellés négatifs : ne JAMAIS cliquer un bouton qui les porte (sécurité).
        private val FS_NEG_TEXTS = listOf(
            "annuler", "cancel", "refuser", "don't allow", "dont allow", "ne pas autoriser",
            "deny", "plus tard", "not now", "later",
        )
    }

    private fun notifyInputState() {
        val inputState = isOpen.toString()
        Handler(Looper.getMainLooper()).post {
            MainActivity.flutterMethodChannel?.invokeMethod(
                "on_state_changed",
                mapOf("name" to "input", "value" to inputState)
            )
        }
    }

    private val logTag = "input service"
    private var leftIsDown = false
    private var touchPath = Path()
    private var stroke: GestureDescription.StrokeDescription? = null
    private var lastTouchGestureStartTime = 0L
    private var mouseX = 0
    private var mouseY = 0
    private var timer = Timer()
    private var recentActionTask: TimerTask? = null
    // 100(tap timeout) + 400(long press timeout)
    private val longPressDuration = ViewConfiguration.getTapTimeout().toLong() + ViewConfiguration.getLongPressTimeout().toLong()

    // FS Support : chaque cran de molette garde son action de secours
    private val wheelActionsQueue = LinkedList<Pair<GestureDescription, () -> Unit>>()
    private var isWheelActionsPolling = false
    private var isWaitingLongPress = false

    private var fakeEditTextForTextStateCalculation: EditText? = null

    private var lastX = 0
    private var lastY = 0

    // FS Support : mode de secours pour les ROM qui refusent dispatchGesture (boîtiers TV, Amlogic...).
    // Refus consécutifs, remis à zéro dès qu'un geste aboutit.
    private val fsGestureRefusals = AtomicInteger(0)
    // FS Support : numéro du dernier geste envoyé, et du dernier geste neuf (hors continuation)
    private val fsGestureSeq = AtomicInteger(0)
    private val fsLastNewGestureSeq = AtomicInteger(0)
    // FS Support : début de l'appui en cours, pour le rejouer en clic, appui long ou défilement
    private var fsStartX = 0
    private var fsStartY = 0
    private var fsStartTime = 0L
    private var fsMoved = false
    // FS Support : dernier défilement de secours à la molette (anti-rafale)
    private var fsLastWheelFallbackTime = 0L
    private var fsLastWheelForward = false
    // FS Support : fil dédié aux actions de secours (une requête de nœuds peut bloquer plusieurs secondes)
    private var fsFallbackThread: HandlerThread? = null
    @Volatile private var fsFallbackHandler: Handler? = null
    // FS Support (mode Ecran client) : anti-rafale des clics automatiques et étape d'installation en cours.
    @Volatile private var fsLastAutoClick = 0L
    @Volatile private var fsInstallClicked = false
    // FS Support : le poller de consentement tourne-t-il déjà ? (évite de l'empiler)
    @Volatile private var fsConsentPollerArmed = false
    // FS Support : dernière journalisation de l'énumération des fenêtres (diagnostic, limité en débit)
    @Volatile private var fsLastWindowsLog = 0L
    // FS Support : seuil de glissement en pixels d'écran, 8 dp comme ViewConfiguration
    private val fsTouchSlop: Int by lazy { max(8, (8 * resources.displayMetrics.density).toInt()) }

    private val volumeController: VolumeController by lazy { VolumeController(applicationContext.getSystemService(AUDIO_SERVICE) as AudioManager) }

    @RequiresApi(Build.VERSION_CODES.N)
    fun onMouseInput(mask: Int, _x: Int, _y: Int) {
        val x = max(0, _x)
        val y = max(0, _y)

        if (mask == 0 || mask == LEFT_MOVE) {
            val oldX = mouseX
            val oldY = mouseY
            mouseX = x * SCREEN_INFO.scale
            mouseY = y * SCREEN_INFO.scale
            if (isWaitingLongPress) {
                val delta = abs(oldX - mouseX) + abs(oldY - mouseY)
                Log.d(logTag,"delta:$delta")
                if (delta > 8) {
                    isWaitingLongPress = false
                }
            }
            // FS Support : au-delà du seuil, l'appui devient un glissement (rejoué en défilement, jamais en clic)
            if (leftIsDown && !fsMoved && abs(mouseX - fsStartX) + abs(mouseY - fsStartY) > fsTouchSlop) {
                fsMoved = true
            }
        }

        // left button down, was up
        if (mask == LEFT_DOWN) {
            isWaitingLongPress = true
            timer.schedule(object : TimerTask() {
                override fun run() {
                    if (isWaitingLongPress) {
                        isWaitingLongPress = false
                        continueGesture(mouseX, mouseY)
                    }
                }
            }, longPressDuration)

            leftIsDown = true
            // FS Support : début de l'appui, à rejouer si l'appareil refuse les gestes
            fsStartX = mouseX
            fsStartY = mouseY
            fsStartTime = System.currentTimeMillis()
            fsMoved = false
            startGesture(mouseX, mouseY)
            return
        }

        // left down, was down
        if (leftIsDown) {
            continueGesture(mouseX, mouseY)
        }

        // left up, was down
        if (mask == LEFT_UP) {
            if (leftIsDown) {
                leftIsDown = false
                isWaitingLongPress = false
                endGesture(mouseX, mouseY, fsPointerUpFallback(mouseX, mouseY))
                return
            }
        }

        if (mask == RIGHT_UP) {
            longPress(mouseX, mouseY)
            return
        }

        if (mask == BACK_UP) {
            performGlobalAction(GLOBAL_ACTION_BACK)
            return
        }

        // long WHEEL_BUTTON_DOWN -> GLOBAL_ACTION_RECENTS
        if (mask == WHEEL_BUTTON_DOWN) {
            timer.purge()
            recentActionTask = object : TimerTask() {
                override fun run() {
                    performGlobalAction(GLOBAL_ACTION_RECENTS)
                    recentActionTask = null
                }
            }
            timer.schedule(recentActionTask, LONG_TAP_DELAY)
        }

        // wheel button up
        if (mask == WHEEL_BUTTON_UP) {
            if (recentActionTask != null) {
                recentActionTask!!.cancel()
                performGlobalAction(GLOBAL_ACTION_HOME)
            }
            return
        }

        if (mask == WHEEL_DOWN) {
            if (mouseY < WHEEL_STEP) {
                return
            }
            val path = Path()
            path.moveTo(mouseX.toFloat(), mouseY.toFloat())
            path.lineTo(mouseX.toFloat(), (mouseY - WHEEL_STEP).toFloat())
            val stroke = GestureDescription.StrokeDescription(
                path,
                0,
                WHEEL_DURATION
            )
            val builder = GestureDescription.Builder()
            builder.addStroke(stroke)
            // FS Support : même déplacement du doigt (vers le haut) pour le défilement de secours
            val wheelX = mouseX
            val wheelY = mouseY
            val fallback: () -> Unit = { fsFallbackWheel(wheelX, wheelY, -WHEEL_STEP) }
            wheelActionsQueue.offer(Pair(builder.build(), fallback))
            consumeWheelActions()

        }

        if (mask == WHEEL_UP) {
            if (mouseY < WHEEL_STEP) {
                return
            }
            val path = Path()
            path.moveTo(mouseX.toFloat(), mouseY.toFloat())
            path.lineTo(mouseX.toFloat(), (mouseY + WHEEL_STEP).toFloat())
            val stroke = GestureDescription.StrokeDescription(
                path,
                0,
                WHEEL_DURATION
            )
            val builder = GestureDescription.Builder()
            builder.addStroke(stroke)
            // FS Support : même déplacement du doigt (vers le bas) pour le défilement de secours
            val wheelX = mouseX
            val wheelY = mouseY
            val fallback: () -> Unit = { fsFallbackWheel(wheelX, wheelY, WHEEL_STEP) }
            wheelActionsQueue.offer(Pair(builder.build(), fallback))
            consumeWheelActions()
        }
    }

    @RequiresApi(Build.VERSION_CODES.N)
    fun onTouchInput(mask: Int, _x: Int, _y: Int) {
        when (mask) {
            TOUCH_PAN_UPDATE -> {
                mouseX -= _x * SCREEN_INFO.scale
                mouseY -= _y * SCREEN_INFO.scale
                mouseX = max(0, mouseX);
                mouseY = max(0, mouseY);
                continueGesture(mouseX, mouseY)
            }
            TOUCH_PAN_START -> {
                mouseX = max(0, _x) * SCREEN_INFO.scale
                mouseY = max(0, _y) * SCREEN_INFO.scale
                // FS Support : point de départ du glissement, pour le défilement de secours
                fsStartX = mouseX
                fsStartY = mouseY
                startGesture(mouseX, mouseY)
            }
            TOUCH_PAN_END -> {
                // FS Support : un glissement se rejoue en défilement, jamais en clic
                val startX = fsStartX
                val startY = fsStartY
                val endX = mouseX
                val endY = mouseY
                endGesture(mouseX, mouseY) { fsFallbackSwipe(startX, startY, endX, endY) }
                mouseX = max(0, _x) * SCREEN_INFO.scale
                mouseY = max(0, _y) * SCREEN_INFO.scale
            }
            else -> {}
        }
    }

    @RequiresApi(Build.VERSION_CODES.N)
    private fun consumeWheelActions() {
        if (isWheelActionsPolling) {
            return
        } else {
            isWheelActionsPolling = true
        }
        wheelActionsQueue.poll()?.let { (gesture, fallback) ->
            fsDispatchGesture(gesture, true, fallback)
            timer.purge()
            timer.schedule(object : TimerTask() {
                override fun run() {
                    isWheelActionsPolling = false
                    consumeWheelActions()
                }
            }, WHEEL_DURATION + 10)
        } ?: let {
            isWheelActionsPolling = false
            return
        }
    }

    @RequiresApi(Build.VERSION_CODES.N)
    private fun performClick(x: Int, y: Int, duration: Long, fallback: (() -> Unit)? = null) {
        val path = Path()
        path.moveTo(x.toFloat(), y.toFloat())
        try {
            val longPressStroke = GestureDescription.StrokeDescription(path, 0, duration)
            val builder = GestureDescription.Builder()
            builder.addStroke(longPressStroke)
            Log.d(logTag, "performClick x:$x y:$y time:$duration")
            fsDispatchGesture(builder.build(), true, fallback)
        } catch (e: Exception) {
            Log.e(logTag, "performClick, error:$e")
        }
    }

    @RequiresApi(Build.VERSION_CODES.N)
    private fun longPress(x: Int, y: Int) {
        // FS Support : en secours, ACTION_LONG_CLICK sur le nœud sous le point
        performClick(x, y, longPressDuration) { fsFallbackClick(x, y, true) }
    }

    private fun startGesture(x: Int, y: Int) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            touchPath.reset()
        } else {
            touchPath = Path()
        }
        touchPath.moveTo(x.toFloat(), y.toFloat())
        lastTouchGestureStartTime = System.currentTimeMillis()
        lastX = x
        lastY = y
    }

    @RequiresApi(Build.VERSION_CODES.N)
    private fun doDispatchGesture(x: Int, y: Int, willContinue: Boolean, fallback: (() -> Unit)? = null) {
        touchPath.lineTo(x.toFloat(), y.toFloat())
        var duration = System.currentTimeMillis() - lastTouchGestureStartTime
        if (duration <= 0) {
            duration = 1
        }
        // FS Support : un geste neuf (pas une continuation) interrompt les gestes encore en cours
        val isNew = stroke == null || Build.VERSION.SDK_INT < Build.VERSION_CODES.O
        try {
            if (stroke == null) {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    stroke = GestureDescription.StrokeDescription(
                        touchPath,
                        0,
                        duration,
                        willContinue
                    )
                } else {
                    stroke = GestureDescription.StrokeDescription(
                        touchPath,
                        0,
                        duration
                    )
                }
            } else {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    stroke = stroke?.continueStroke(touchPath, 0, duration, willContinue)
                } else {
                    stroke = null
                    stroke = GestureDescription.StrokeDescription(
                        touchPath,
                        0,
                        duration
                    )
                }
            }
            stroke?.let {
                val builder = GestureDescription.Builder()
                builder.addStroke(it)
                Log.d(logTag, "doDispatchGesture x:$x y:$y time:$duration")
                fsDispatchGesture(builder.build(), isNew, fallback)
            }
        } catch (e: Exception) {
            Log.e(logTag, "doDispatchGesture, willContinue:$willContinue, error:$e")
        }
    }

    @RequiresApi(Build.VERSION_CODES.N)
    private fun continueGesture(x: Int, y: Int) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            doDispatchGesture(x, y, true)
            touchPath.reset()
            touchPath.moveTo(x.toFloat(), y.toFloat())
            lastTouchGestureStartTime = System.currentTimeMillis()
            lastX = x
            lastY = y
        } else {
            touchPath.lineTo(x.toFloat(), y.toFloat())
        }
    }

    @RequiresApi(Build.VERSION_CODES.N)
    private fun endGestureBelowO(x: Int, y: Int, fallback: (() -> Unit)?) {
        try {
            touchPath.lineTo(x.toFloat(), y.toFloat())
            var duration = System.currentTimeMillis() - lastTouchGestureStartTime
            if (duration <= 0) {
                duration = 1
            }
            val stroke = GestureDescription.StrokeDescription(
                touchPath,
                0,
                duration
            )
            val builder = GestureDescription.Builder()
            builder.addStroke(stroke)
            Log.d(logTag, "end gesture x:$x y:$y time:$duration")
            fsDispatchGesture(builder.build(), true, fallback)
        } catch (e: Exception) {
            Log.e(logTag, "endGesture error:$e")
        }
    }

    @RequiresApi(Build.VERSION_CODES.N)
    private fun endGesture(x: Int, y: Int, fallback: (() -> Unit)? = null) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            doDispatchGesture(x, y, false, fallback)
            touchPath.reset()
            stroke = null
        } else {
            endGestureBelowO(x, y, fallback)
        }
    }

    // FS Support : envoie le geste en écoutant son résultat. Un refus (retour false ou onCancelled)
    // est compté ; à partir du seuil, l'action est rejouée par les nœuds d'accessibilité.
    // Un geste qui aboutit remet le compteur à zéro : rien ne change là où les gestes marchent.
    // FS Support : option « Clics compatibles ecrans interactifs ». Lue au vol via le pont Rust
    // (meme mecanisme que MainActivity.FFI.getLocalOption). Toute erreur = desactive.
    private fun fsForceAccessibilityClicks(): Boolean {
        return try {
            FFI.getLocalOption(KEY_FS_FORCE_ACCESSIBILITY_CLICKS) == "Y"
        } catch (e: Exception) {
            Log.w(logTag, "FS Support : lecture de l'option clics forces impossible : $e")
            false
        }
    }

    @RequiresApi(Build.VERSION_CODES.N)
    private fun fsDispatchGesture(gesture: GestureDescription, isNew: Boolean, fallback: (() -> Unit)?) {
        // FS Support : mode force -> on NE tente PAS dispatchGesture, tout passe par les noeuds.
        // Les gestes intermediaires (continuation, fallback null) sont simplement ignores ;
        // seul l'evenement terminal porte un fallback et rejoue l'action complete.
        if (fsForceAccessibilityClicks()) {
            if (fallback != null) {
                Log.i(logTag, "FS Support : mode clics compatibles ecrans interactifs — action rejouee par noeuds d'accessibilite")
                fsRunFallback(fallback)
            }
            return
        }
        val seq = fsGestureSeq.incrementAndGet()
        if (isNew) {
            fsLastNewGestureSeq.accumulateAndGet(seq) { a, b -> max(a, b) }
        }
        val callback = object : AccessibilityService.GestureResultCallback() {
            override fun onCompleted(gestureDescription: GestureDescription?) {
                if (fsGestureRefusals.getAndSet(0) >= FS_GESTURE_REFUSAL_THRESHOLD) {
                    Log.i(logTag, "FS Support : gestes de nouveau acceptés, mode de secours suspendu")
                }
            }

            override fun onCancelled(gestureDescription: GestureDescription?) {
                fsOnGestureRefused(seq, fallback)
            }
        }
        val accepted = try {
            dispatchGesture(gesture, callback, null)
        } catch (e: Exception) {
            Log.w(logTag, "FS Support : dispatchGesture en échec : $e")
            false
        }
        if (!accepted) {
            // FS Support : le rappel ne viendra pas, on compte le refus ici
            fsOnGestureRefused(seq, fallback)
        }
    }

    // FS Support : compte un refus de geste et, à partir du seuil, lance l'action de secours
    private fun fsOnGestureRefused(seq: Int, fallback: (() -> Unit)?) {
        // FS Support : un geste interrompu par un geste plus récent n'est pas un refus de l'appareil
        if (seq < fsLastNewGestureSeq.get()) {
            return
        }
        val refusals = fsGestureRefusals.incrementAndGet()
        if (refusals == FS_GESTURE_REFUSAL_THRESHOLD) {
            Log.w(logTag, "FS Support : l'appareil refuse les gestes, mode de secours par nœuds d'accessibilité")
        }
        if (refusals >= FS_GESTURE_REFUSAL_THRESHOLD && fallback != null) {
            fsRunFallback(fallback)
        }
    }

    // FS Support : exécute l'action de secours sur son fil, sans jamais faire planter le service
    private fun fsRunFallback(fallback: () -> Unit) {
        val task = Runnable {
            try {
                fallback()
            } catch (e: Exception) {
                Log.w(logTag, "FS Support : action de secours en échec : $e")
            }
        }
        val handler = fsFallbackHandler
        if (handler == null || !handler.post(task)) {
            task.run()
        }
    }

    // FS Support : action à rejouer au relâchement du bouton gauche, toujours au point d'appui :
    // glissement -> défilement, appui tenu -> appui long, sinon clic
    @RequiresApi(Build.VERSION_CODES.N)
    private fun fsPointerUpFallback(upX: Int, upY: Int): () -> Unit {
        val startX = fsStartX
        val startY = fsStartY
        val moved = fsMoved
        val held = System.currentTimeMillis() - fsStartTime >= longPressDuration
        return {
            if (moved) {
                fsFallbackSwipe(startX, startY, upX, upY)
            } else {
                fsFallbackClick(startX, startY, held)
            }
        }
    }

    // FS Support : clic (ou appui long) de secours sur le nœud cliquable le plus profond sous le point,
    // comme un vrai toucher ; à défaut, ACTION_FOCUS puis l'action sur le nœud visible le plus profond
    @RequiresApi(Build.VERSION_CODES.N)
    private fun fsFallbackClick(x: Int, y: Int, longClick: Boolean) {
        val action = if (longClick) AccessibilityNodeInfo.ACTION_LONG_CLICK else AccessibilityNodeInfo.ACTION_CLICK
        val search = FsNodeSearch(x, y)
        try {
            val target = fsFindNodeAt(search) { if (longClick) it.isLongClickable else it.isClickable }
            var done = false
            if (target != null) {
                done = target.performAction(action)
            } else {
                search.deepest?.let { node ->
                    node.performAction(AccessibilityNodeInfo.ACTION_FOCUS)
                    done = node.performAction(action)
                }
            }
            Log.d(logTag, "FS Support : secours ${if (longClick) "appui long" else "clic"} x:$x y:$y cible:${target != null} résultat:$done")
        } catch (e: Exception) {
            Log.w(logTag, "FS Support : secours clic impossible x:$x y:$y : $e")
        } finally {
            search.recycle()
        }
    }

    // FS Support : un glissement se rejoue en défilement, jamais en clic ; trop court, il est ignoré
    @RequiresApi(Build.VERSION_CODES.N)
    private fun fsFallbackSwipe(startX: Int, startY: Int, endX: Int, endY: Int) {
        val dx = endX - startX
        val dy = endY - startY
        if (abs(dx) + abs(dy) <= fsTouchSlop) {
            Log.d(logTag, "FS Support : glissement trop court, ignoré en secours")
            return
        }
        fsFallbackScroll(startX, startY, dx, dy)
    }

    // FS Support : molette en secours ; une action de défilement avance d'une page,
    // donc une seule par rafale de crans dans le même sens
    @RequiresApi(Build.VERSION_CODES.N)
    private fun fsFallbackWheel(x: Int, y: Int, dy: Int) {
        val forward = dy < 0
        val now = System.currentTimeMillis()
        if (forward == fsLastWheelForward && now - fsLastWheelFallbackTime < FS_WHEEL_FALLBACK_INTERVAL) {
            return
        }
        fsLastWheelFallbackTime = now
        fsLastWheelForward = forward
        fsFallbackScroll(x, y, 0, dy)
    }

    // FS Support : défilement de secours selon le déplacement (dx, dy) du doigt parti de (x, y).
    // Doigt vers le haut = contenu vers le bas (en avant). Action directionnelle (API 23+) sur le
    // premier ancêtre défilant qui la propose, sinon ACTION_SCROLL_FORWARD / BACKWARD.
    @RequiresApi(Build.VERSION_CODES.N)
    private fun fsFallbackScroll(x: Int, y: Int, dx: Int, dy: Int) {
        val vertical = abs(dy) >= abs(dx)
        val forward = if (vertical) dy < 0 else dx < 0
        val directional = when {
            vertical && forward -> AccessibilityNodeInfo.AccessibilityAction.ACTION_SCROLL_DOWN
            vertical -> AccessibilityNodeInfo.AccessibilityAction.ACTION_SCROLL_UP
            forward -> AccessibilityNodeInfo.AccessibilityAction.ACTION_SCROLL_RIGHT
            else -> AccessibilityNodeInfo.AccessibilityAction.ACTION_SCROLL_LEFT
        }.id
        val generic = if (forward) AccessibilityNodeInfo.ACTION_SCROLL_FORWARD else AccessibilityNodeInfo.ACTION_SCROLL_BACKWARD
        val search = FsNodeSearch(x, y)
        try {
            var action = directional
            var target = fsFindNodeAt(search) { it.isScrollable && fsHasAction(it, directional) }
            if (target == null) {
                action = generic
                target = fsFindNodeAt(search) { it.isScrollable }
            }
            val done = target?.performAction(action) ?: false
            Log.d(logTag, "FS Support : secours défilement x:$x y:$y dx:$dx dy:$dy cible:${target != null} résultat:$done")
        } catch (e: Exception) {
            Log.w(logTag, "FS Support : secours défilement impossible x:$x y:$y : $e")
        } finally {
            search.recycle()
        }
    }

    private fun fsHasAction(node: AccessibilityNodeInfo, actionId: Int): Boolean =
        node.actionList.any { it.id == actionId }

    // FS Support : nœud le plus profond sous le point qui satisfait accept, dans la fenêtre du dessus
    // (un vrai toucher ne va pas plus bas), ou à défaut dans la fenêtre active
    private fun fsFindNodeAt(search: FsNodeSearch, accept: (AccessibilityNodeInfo) -> Boolean): AccessibilityNodeInfo? {
        var windowList: List<AccessibilityWindowInfo> = emptyList()
        try {
            windowList = windows.sortedByDescending { it.layer }
            val windowBounds = Rect()
            for (window in windowList) {
                window.getBoundsInScreen(windowBounds)
                if (!windowBounds.contains(search.x, search.y)) {
                    continue
                }
                val root = window.root ?: continue
                search.obtained.add(root)
                if (fsIsUnderPoint(root, search)) {
                    return fsFindIn(root, search, accept, 0)
                }
            }
        } catch (e: Exception) {
            Log.w(logTag, "FS Support : lecture des fenêtres impossible : $e")
        } finally {
            fsRecycleWindows(windowList)
        }
        val root = rootInActiveWindow ?: return null
        search.obtained.add(root)
        return if (fsIsUnderPoint(root, search)) fsFindIn(root, search, accept, 0) else null
    }

    // FS Support : parcourt les enfants sous le point, du dessus (dernier) vers le dessous, et renvoie
    // le plus profond accepté ; retient au passage le nœud visible le plus profond
    private fun fsFindIn(
        node: AccessibilityNodeInfo,
        search: FsNodeSearch,
        accept: (AccessibilityNodeInfo) -> Boolean,
        depth: Int
    ): AccessibilityNodeInfo? {
        var childUnderPoint = false
        if (depth < FS_MAX_NODE_DEPTH) {
            for (i in node.childCount - 1 downTo 0) {
                val child = node.getChild(i) ?: continue
                search.obtained.add(child)
                if (!fsIsUnderPoint(child, search)) {
                    continue
                }
                childUnderPoint = true
                val found = fsFindIn(child, search, accept, depth + 1)
                if (found != null) {
                    return found
                }
            }
        }
        if (!childUnderPoint && search.deepest == null) {
            search.deepest = node
        }
        return if (accept(node)) node else null
    }

    private fun fsIsUnderPoint(node: AccessibilityNodeInfo, search: FsNodeSearch): Boolean {
        if (!node.isVisibleToUser) {
            return false
        }
        node.getBoundsInScreen(search.bounds)
        return search.bounds.contains(search.x, search.y)
    }

    @Suppress("DEPRECATION")
    private fun fsRecycleWindows(windowList: List<AccessibilityWindowInfo>) {
        if (Build.VERSION.SDK_INT >= 33) {
            return
        }
        for (window in windowList) {
            try {
                window.recycle()
            } catch (e: Exception) {
                Log.w(logTag, "FS Support : recyclage de fenêtre impossible : $e")
            }
        }
    }

    // FS Support : recherche d'un nœud sous un point ; tous les nœuds obtenus sont recyclés à la fin
    private class FsNodeSearch(val x: Int, val y: Int) {
        val obtained = ArrayList<AccessibilityNodeInfo>()
        val bounds = Rect()
        // FS Support : nœud visible le plus profond sous le point (branche du dessus)
        var deepest: AccessibilityNodeInfo? = null

        @Suppress("DEPRECATION")
        fun recycle() {
            deepest = null
            if (Build.VERSION.SDK_INT < 33) {
                for (node in obtained) {
                    try {
                        node.recycle()
                    } catch (e: Exception) {
                        Log.w("input service", "FS Support : recyclage de nœud impossible : $e")
                    }
                }
            }
            obtained.clear()
        }
    }

    @RequiresApi(Build.VERSION_CODES.N)
    fun onKeyEvent(data: ByteArray) {
        val keyEvent = KeyEvent.parseFrom(data)
        val keyboardMode = keyEvent.getMode()

        var textToCommit: String? = null

        // [down] indicates the key's state(down or up).
        // [press] indicates a click event(down and up).
        // https://github.com/rustdesk/rustdesk/blob/3a7594755341f023f56fa4b6a43b60d6b47df88d/flutter/lib/models/input_model.dart#L688
        if (keyEvent.hasSeq()) {
            textToCommit = keyEvent.getSeq()
        } else if (keyboardMode == KeyboardMode.Legacy) {
            if (keyEvent.hasChr() && (keyEvent.getDown() || keyEvent.getPress())) {
                val chr = keyEvent.getChr()
                if (chr != null) {
                    textToCommit = String(Character.toChars(chr))
                }
            }
        } else if (keyboardMode == KeyboardMode.Translate) {
        } else {
        }

        Log.d(logTag, "onKeyEvent $keyEvent textToCommit:$textToCommit")

        var ke: KeyEventAndroid? = null
        if (Build.VERSION.SDK_INT < 33 || textToCommit == null) {
            ke = KeyEventConverter.toAndroidKeyEvent(keyEvent)
        }
        ke?.let { event ->
            if (tryHandleVolumeKeyEvent(event)) {
                return
            } else if (tryHandlePowerKeyEvent(event)) {
                return
            }
        }

        if (Build.VERSION.SDK_INT >= 33) {
            getInputMethod()?.let { inputMethod ->
                inputMethod.getCurrentInputConnection()?.let { inputConnection ->
                    if (textToCommit != null) {
                        textToCommit?.let { text ->
                            inputConnection.commitText(text, 1, null)
                        }
                    } else {
                        ke?.let { event ->
                            inputConnection.sendKeyEvent(event)
                            if (keyEvent.getPress()) {
                                val actionUpEvent = KeyEventAndroid(KeyEventAndroid.ACTION_UP, event.keyCode)
                                inputConnection.sendKeyEvent(actionUpEvent)
                            }
                        }
                    }
                }
            }
        } else {
            val handler = Handler(Looper.getMainLooper())
            handler.post {
                ke?.let { event ->
                    val possibleNodes = possibleAccessibiltyNodes()
                    Log.d(logTag, "possibleNodes:$possibleNodes")
                    for (item in possibleNodes) {
                        val success = trySendKeyEvent(event, item, textToCommit)
                        if (success) {
                            if (keyEvent.getPress()) {
                                val actionUpEvent = KeyEventAndroid(KeyEventAndroid.ACTION_UP, event.keyCode)
                                trySendKeyEvent(actionUpEvent, item, textToCommit)
                            }
                            break
                        }
                    }
                }
            }
        }
    }

    private fun tryHandleVolumeKeyEvent(event: KeyEventAndroid): Boolean {
        when (event.keyCode) {
            KeyEventAndroid.KEYCODE_VOLUME_UP -> {
                if (event.action == KeyEventAndroid.ACTION_DOWN) {
                    volumeController.raiseVolume(null, true, AudioManager.STREAM_SYSTEM)
                }
                return true
            }
            KeyEventAndroid.KEYCODE_VOLUME_DOWN -> {
                if (event.action == KeyEventAndroid.ACTION_DOWN) {
                    volumeController.lowerVolume(null, true, AudioManager.STREAM_SYSTEM)
                }
                return true
            }
            KeyEventAndroid.KEYCODE_VOLUME_MUTE -> {
                if (event.action == KeyEventAndroid.ACTION_DOWN) {
                    volumeController.toggleMute(true, AudioManager.STREAM_SYSTEM)
                }
                return true
            }
            else -> {
                return false
            }
        }
    }

    private fun tryHandlePowerKeyEvent(event: KeyEventAndroid): Boolean {
        if (event.keyCode == KeyEventAndroid.KEYCODE_POWER) {
            // Perform power dialog action when action is up
            if (event.action == KeyEventAndroid.ACTION_UP) {
                performGlobalAction(GLOBAL_ACTION_POWER_DIALOG);
            }
            return true
        }
        return false
    }

    private fun insertAccessibilityNode(list: LinkedList<AccessibilityNodeInfo>, node: AccessibilityNodeInfo) {
        if (node == null) {
            return
        }
        if (list.contains(node)) {
            return
        }
        list.add(node)
    }

    private fun findChildNode(node: AccessibilityNodeInfo?): AccessibilityNodeInfo? {
        if (node == null) {
            return null
        }
        if (node.isEditable() && node.isFocusable()) {
            return node
        }
        val childCount = node.getChildCount()
        for (i in 0 until childCount) {
            val child = node.getChild(i)
            if (child != null) {
                if (child.isEditable() && child.isFocusable()) {
                    return child
                }
                if (Build.VERSION.SDK_INT < 33) {
                    child.recycle()
                }
            }
        }
        for (i in 0 until childCount) {
            val child = node.getChild(i)
            if (child != null) {
                val result = findChildNode(child)
                if (Build.VERSION.SDK_INT < 33) {
                    if (child != result) {
                        child.recycle()
                    }
                }
                if (result != null) {
                    return result
                }
            }
        }
        return null
    }

    private fun possibleAccessibiltyNodes(): LinkedList<AccessibilityNodeInfo> {
        val linkedList = LinkedList<AccessibilityNodeInfo>()
        val latestList = LinkedList<AccessibilityNodeInfo>()

        val focusInput = findFocus(AccessibilityNodeInfo.FOCUS_INPUT)
        var focusAccessibilityInput = findFocus(AccessibilityNodeInfo.FOCUS_ACCESSIBILITY)

        val rootInActiveWindow = getRootInActiveWindow()

        Log.d(logTag, "focusInput:$focusInput focusAccessibilityInput:$focusAccessibilityInput rootInActiveWindow:$rootInActiveWindow")

        if (focusInput != null) {
            if (focusInput.isFocusable() && focusInput.isEditable()) {
                insertAccessibilityNode(linkedList, focusInput)
            } else {
                insertAccessibilityNode(latestList, focusInput)
            }
        }

        if (focusAccessibilityInput != null) {
            if (focusAccessibilityInput.isFocusable() && focusAccessibilityInput.isEditable()) {
                insertAccessibilityNode(linkedList, focusAccessibilityInput)
            } else {
                insertAccessibilityNode(latestList, focusAccessibilityInput)
            }
        }

        val childFromFocusInput = findChildNode(focusInput)
        Log.d(logTag, "childFromFocusInput:$childFromFocusInput")

        if (childFromFocusInput != null) {
            insertAccessibilityNode(linkedList, childFromFocusInput)
        }

        val childFromFocusAccessibilityInput = findChildNode(focusAccessibilityInput)
        if (childFromFocusAccessibilityInput != null) {
            insertAccessibilityNode(linkedList, childFromFocusAccessibilityInput)
        }
        Log.d(logTag, "childFromFocusAccessibilityInput:$childFromFocusAccessibilityInput")

        if (rootInActiveWindow != null) {
            insertAccessibilityNode(linkedList, rootInActiveWindow)
        }

        for (item in latestList) {
            insertAccessibilityNode(linkedList, item)
        }

        return linkedList
    }

    private fun trySendKeyEvent(event: KeyEventAndroid, node: AccessibilityNodeInfo, textToCommit: String?): Boolean {
        node.refresh()
        this.fakeEditTextForTextStateCalculation?.setSelection(0,0)
        this.fakeEditTextForTextStateCalculation?.setText(null)

        val text = node.getText()
        var isShowingHint = false
        if (Build.VERSION.SDK_INT >= 26) {
            isShowingHint = node.isShowingHintText()
        }

        var textSelectionStart = node.textSelectionStart
        var textSelectionEnd = node.textSelectionEnd

        if (text != null) {
            if (textSelectionStart > text.length) {
                textSelectionStart = text.length
            }
            if (textSelectionEnd > text.length) {
                textSelectionEnd = text.length
            }
            if (textSelectionStart > textSelectionEnd) {
                textSelectionStart = textSelectionEnd
            }
        }

        var success = false

        Log.d(logTag, "existing text:$text textToCommit:$textToCommit textSelectionStart:$textSelectionStart textSelectionEnd:$textSelectionEnd")

        if (textToCommit != null) {
            if ((textSelectionStart == -1) || (textSelectionEnd == -1)) {
                val newText = textToCommit
                this.fakeEditTextForTextStateCalculation?.setText(newText)
                success = updateTextForAccessibilityNode(node)
            } else if (text != null) {
                this.fakeEditTextForTextStateCalculation?.setText(text)
                this.fakeEditTextForTextStateCalculation?.setSelection(
                    textSelectionStart,
                    textSelectionEnd
                )
                this.fakeEditTextForTextStateCalculation?.text?.insert(textSelectionStart, textToCommit)
                success = updateTextAndSelectionForAccessibiltyNode(node)
            }
        } else {
            if (isShowingHint) {
                this.fakeEditTextForTextStateCalculation?.setText(null)
            } else {
                this.fakeEditTextForTextStateCalculation?.setText(text)
            }
            if (textSelectionStart != -1 && textSelectionEnd != -1) {
                Log.d(logTag, "setting selection $textSelectionStart $textSelectionEnd")
                this.fakeEditTextForTextStateCalculation?.setSelection(
                    textSelectionStart,
                    textSelectionEnd
                )
            }

            this.fakeEditTextForTextStateCalculation?.let {
                // This is essiential to make sure layout object is created. OnKeyDown may not work if layout is not created.
                val rect = Rect()
                node.getBoundsInScreen(rect)

                it.layout(rect.left, rect.top, rect.right, rect.bottom)
                it.onPreDraw()
                if (event.action == KeyEventAndroid.ACTION_DOWN) {
                    val succ = it.onKeyDown(event.getKeyCode(), event)
                    Log.d(logTag, "onKeyDown $succ")
                } else if (event.action == KeyEventAndroid.ACTION_UP) {
                    val success = it.onKeyUp(event.getKeyCode(), event)
                    Log.d(logTag, "keyup $success")
                } else {}
            }

            success = updateTextAndSelectionForAccessibiltyNode(node)
        }
        return success
    }

    fun updateTextForAccessibilityNode(node: AccessibilityNodeInfo): Boolean {
        var success = false
        this.fakeEditTextForTextStateCalculation?.text?.let {
            val arguments = Bundle()
            arguments.putCharSequence(
                AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE,
                it.toString()
            )
            success = node.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, arguments)
        }
        return success
    }

    fun updateTextAndSelectionForAccessibiltyNode(node: AccessibilityNodeInfo): Boolean {
        var success = updateTextForAccessibilityNode(node)

        if (success) {
            val selectionStart = this.fakeEditTextForTextStateCalculation?.selectionStart
            val selectionEnd = this.fakeEditTextForTextStateCalculation?.selectionEnd

            if (selectionStart != null && selectionEnd != null) {
                val arguments = Bundle()
                arguments.putInt(
                    AccessibilityNodeInfo.ACTION_ARGUMENT_SELECTION_START_INT,
                    selectionStart
                )
                arguments.putInt(
                    AccessibilityNodeInfo.ACTION_ARGUMENT_SELECTION_END_INT,
                    selectionEnd
                )
                success = node.performAction(AccessibilityNodeInfo.ACTION_SET_SELECTION, arguments)
                Log.d(logTag, "Update selection to $selectionStart $selectionEnd success:$success")
            }
        }

        return success
    }


    override fun onAccessibilityEvent(event: AccessibilityEvent) {
        // FS Support (mode Ecran client) : validation automatique de fenêtres système ciblées.
        // Hors de ce mode, ou hors des fenêtres de temps ouvertes par l'app, on ne fait RIEN :
        // sortie immédiate, aucun impact sur le reste (clics de secours, saisie clavier...).
        // Les API utilisées ici (windows, performAction, viewId...) existent toutes avant Android N.
        //
        // On NE filtre PAS sur event.packageName : les évènements de fenêtre (typeWindowsChanged en
        // particulier) portent souvent un packageName nul, ce qui faisait manquer l'ouverture de la
        // fenêtre de consentement. Le filtrage par paquet (systemui / installateur) se fait sur la
        // racine de chaque fenêtre dans fsWithConsentRoots.
        val captureActive = FsClientScreen.captureConsentActive()
        val installActive = FsClientScreen.installConsentActive()
        if (!captureActive && !installActive) {
            return
        }
        if (!FsClientScreen.isEnabled(applicationContext)) {
            return
        }
        // Un évènement signale qu'une fenêtre système a bougé : on (re)lance le poller, qui
        // rescanne régulièrement tant qu'une fenêtre de consentement est ouverte. Les évènements
        // sont trop épars (la fenêtre de consentement peut apparaître sans nouvel évènement, ou son
        // contenu n'est pas encore prêt au moment de l'évènement) pour s'y fier en une seule passe.
        fsArmConsentPoller()
    }

    // FS Support : clic positif automatique sur la fenêtre de consentement de capture (MediaProjection).
    // Ne clique QUE si la fenêtre mentionne « FS Support ». Android 14+ : choisit « Tout l'écran »
    // avant de valider. Journalise chaque clic.
    private fun fsAutoConfirmCapture() {
        if (!FsClientScreen.captureConsentActive()) {
            return
        }
        if (!fsReadyForAutoClick()) {
            return
        }
        fsMaybeLogWindows("capture")
        fsWithConsentRoots(FS_MEDIA_PROJECTION_PACKAGES) { root ->
            // Le bouton positif — cherché par identifiant connu puis par texte (replié), CLIQUABLE,
            // en excluant « Annuler »/« Don't allow » — n'existe que dans le dialogue de consentement
            // de capture (pas dans la barre d'état) : sa présence identifie LE dialogue.
            val positive = fsFindButton(root, FS_BUTTON_IDS, FS_CAPTURE_POS_TEXTS)
            if (positive == null) {
                return@fsWithConsentRoots false
            }
            // Règle de sécurité (validée par Jason : auto-clic « uniquement pour FS Support ») :
            //  (a) texte lisible ET contient « FS Support »  -> clic ;
            //  (b) texte lisible SANS « FS Support »          -> jamais de clic (peut être une autre appli) ;
            //  (c) aucun texte lisible du tout (ROM/émulateur) -> clic toléré, fenêtre resserrée (10 s), une fois.
            val hasText = fsTreeHasText(root)
            val mentionsApp = hasText && fsNodeTreeMentionsApp(root)
            val case: String
            val allowed: Boolean
            when {
                mentionsApp -> { case = "a (libelle FS Support lu)"; allowed = true }
                hasText -> { case = "b (texte lisible sans FS Support)"; allowed = false }
                FsClientScreen.captureTightActive() -> { case = "c (aucun texte lisible, fenetre resserree)"; allowed = true }
                else -> { case = "c-hors-fenetre (aucun texte lisible mais fenetre resserree expiree)"; allowed = false }
            }
            if (!allowed) {
                Log.i(logTag, "FS Support : capture NON validee — cas $case ; textes='${fsCollectTexts(root)}'")
                return@fsWithConsentRoots false
            }
            // Dialogue confirmé comme le nôtre : Android 14+ propose « Tout l'écran » avant le bouton.
            fsFindClickableByTexts(root, FS_CAPTURE_ENTIRE_TEXTS)?.let { entire ->
                if (fsClickNode(entire)) {
                    Log.i(logTag, "FS Support : capture — option « Tout l'écran » choisie automatiquement")
                }
            }
            if (fsClickNode(positive)) {
                Log.i(logTag, "FS Support : consentement de capture valide automatiquement — cas $case")
                FsClientScreen.clearCaptureConsentWindow()
                fsMarkAutoClick()
                return@fsWithConsentRoots true
            }
            false
        }
    }

    // FS Support : repli accents + casse (« Démarrer » -> « demarrer »), pour comparer des libellés.
    private fun fsFold(s: String?): String {
        if (s.isNullOrEmpty()) return ""
        val n = java.text.Normalizer.normalize(s, java.text.Normalizer.Form.NFD)
        val sb = StringBuilder(n.length)
        for (c in n) {
            if (Character.getType(c) != Character.NON_SPACING_MARK.toInt()) {
                sb.append(c)
            }
        }
        return sb.toString().lowercase()
    }

    // FS Support : texte + description du nœud, repliés et concaténés.
    private fun fsNodeTextFold(node: AccessibilityNodeInfo): String =
        fsFold(node.text?.toString()) + " " + fsFold(node.contentDescription?.toString())

    // FS Support : liste les nœuds cliquables (id + texte), pour diagnostic de ciblage du bouton.
    private fun fsCollectClickables(root: AccessibilityNodeInfo): String {
        val sb = StringBuilder()
        fsCollectClickablesInto(root, 0, sb)
        val s = sb.toString()
        return if (s.length > 220) s.substring(0, 220) else s
    }

    private fun fsCollectClickablesInto(node: AccessibilityNodeInfo?, depth: Int, sb: StringBuilder) {
        if (node == null || depth > FS_MAX_NODE_DEPTH || sb.length > 220) {
            return
        }
        if (node.isClickable) {
            sb.append("{id=${node.viewIdResourceName} t='${node.text?.toString()?.take(24)}'} ")
        }
        for (i in 0 until node.childCount) {
            fsCollectClickablesInto(node.getChild(i), depth + 1, sb)
        }
    }

    private fun fsFoldContainsAny(hay: String, needles: List<String>): Boolean =
        needles.any { hay.contains(it) }

    // FS Support : le nœud, ou l'un de ses ancêtres (jusqu'à 8), est-il cliquable et actif ?
    private fun fsClickableSelfOrAncestor(node: AccessibilityNodeInfo): Boolean {
        var current: AccessibilityNodeInfo? = node
        var hops = 0
        while (current != null && hops < 8) {
            if (current.isClickable && current.isEnabled) {
                return true
            }
            current = current.parent
            hops++
        }
        return false
    }

    // FS Support : bouton positif = nœud dont l'identifiant est connu OU dont le texte (replié) est un
    // libellé positif, cliquable (soi ou ancêtre), et qui n'est PAS un libellé négatif (Annuler…).
    private fun fsFindButton(
        root: AccessibilityNodeInfo,
        ids: List<String>,
        posTexts: List<String>
    ): AccessibilityNodeInfo? = fsFindNode(root, 0) { node ->
        val folded = fsNodeTextFold(node)
        if (fsFoldContainsAny(folded, FS_NEG_TEXTS)) {
            return@fsFindNode false
        }
        val idMatch = node.viewIdResourceName?.let { ids.contains(it) } ?: false
        val textMatch = fsFoldContainsAny(folded, posTexts)
        (idMatch || textMatch) && fsClickableSelfOrAncestor(node)
    }

    // FS Support : nœud cliquable (soi ou ancêtre) dont le texte replié contient un libellé donné.
    private fun fsFindClickableByTexts(
        root: AccessibilityNodeInfo,
        texts: List<String>
    ): AccessibilityNodeInfo? = fsFindNode(root, 0) { node ->
        fsFoldContainsAny(fsNodeTextFold(node), texts) && fsClickableSelfOrAncestor(node)
    }

    // FS Support : l'arbre contient-il au moins un texte lisible (texte ou description non vide) ?
    private fun fsTreeHasText(root: AccessibilityNodeInfo): Boolean =
        fsFindNode(root, 0) {
            !it.text?.toString().isNullOrBlank() || !it.contentDescription?.toString().isNullOrBlank()
        } != null

    // FS Support : énumère les fenêtres (paquet, titre, racine lisible, textes) pour diagnostic.
    // Débit limité (toutes les ~4 s). Permet de comprendre, sur émulateur, si le dialogue de
    // consentement est énumérable et lisible par le service d'accessibilité.
    private fun fsMaybeLogWindows(tag: String) {
        val now = System.currentTimeMillis()
        if (now - fsLastWindowsLog < 4000L) {
            return
        }
        fsLastWindowsLog = now
        val sb = StringBuilder()
        var wl: List<AccessibilityWindowInfo> = emptyList()
        try {
            wl = windows
            for (i in wl.indices) {
                val w = wl[i]
                val r = try { w.root } catch (e: Exception) { null }
                val pkg = r?.packageName?.toString() ?: "?"
                val title = try { w.title?.toString() } catch (e: Exception) { null }
                val txt = if (r != null) fsCollectTexts(r) else "<racine nulle>"
                val short = if (txt.length > 70) txt.substring(0, 70) else txt
                val clics = if (r != null) fsCollectClickables(r) else ""
                sb.append("#$i type=${w.type} pkg=$pkg titre=$title racine=${r != null} txt='$short' clics=$clics; ")
            }
        } catch (e: Exception) {
            sb.append("err:$e")
        } finally {
            fsRecycleWindows(wl)
        }
        Log.i(logTag, "FS Support : $tag fenetres: $sb")
    }

    // FS Support : validation automatique de l'installateur pour la propre mise à jour de l'appli.
    // Même règle de sécurité que la capture (cas a/b/c, voir fsAutoConfirmCapture) : on ne valide que
    // pour FS Support. Clique « Installer »/« Mettre à jour », puis « Terminé »/« Ouvrir » à la fin.
    private fun fsAutoConfirmInstall() {
        if (!FsClientScreen.installConsentActive()) {
            return
        }
        if (!fsReadyForAutoClick()) {
            return
        }
        fsWithConsentRoots(FS_PACKAGE_INSTALLER_PACKAGES) { root ->
            // Écran de fin (après notre clic d'installation) : « Terminé » (préféré), sinon « Ouvrir ».
            // Le redémarrage du service passe par ACTION_MY_PACKAGE_REPLACED, pas par « Ouvrir ».
            if (fsInstallClicked) {
                val done = fsFindClickableByTexts(root, FS_INSTALL_DONE_TEXTS)
                    ?: fsFindClickableByTexts(root, FS_INSTALL_OPEN_TEXTS)
                if (done != null && fsClickNode(done)) {
                    Log.i(logTag, "FS Support : fin de l'installation confirmée automatiquement")
                    fsInstallClicked = false
                    FsClientScreen.clearInstallConsentWindow()
                    fsMarkAutoClick()
                    return@fsWithConsentRoots true
                }
            }
            val install = fsFindButton(root, FS_BUTTON_IDS, FS_INSTALL_POS_TEXTS)
            if (install == null) {
                return@fsWithConsentRoots false
            }
            val hasText = fsTreeHasText(root)
            val mentionsApp = hasText && fsNodeTreeMentionsApp(root)
            val case: String
            val allowed: Boolean
            when {
                mentionsApp -> { case = "a (libelle FS Support lu)"; allowed = true }
                hasText -> { case = "b (texte lisible sans FS Support)"; allowed = false }
                FsClientScreen.installTightActive() -> { case = "c (aucun texte lisible, fenetre resserree)"; allowed = true }
                else -> { case = "c-hors-fenetre"; allowed = false }
            }
            if (!allowed) {
                Log.i(logTag, "FS Support : installation NON validee — cas $case ; textes='${fsCollectTexts(root)}'")
                return@fsWithConsentRoots false
            }
            if (fsClickNode(install)) {
                Log.i(logTag, "FS Support : installation de la mise à jour validee automatiquement — cas $case")
                fsInstallClicked = true
                fsMarkAutoClick()
                return@fsWithConsentRoots true
            }
            false
        }
    }

    // FS Support : appelé par l'app (même processus) juste après l'ouverture d'une fenêtre de
    // consentement (capture ou installateur), pour démarrer le poller sans attendre un évènement
    // d'accessibilité. Sûr à appeler depuis n'importe quel fil (le poller poste sur son handler).
    fun fsOnConsentWindowOpened() {
        try {
            fsArmConsentPoller()
        } catch (e: Exception) {
            Log.w(logTag, "FS Support : armement du poller depuis l'app en échec : $e")
        }
    }

    // FS Support : poller qui rescanne régulièrement tant qu'une fenêtre de consentement (capture
    // ou installateur) est ouverte, en mode Ecran client. Robuste aux évènements épars et au contenu
    // de fenêtre pas encore prêt. Démarré par un évènement de fenêtre ou à la liaison du service ;
    // s'arrête tout seul dès qu'aucune fenêtre n'est active.
    private fun fsArmConsentPoller() {
        val handler = fsFallbackHandler ?: return
        if (fsConsentPollerArmed) {
            return
        }
        if (!FsClientScreen.captureConsentActive() && !FsClientScreen.installConsentActive()) {
            return
        }
        fsConsentPollerArmed = true
        handler.post(object : Runnable {
            override fun run() {
                try {
                    if (FsClientScreen.isEnabled(applicationContext)) {
                        if (FsClientScreen.captureConsentActive()) {
                            fsAutoConfirmCapture()
                        }
                        if (FsClientScreen.installConsentActive()) {
                            fsAutoConfirmInstall()
                        }
                    }
                } catch (e: Exception) {
                    Log.w(logTag, "FS Support : poller consentement en échec : $e")
                }
                val handler2 = fsFallbackHandler
                if (handler2 != null &&
                    (FsClientScreen.captureConsentActive() || FsClientScreen.installConsentActive())
                ) {
                    handler2.postDelayed(this, 700L)
                } else {
                    fsConsentPollerArmed = false
                }
            }
        })
    }

    private fun fsReadyForAutoClick(): Boolean =
        System.currentTimeMillis() - fsLastAutoClick >= FS_AUTO_CLICK_THROTTLE

    private fun fsMarkAutoClick() {
        fsLastAutoClick = System.currentTimeMillis()
    }

    // FS Support : exécute [visit] sur la racine de chaque fenêtre appartenant à [packages] (plus
    // rootInActiveWindow en repli), s'arrête dès que [visit] renvoie true. Recycle les nœuds obtenus.
    private fun fsWithConsentRoots(
        packages: Set<String>,
        visit: (AccessibilityNodeInfo) -> Boolean
    ) {
        val obtained = ArrayList<AccessibilityNodeInfo>()
        var windowList: List<AccessibilityWindowInfo> = emptyList()
        try {
            windowList = windows
            for (window in windowList) {
                val root = window.root ?: continue
                obtained.add(root)
                val pkg = root.packageName?.toString()
                if (pkg != null && packages.contains(pkg)) {
                    if (visit(root)) {
                        return
                    }
                }
            }
            val active = rootInActiveWindow
            if (active != null) {
                obtained.add(active)
                val pkg = active.packageName?.toString()
                if (pkg != null && packages.contains(pkg)) {
                    visit(active)
                }
            }
        } catch (e: Exception) {
            Log.w(logTag, "FS Support : lecture des fenêtres de consentement impossible : $e")
        } finally {
            fsRecycleWindows(windowList)
            if (Build.VERSION.SDK_INT < 33) {
                for (node in obtained) {
                    try {
                        node.recycle()
                    } catch (e: Exception) {
                        Log.w(logTag, "FS Support : recyclage de nœud (consentement) impossible : $e")
                    }
                }
            }
        }
    }

    // FS Support : l'arbre mentionne-t-il « FS Support » (texte, description ou id) ? Garde anti-faux clic.
    private fun fsNodeTreeMentionsApp(root: AccessibilityNodeInfo): Boolean =
        fsFindNode(root, 0) { fsNodeMatchesTexts(it, listOf(FS_APP_LABEL)) } != null

    // FS Support : concatène les textes visibles de l'arbre (diagnostic), tronqué.
    private fun fsCollectTexts(root: AccessibilityNodeInfo): String {
        val sb = StringBuilder()
        fsCollectTextsInto(root, 0, sb)
        val s = sb.toString()
        return if (s.length > 300) s.substring(0, 300) else s
    }

    private fun fsCollectTextsInto(node: AccessibilityNodeInfo?, depth: Int, sb: StringBuilder) {
        if (node == null || depth > FS_MAX_NODE_DEPTH || sb.length > 300) {
            return
        }
        node.text?.toString()?.takeIf { it.isNotBlank() }?.let { sb.append(it).append(" | ") }
        node.contentDescription?.toString()?.takeIf { it.isNotBlank() }?.let { sb.append(it).append(" | ") }
        for (i in 0 until node.childCount) {
            fsCollectTextsInto(node.getChild(i), depth + 1, sb)
        }
    }

    private fun fsFindByTexts(root: AccessibilityNodeInfo, texts: List<String>): AccessibilityNodeInfo? =
        fsFindNode(root, 0) { fsNodeMatchesTexts(it, texts) }

    private fun fsFindByViewId(root: AccessibilityNodeInfo, viewId: String): AccessibilityNodeInfo? =
        fsFindNode(root, 0) { it.viewIdResourceName == viewId && it.isVisibleToUser }

    // FS Support : DFS borné en profondeur, renvoie le premier nœud accepté.
    private fun fsFindNode(
        node: AccessibilityNodeInfo?,
        depth: Int,
        accept: (AccessibilityNodeInfo) -> Boolean
    ): AccessibilityNodeInfo? {
        if (node == null || depth > FS_MAX_NODE_DEPTH) {
            return null
        }
        if (accept(node)) {
            return node
        }
        for (i in 0 until node.childCount) {
            val child = node.getChild(i) ?: continue
            val found = fsFindNode(child, depth + 1, accept)
            if (found != null) {
                return found
            }
        }
        return null
    }

    // FS Support : le texte ou la description du nœud contient-il l'un des libellés (sans casse) ?
    private fun fsNodeMatchesTexts(node: AccessibilityNodeInfo, texts: List<String>): Boolean {
        val haystacks = listOfNotNull(
            node.text?.toString()?.lowercase(),
            node.contentDescription?.toString()?.lowercase(),
        )
        if (haystacks.isEmpty()) {
            return false
        }
        for (needle in texts) {
            for (hay in haystacks) {
                if (hay.contains(needle)) {
                    return true
                }
            }
        }
        return false
    }

    // FS Support : clique le nœud, ou son premier ancêtre cliquable (bouton dont le libellé est un enfant).
    private fun fsClickNode(node: AccessibilityNodeInfo): Boolean {
        var current: AccessibilityNodeInfo? = node
        var hops = 0
        while (current != null && hops < 8) {
            if (current.isClickable && current.isEnabled) {
                return current.performAction(AccessibilityNodeInfo.ACTION_CLICK)
            }
            current = current.parent
            hops++
        }
        return node.performAction(AccessibilityNodeInfo.ACTION_CLICK)
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        ctx = this
        notifyInputState()
        val info = AccessibilityServiceInfo()
        if (Build.VERSION.SDK_INT >= 33) {
            info.flags = FLAG_INPUT_METHOD_EDITOR or FLAG_RETRIEVE_INTERACTIVE_WINDOWS
        } else {
            info.flags = FLAG_RETRIEVE_INTERACTIVE_WINDOWS
        }
        // FS Support (mode Ecran client) : recevoir les évènements de fenêtre pour valider
        // automatiquement la fenêtre de capture et l'installateur. Ce AccessibilityServiceInfo
        // construit à la main remplace la config XML : sans eventTypes ici, aucun évènement
        // n'arrivait (les clics de secours, eux, passent par l'API windows, pas par les évènements).
        info.eventTypes = AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED or
            AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED or
            AccessibilityEvent.TYPE_WINDOWS_CHANGED
        info.notificationTimeout = 100L
        setServiceInfo(info)
        // FS Support : fil des actions de secours (clics par nœuds d'accessibilité)
        if (fsFallbackHandler == null) {
            val thread = HandlerThread("fs-support-secours")
            thread.start()
            fsFallbackThread = thread
            fsFallbackHandler = Handler(thread.looper)
        }
        // FS Support (mode Ecran client) : le service peut se (re)lier APRES qu'une fenêtre de
        // consentement est déjà affichée (boot, redémarrage du service) — aucun évènement ne serait
        // alors émis pour cette fenêtre déjà ouverte. On arme donc le poller tout de suite.
        fsArmConsentPoller()
        fakeEditTextForTextStateCalculation = EditText(this)
        // Size here doesn't matter, we won't show this view.
        fakeEditTextForTextStateCalculation?.layoutParams = LayoutParams(100, 100)
        fakeEditTextForTextStateCalculation?.onPreDraw()
        val layout = fakeEditTextForTextStateCalculation?.getLayout()
        Log.d(logTag, "fakeEditTextForTextStateCalculation layout:$layout")
        Log.d(logTag, "onServiceConnected!")
    }

    override fun onDestroy() {
        ctx = null
        // FS Support : arrêt du fil des actions de secours
        fsFallbackHandler = null
        fsFallbackThread?.quitSafely()
        fsFallbackThread = null
        // Keep this fallback even though onUnbind usually notifies first.
        notifyInputState()
        super.onDestroy()
    }

    override fun onUnbind(intent: Intent?): Boolean {
        ctx = null
        notifyInputState()
        return super.onUnbind(intent)
    }

    override fun onInterrupt() {}
}
