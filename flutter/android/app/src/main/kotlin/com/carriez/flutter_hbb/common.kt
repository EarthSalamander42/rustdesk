package com.carriez.flutter_hbb

import android.Manifest.permission.*
import android.annotation.SuppressLint
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.media.AudioRecord
import android.media.AudioRecord.READ_BLOCKING
import android.media.MediaCodecList
import android.media.MediaFormat
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.provider.Settings
import android.provider.Settings.*
import android.util.DisplayMetrics
import android.util.Log
import android.view.WindowManager
import androidx.annotation.RequiresApi
import androidx.core.content.ContextCompat.getSystemService
import com.hjq.permissions.Permission
import com.hjq.permissions.XXPermissions
import ffi.FFI
import java.nio.ByteBuffer
import java.util.*


// intent action, extra
const val ACT_REQUEST_MEDIA_PROJECTION = "REQUEST_MEDIA_PROJECTION"
const val ACT_INIT_MEDIA_PROJECTION_AND_SERVICE = "INIT_MEDIA_PROJECTION_AND_SERVICE"
const val ACT_LOGIN_REQ_NOTIFY = "LOGIN_REQ_NOTIFY"
const val EXT_INIT_FROM_BOOT = "EXT_INIT_FROM_BOOT"
const val EXT_MEDIA_PROJECTION_RES_INTENT = "MEDIA_PROJECTION_RES_INTENT"
const val EXT_MEDIA_PROJECTION_RESULT_RECEIVER = "MEDIA_PROJECTION_RESULT_RECEIVER"
const val EXT_LOGIN_REQ_NOTIFY = "LOGIN_REQ_NOTIFY"
// FS Support : identifiant de connexion porté par les boutons de la notification de demande.
const val EXT_LOGIN_REQ_CLIENT_ID = "LOGIN_REQ_CLIENT_ID"

// Activity requestCode
const val REQ_INVOKE_PERMISSION_ACTIVITY_MEDIA_PROJECTION = 101
const val REQ_REQUEST_MEDIA_PROJECTION = 201
const val REQ_EXPORT_FILE = 301
const val REQ_IMPORT_FILES = 302
const val REQ_IMPORT_DIRECTORY = 303
const val REQ_EXPORT_FILES = 304

// Activity responseCode
const val RES_FAILED = -100

// Flutter channel
const val START_ACTION = "start_action"
const val GET_START_ON_BOOT_OPT = "get_start_on_boot_opt"
const val SET_START_ON_BOOT_OPT = "set_start_on_boot_opt"
const val SYNC_APP_DIR_CONFIG_PATH = "sync_app_dir"
const val PICK_IMPORT_FILES = "pick_import_files"
const val IMPORT_FILE = "import_file"
const val EXPORT_FILE = "export_file"
const val PICK_IMPORT_DIRECTORY = "pick_import_directory"
const val IMPORT_DIRECTORY = "import_directory"
const val EXPORT_FILES = "export_files"
const val GET_VALUE = "get_value"

const val KEY_IS_SUPPORT_VOICE_CALL = "KEY_IS_SUPPORT_VOICE_CALL"

const val KEY_SHARED_PREFERENCES = "KEY_SHARED_PREFERENCES"
const val KEY_START_ON_BOOT_OPT = "KEY_START_ON_BOOT_OPT"
const val KEY_APP_DIR_CONFIG_PATH = "KEY_APP_DIR_CONFIG_PATH"

// FS Support : option locale (pont Rust, lue par FFI.getLocalOption) qui force tous les
// clics / appuis longs / defilements a passer par les noeuds d'accessibilite, sans tenter
// dispatchGesture. Pour les ROM (boitiers Droidlogic) qui declarent les gestes aboutis tout
// en les ignorant, ce que le mode de secours automatique (compteur de refus) ne detecte pas.
const val KEY_FS_FORCE_ACCESSIBILITY_CLICKS = "fs-force-accessibility-clicks"

@SuppressLint("ConstantLocale")
val LOCAL_NAME = Locale.getDefault().toString()
val SCREEN_INFO = Info(0, 0, 1, 200)

data class Info(
    var width: Int, var height: Int, var scale: Int, var dpi: Int
)

fun isSupportVoiceCall(): Boolean {
    // https://developer.android.com/reference/android/media/MediaRecorder.AudioSource#VOICE_COMMUNICATION
    return Build.VERSION.SDK_INT >= Build.VERSION_CODES.R
}

fun requestPermission(context: Context, type: String) {
    XXPermissions.with(context)
        .permission(type)
        .request { _, all ->
            if (all) {
                Handler(Looper.getMainLooper()).post {
                    MainActivity.flutterMethodChannel?.invokeMethod(
                        "on_android_permission_result",
                        mapOf("type" to type, "result" to all)
                    )
                }
            }
        }
}

