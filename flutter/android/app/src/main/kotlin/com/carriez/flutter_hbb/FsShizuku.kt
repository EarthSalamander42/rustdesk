package com.carriez.flutter_hbb

import android.content.pm.PackageManager
import android.os.Build
import android.os.IBinder
import android.os.SystemClock
import android.util.Log
import android.view.InputDevice
import android.view.InputEvent
import android.view.KeyEvent
import android.view.MotionEvent
import org.lsposed.hiddenapibypass.HiddenApiBypass
import rikka.shizuku.Shizuku
import rikka.shizuku.ShizukuBinderWrapper
import rikka.shizuku.SystemServiceHelper
import java.lang.reflect.Method

/**
 * FS Support : injection tactile réelle par Shizuku, pour les ROM qui refusent dispatchGesture
 * (Droidlogic/Amlogic). Optionnelle : sans Shizuku installé, démarré et autorisé, [ready] reste
 * faux et InputService garde son chemin habituel (gestes d'accessibilité puis nœuds).
 *
 * Les événements passent par IInputManager.injectInputEvent avec l'identité de Shizuku (shell ou
 * root), ce qui donne un vrai doigt : appui, glissé continu (dessin), relâché, et les touches
 * système (récents, retour, accueil) que performGlobalAction ne fait pas sur ces boîtiers.
 */
object FsShizuku {
    private const val TAG = "FsShizuku"
    private const val REQUEST_CODE = 4242
    // InputManager.INJECT_INPUT_EVENT_MODE_ASYNC : ne bloque pas le fil d'entrée
    private const val INJECT_ASYNC = 0

    @Volatile private var inputManager: Any? = null
    @Volatile private var injectMethod: Method? = null
    @Volatile private var askedOnce = false
    @Volatile private var downTime = 0L
    @Volatile private var pointerDown = false

    private val permissionListener = Shizuku.OnRequestPermissionResultListener { code, result ->
        if (code == REQUEST_CODE) {
            Log.i(TAG, "autorisation Shizuku : ${result == PackageManager.PERMISSION_GRANTED}")
        }
    }

    private val binderListener = Shizuku.OnBinderReceivedListener {
        // Shizuku vient de démarrer (ou de redémarrer) : demander l'autorisation une fois.
        requestIfNeeded()
    }

    private val binderDeadListener = Shizuku.OnBinderDeadListener {
        inputManager = null
        injectMethod = null
        pointerDown = false
    }

    /** À appeler à la connexion du service d'accessibilité. Sans Shizuku, ne fait rien. */
    fun init() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) return
        try {
            Shizuku.addRequestPermissionResultListener(permissionListener)
            Shizuku.addBinderReceivedListenerSticky(binderListener)
            Shizuku.addBinderDeadListener(binderDeadListener)
        } catch (e: Throwable) {
            Log.w(TAG, "Shizuku indisponible : $e")
        }
    }

    fun release() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) return
        try {
            Shizuku.removeRequestPermissionResultListener(permissionListener)
            Shizuku.removeBinderReceivedListener(binderListener)
            Shizuku.removeBinderDeadListener(binderDeadListener)
        } catch (_: Throwable) {
        }
        inputManager = null
        injectMethod = null
    }

    private fun requestIfNeeded() {
        try {
            if (!Shizuku.pingBinder() || Shizuku.isPreV11()) return
            if (Shizuku.checkSelfPermission() == PackageManager.PERMISSION_GRANTED) return
            if (askedOnce || Shizuku.shouldShowRequestPermissionRationale()) return
            askedOnce = true
            Shizuku.requestPermission(REQUEST_CODE)
        } catch (e: Throwable) {
            Log.w(TAG, "demande d'autorisation impossible : $e")
        }
    }

    /** Vrai seulement si Shizuku tourne, est autorisé, et que l'injection est prête. */
    fun ready(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) return false
        return try {
            if (!Shizuku.pingBinder() || Shizuku.isPreV11()) return false
            if (Shizuku.checkSelfPermission() != PackageManager.PERMISSION_GRANTED) return false
            ensureInjector()
        } catch (e: Throwable) {
            false
        }
    }

    private fun ensureInjector(): Boolean {
        if (inputManager != null && injectMethod != null) return true
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                HiddenApiBypass.addHiddenApiExemptions("Landroid/hardware/input/IInputManager")
            }
            val binder: IBinder = ShizukuBinderWrapper(SystemServiceHelper.getSystemService("input"))
            val stub = Class.forName("android.hardware.input.IInputManager\$Stub")
            val im = stub.getMethod("asInterface", IBinder::class.java).invoke(null, binder)
            val inject = Class.forName("android.hardware.input.IInputManager")
                .getMethod("injectInputEvent", InputEvent::class.java, Int::class.javaPrimitiveType)
            inputManager = im
            injectMethod = inject
            Log.i(TAG, "injection Shizuku prête")
            true
        } catch (e: Throwable) {
            Log.w(TAG, "injection Shizuku impossible : $e")
            false
        }
    }

    private fun inject(event: InputEvent): Boolean {
        return try {
            (injectMethod?.invoke(inputManager, event, INJECT_ASYNC) as? Boolean) ?: false
        } catch (e: Throwable) {
            Log.w(TAG, "injection refusée : $e")
            false
        }
    }

    private fun touch(action: Int, x: Int, y: Int, time: Long): Boolean {
        val ev = MotionEvent.obtain(downTime, time, action, x.toFloat(), y.toFloat(), 1.0f, 1.0f, 0, 1.0f, 1.0f, 0, 0)
        ev.source = InputDevice.SOURCE_TOUCHSCREEN
        val done = inject(ev)
        ev.recycle()
        return done
    }

    /** Appui du doigt. Faux si Shizuku n'est pas prêt : l'appelant garde son chemin habituel. */
    fun down(x: Int, y: Int): Boolean {
        if (!ready()) return false
        downTime = SystemClock.uptimeMillis()
        pointerDown = touch(MotionEvent.ACTION_DOWN, x, y, downTime)
        return pointerDown
    }

    /** Glissé du doigt, seulement entre down et up. */
    fun move(x: Int, y: Int): Boolean {
        if (!pointerDown) return false
        return touch(MotionEvent.ACTION_MOVE, x, y, SystemClock.uptimeMillis())
    }

    fun up(x: Int, y: Int): Boolean {
        if (!pointerDown) return false
        pointerDown = false
        return touch(MotionEvent.ACTION_UP, x, y, SystemClock.uptimeMillis())
    }

    fun isPointerDown(): Boolean = pointerDown

    /** Touche système (KEYCODE_APP_SWITCH, KEYCODE_BACK, KEYCODE_HOME…). */
    fun key(keyCode: Int): Boolean {
        if (!ready()) return false
        val now = SystemClock.uptimeMillis()
        val down = KeyEvent(now, now, KeyEvent.ACTION_DOWN, keyCode, 0, 0, -1, 0, 0, InputDevice.SOURCE_KEYBOARD)
        val up = KeyEvent(now, SystemClock.uptimeMillis(), KeyEvent.ACTION_UP, keyCode, 0, 0, -1, 0, 0, InputDevice.SOURCE_KEYBOARD)
        return inject(down) && inject(up)
    }
}