fun startAction(context: Context, action: String) {
    try {
        context.startActivity(Intent(action).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            // don't pass package name when launch ACTION_ACCESSIBILITY_SETTINGS
            if (ACTION_ACCESSIBILITY_SETTINGS != action) {
                data = Uri.parse("package:" + context.packageName)
            }
        })
    } catch (e: Exception) {
        e.printStackTrace()
        if (action == ACTION_MANAGE_OVERLAY_PERMISSION) {
            startOverlaySettingsFallback(context)
        }
    }
}

// FS Support : certaines ROM (boîtiers Android TV, Amlogic « Droidlogic ») n'ont pas la page par
// appli de l'autorisation de superposition : liste générale, puis fiche de l'appli. Si tout est
// masqué : adb shell appops set fr.fssolutions.support SYSTEM_ALERT_WINDOW allow
private fun startOverlaySettingsFallback(context: Context) {
    val intents = listOf(
        Intent(ACTION_MANAGE_OVERLAY_PERMISSION),
        Intent(ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:" + context.packageName)),
    )
    for (intent in intents) {
        try {
            context.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            return
        } catch (e: Exception) {
            Log.w("common", "FS Support : réglage indisponible : ${intent.action}", e)
        }
    }
}

// FS Support (assistant « Ecran client ») : ouvre directement la fiche du service d'accessibilite
// FS Support (ACCESSIBILITY_DETAILS_SETTINGS + composant), avec repli sur la liste generale puis la
// fiche de l'appli pour les ROM qui n'ont pas cette page (boitiers TV, Amlogic « Droidlogic »).
fun startAccessibilityDetails(context: Context) {
    val component = ComponentName(context, InputService::class.java).flattenToString()
    val detail = Intent("android.settings.ACCESSIBILITY_DETAILS_SETTINGS").apply {
        putExtra("android.intent.extra.COMPONENT_NAME", component)
        // Certaines ROM lisent plutot l'argument de fragment des Reglages.
        putExtra(":settings:fragment_args_key", component)
        val args = Bundle()
        args.putString(":settings:fragment_args_key", component)
        putExtra(":settings:show_fragment_args", args)
    }
    val intents = listOf(
        detail,
        Intent(ACTION_ACCESSIBILITY_SETTINGS),
        Intent(ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:" + context.packageName)),
    )
    for (intent in intents) {
        try {
            context.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            return
        } catch (e: Exception) {
            Log.w("common", "FS Support : page d'accessibilite indisponible : ${intent.action}", e)
        }
    }
}

// FS Support (assistant « Ecran client ») : ouvre « Installer des applis inconnues » pour FS Support
// (MANAGE_UNKNOWN_APP_SOURCES + package:), avec repli sur la liste generale puis la fiche de l'appli.
fun startManageUnknownSources(context: Context) {
    val pkg = Uri.parse("package:" + context.packageName)
    val intents = listOf(
        Intent("android.settings.MANAGE_UNKNOWN_APP_SOURCES", pkg),
        Intent("android.settings.MANAGE_UNKNOWN_APP_SOURCES"),
        Intent(ACTION_APPLICATION_DETAILS_SETTINGS, pkg),
    )
    for (intent in intents) {
        try {
            context.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            return
        } catch (e: Exception) {
            Log.w("common", "FS Support : reglage sources inconnues indisponible : ${intent.action}", e)
        }
    }
}

class AudioReader(val bufSize: Int, private val maxFrames: Int) {
    private var currentPos = 0
    private val bufferPool: Array<ByteBuffer>

    init {
        if (maxFrames < 0 || maxFrames > 32) {
            throw Exception("Out of bounds")
        }
        if (bufSize <= 0) {
            throw Exception("Wrong bufSize")
        }
        bufferPool = Array(maxFrames) {
            ByteBuffer.allocateDirect(bufSize)
        }
    }

    private fun next() {
        currentPos++
        if (currentPos >= maxFrames) {
            currentPos = 0
        }
    }

    @RequiresApi(Build.VERSION_CODES.M)
    fun readSync(audioRecord: AudioRecord): ByteBuffer? {
        val buffer = bufferPool[currentPos]
        val res = audioRecord.read(buffer, bufSize, READ_BLOCKING)
        return if (res > 0) {
            next()
            buffer
        } else {
            null
        }
    }
}


fun getScreenSize(windowManager: WindowManager) : Pair<Int, Int>{
    var w = 0
    var h = 0
    @Suppress("DEPRECATION")
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
        val m = windowManager.maximumWindowMetrics
        w = m.bounds.width()
        h = m.bounds.height()
    } else {
        val dm = DisplayMetrics()
        windowManager.defaultDisplay.getRealMetrics(dm)
        w = dm.widthPixels
        h = dm.heightPixels
    }
    return Pair(w, h)
}

 fun translate(input: String): String {
    Log.d("common", "translate:$LOCAL_NAME")
    return FFI.translateLocale(LOCAL_NAME, input)
}
