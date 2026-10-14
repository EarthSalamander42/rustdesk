package com.carriez.flutter_hbb

/**
 * FS Support — journal de plantage envoyé à FS Solutions.
 *
 * Sur un écran géré à distance, personne ne peut lire logcat. Ce module :
 *   1. pose un gestionnaire d'exceptions non interceptées (Kotlin/Java) qui écrit la pile dans un
 *      fichier de l'appli AVANT de laisser le processus mourir ;
 *   2. au démarrage suivant, lit les sorties récentes du processus que garde Android
 *      (ActivityManager.getHistoricalProcessExitReasons, API 30+) : plantage Java, plantage natif
 *      (trace « tombstone » en API 31+, dont on garde les textes lisibles), ANR (API 30+), et aussi
 *      les arrêts pour mémoire insuffisante ou par signal, invisibles autrement ;
 *   3. joint la fin du journal Rust de l'appli (<externe>/<nom de l'appli>/Logs, fichiers .log) et la fin
 *      de logcat (lignes de l'appli seulement : Android ne montre à une appli que les siennes) ;
 *   4. envoie le tout en JSON (≤ 64 Ko) à https://api.fs-solutions.fr/fss/api/journal-plantage,
 *      en tâche de fond ; en cas d'échec le rapport reste en file et repart au démarrage suivant.
 *
 * Un envoi manuel (« Envoyer le journal à FS Solutions ») suit le même chemin, sans plantage.
 *
 * Jamais de mot de passe ni de jeton : toute ligne qui en évoque un est masquée avant l'envoi.
 * Tout est gardé par try/catch : le journal ne doit jamais être lui-même une cause de plantage.
 */

import android.app.ActivityManager
import android.app.ApplicationExitInfo
import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import org.json.JSONArray
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.InputStream
import java.io.PrintWriter
import java.io.RandomAccessFile
import java.io.StringWriter
import java.net.HttpURLConnection
import java.net.URL
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import java.util.concurrent.Executors

object FsCrashJournal {
    private const val TAG = "FsJournal"

    const val ENDPOINT = "https://api.fs-solutions.fr/fss/api/journal-plantage"

    // Plafonds (octets). Le total JSON ne dépasse jamais MAX_TOTAL.
    private const val MAX_TOTAL = 64 * 1024
    private const val MAX_TRACE = 24 * 1024
    private const val MAX_LOGCAT = 16 * 1024
    private const val MAX_RUST_LOG = 16 * 1024
    private const val MAX_DESCRIPTION = 1024
    private const val MAX_QUEUE = 6

    private const val PREFS = "fs_crash_journal"
    private const val KEY_LAST_EXIT_TS = "last_exit_ts"
    private const val KEY_ID = "fs_support_id"
    private const val KEY_UUID = "fs_support_uuid"
    // Tests e2e seulement (emulateur, prefs ecrites en root) : rapports gardes en file, jamais envoyes.
    private const val KEY_SEND_DISABLED = "envoi_desactive"

    private const val DIR_QUEUE = "fs-journal/attente"
    private const val FILE_JVM_CRASH = "fs-journal/plantage-jvm.txt"

    // Un seul fil : collecte et envois ne se chevauchent jamais.
    private val executor = Executors.newSingleThreadExecutor { r ->
        Thread(r, "fs-journal").apply { isDaemon = true }
    }

    @Volatile
    private var installed = false

    // Lignes à masquer : tout ce qui évoque un secret (mot de passe, jeton, clé…).
    private val SENSITIVE = Regex(
        "(?i)(pass(word|wd)?|mot[ _-]?de[ _-]?passe|mdp|token|jeton|secret|authori[sz]ation|bearer|api[_-]?key|cookie|otp|2fa|totp|private[_-]?key|salt)"
    )

    // ------------------------------------------------------------------------------------------
    // Démarrage du processus (MainApplication.onCreate)
    // ------------------------------------------------------------------------------------------

    /** Pose le gestionnaire d'exceptions puis, en tâche de fond, collecte et envoie. */
    fun onProcessStart(context: Context) {
        val app = context.applicationContext
        installUncaughtHandler(app)
        executor.execute {
            try {
                // Laisse le temps au réseau et à l'interface de démarrer (démarrage de l'écran).
                Thread.sleep(20_000)
                collectPending(app)
                sendQueue(app)
            } catch (e: Throwable) {
                Log.w(TAG, "FS Support journal : collecte au démarrage en échec : $e")
            }
        }
    }

    private fun installUncaughtHandler(app: Context) {
        if (installed) return
        installed = true
        val previous = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { thread, error ->
            try {
                val sw = StringWriter()
                error.printStackTrace(PrintWriter(sw))
                val text = "fil=${thread.name}\nheure=${isoNow()}\n$sw"
                val f = File(app.filesDir, FILE_JVM_CRASH)
                f.parentFile?.mkdirs()
                f.writeText(text.take(MAX_TRACE))
            } catch (ignored: Throwable) {
                // Rien : on ne doit surtout pas empêcher le traitement normal du plantage.
            }
            if (previous != null) {
                previous.uncaughtException(thread, error)
            } else {
                android.os.Process.killProcess(android.os.Process.myPid())
                System.exit(10)
            }
        }
    }

    // ------------------------------------------------------------------------------------------
    // Identité du poste (ID FS Support, uuid), transmise par l'interface Flutter
    // ------------------------------------------------------------------------------------------

    /** Mémorise l'ID et l'uuid (appelé par l'interface dès qu'elle les connaît). */
    fun rememberIdentity(context: Context, id: String?, uuid: String?) {
        try {
            val prefs = context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val e = prefs.edit()
            if (!id.isNullOrBlank() && id != prefs.getString(KEY_ID, null)) e.putString(KEY_ID, id.trim())
            if (!uuid.isNullOrBlank() && uuid != prefs.getString(KEY_UUID, null)) e.putString(KEY_UUID, uuid.trim())
            e.apply()
        } catch (e: Exception) {
            Log.w(TAG, "FS Support journal : identité non mémorisée : $e")
        }
    }

    private fun identity(context: Context): Pair<String, String> {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        var id = prefs.getString(KEY_ID, "") ?: ""
        val uuid = prefs.getString(KEY_UUID, "") ?: ""
        if (id.isBlank()) {
            id = readIdFromConfig(context)
        }
        return Pair(id, uuid)
    }

    // Repli : l'ID figure en clair dans la configuration RustDesk (<dossier>/<nom>2.toml, « id = '…' »).
    private fun readIdFromConfig(context: Context): String {
        return try {
            val shared = context.getSharedPreferences(KEY_SHARED_PREFERENCES, FlutterActivity.MODE_PRIVATE)
            val dirs = listOfNotNull(
                shared.getString(KEY_APP_DIR_CONFIG_PATH, null)?.takeIf { it.isNotBlank() }?.let { File(it) },
                context.filesDir,
                File(context.applicationInfo.dataDir, "app_flutter"),
            )
            val re = Regex("^id\\s*=\\s*['\"]([^'\"]+)['\"]", RegexOption.MULTILINE)
            for (dir in dirs) {
                val files = dir.listFiles { f -> f.isFile && f.name.endsWith("2.toml") } ?: continue
                for (f in files) {
                    val m = re.find(f.readText().take(16 * 1024)) ?: continue
                    return m.groupValues[1]
                }
            }
            ""
        } catch (e: Exception) {
            ""
        }
    }

    // ------------------------------------------------------------------------------------------
    // Collecte
    // ------------------------------------------------------------------------------------------

    /** Transforme le plantage Java mémorisé et les sorties récentes du processus en rapports en file. */
    private fun collectPending(app: Context) {
        val prefs = app.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val logcat = readLogcat()
        val rustLog = readRustLogTail(app)

        // 1. Plantage Java/Kotlin écrit par le gestionnaire d'exceptions.
        val jvmFile = File(app.filesDir, FILE_JVM_CRASH)
        var jvmTrace: String? = null
        if (jvmFile.isFile) {
            jvmTrace = try { jvmFile.readText() } catch (ignored: Exception) { null }
            jvmFile.delete()
        }

        // 2. Sorties du processus connues d'Android (API 30+).
        var lastTs = prefs.getLong(KEY_LAST_EXIT_TS, 0L)
        var newest = lastTs
        var jvmAttached = false
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            try {
                val am = app.getSystemService(ActivityManager::class.java)
                val exits = am.getHistoricalProcessExitReasons(null, 0, 16)
                // Première exécution : on ne remonte pas tout l'historique, seulement les 3 derniers jours.
                if (lastTs == 0L) lastTs = System.currentTimeMillis() - 3L * 24 * 3600 * 1000
                for (info in exits.sortedBy { it.timestamp }) {
                    if (info.timestamp <= lastTs) continue
                    if (info.timestamp > newest) newest = info.timestamp
                    val raison = reasonName(info.reason) ?: continue
                    var trace = readExitTrace(info)
                    if (info.reason == ApplicationExitInfo.REASON_CRASH && jvmTrace != null && !jvmAttached) {
                        trace = jvmTrace
                        jvmAttached = true
                    }
                    val report = buildReport(
                        app, raison, info.timestamp, info.description ?: "", trace, logcat, rustLog,
                        JSONObject().apply {
                            put("pid", info.pid)
                            put("statut", info.status)
                            put("importance", info.importance)
                            put("pss_ko", info.pss)
                            put("rss_ko", info.rss)
                            put("processus", info.processName ?: "")
                        }
                    )
                    enqueue(app, report)
                }
            } catch (e: Exception) {
                Log.w(TAG, "FS Support journal : sorties du processus illisibles : $e")
            }
        }
        if (jvmTrace != null && !jvmAttached) {
            enqueue(app, buildReport(app, "jvm", System.currentTimeMillis(), "Exception non interceptée", jvmTrace, logcat, rustLog, null))
        }
        if (newest > prefs.getLong(KEY_LAST_EXIT_TS, 0L)) {
            prefs.edit().putLong(KEY_LAST_EXIT_TS, newest).apply()
        }
    }

    // Raisons retenues : plantages, ANR, et arrêts brutaux qu'on ne verrait pas autrement.
    private fun reasonName(reason: Int): String? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return null
        return when (reason) {
            ApplicationExitInfo.REASON_CRASH -> "crash"
            ApplicationExitInfo.REASON_CRASH_NATIVE -> "crash_native"
            ApplicationExitInfo.REASON_ANR -> "anr"
            ApplicationExitInfo.REASON_LOW_MEMORY -> "low_memory"
            ApplicationExitInfo.REASON_SIGNALED -> "signaled"
            ApplicationExitInfo.REASON_INITIALIZATION_FAILURE -> "initialization_failure"
            ApplicationExitInfo.REASON_EXCESSIVE_RESOURCE_USAGE -> "excessive_resource_usage"
            else -> null
        }
    }

    // Trace de la sortie : texte pour un ANR ; « tombstone » binaire (protobuf) pour un plantage
    // natif en API 31+, dont on garde les suites de caractères lisibles (pile, message d'abandon…).
    private fun readExitTrace(info: ApplicationExitInfo): String {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return ""
        return try {
            val stream: InputStream = info.traceInputStream ?: return ""
            val bytes = stream.use { readBounded(it, 512 * 1024) }
            if (info.reason == ApplicationExitInfo.REASON_CRASH_NATIVE) {
                printableStrings(bytes)
            } else {
                String(bytes, Charsets.UTF_8)
            }
        } catch (e: Exception) {
            "trace illisible : $e"
        }
    }

    private fun readBounded(input: InputStream, max: Int): ByteArray {
        val out = ByteArrayOutputStream()
        val buf = ByteArray(8192)
        while (out.size() < max) {
            val n = input.read(buf, 0, minOf(buf.size, max - out.size()))
            if (n <= 0) break
            out.write(buf, 0, n)
        }
        return out.toByteArray()
    }

    // Équivalent de « strings » : suites d'au moins 4 caractères imprimables, une par ligne.
    internal fun printableStrings(bytes: ByteArray): String {
        val sb = StringBuilder()
        val cur = StringBuilder()
        fun flush() {
            if (cur.length >= 4) sb.append(cur).append('\n')
            cur.setLength(0)
        }
        for (b in bytes) {
            val c = b.toInt() and 0xFF
            if (c in 0x20..0x7E || c == 0x09) cur.append(c.toChar()) else flush()
        }
        flush()
        return sb.toString()
    }

    // Fin de logcat : Android ne montre à une appli que ses propres lignes (y compris celles du
    // processus précédent, mort, tant que le tampon les garde).
    private fun readLogcat(): String {
        return try {
            val p = Runtime.getRuntime().exec(arrayOf("logcat", "-d", "-t", "1500", "-v", "threadtime"))
            val bytes = p.inputStream.use { readBounded(it, 2 * 1024 * 1024) }
            try { p.destroy() } catch (ignored: Exception) {}
            String(bytes, Charsets.UTF_8)
        } catch (e: Exception) {
            "logcat illisible : $e"
        }
    }

    // Journal Rust : <getExternalFilesDir>/<nom de l'appli>/Logs/*.log (Config::log_path sur Android).
    private fun readRustLogTail(context: Context): String {
        return try {
            val roots = listOfNotNull(context.getExternalFilesDir(null), context.filesDir)
            val logs = ArrayList<File>()
            for (root in roots) {
                root.listFiles()?.forEach { appDir ->
                    val dir = File(appDir, "Logs")
                    if (dir.isDirectory) {
                        dir.walkTopDown().maxDepth(2).filter { it.isFile && it.name.endsWith(".log") }.forEach { logs.add(it) }
                    }
                }
            }
            val newest = logs.maxByOrNull { it.lastModified() } ?: return ""
            RandomAccessFile(newest, "r").use { raf ->
                val len = raf.length()
                val start = maxOf(0L, len - MAX_RUST_LOG * 2)
                raf.seek(start)
                val buf = ByteArray((len - start).toInt())
                raf.readFully(buf)
                "fichier=${newest.name}\n" + String(buf, Charsets.UTF_8)
            }
        } catch (e: Exception) {
            "journal Rust illisible : $e"
        }
    }

    // ------------------------------------------------------------------------------------------
    // Rapport
    // ------------------------------------------------------------------------------------------

    /** Masque les lignes qui évoquent un secret. */
    internal fun sanitize(text: String): String {
        if (text.isEmpty()) return text
        return text.lineSequence().joinToString("\n") { line ->
            if (SENSITIVE.containsMatchIn(line)) "[ligne masquée : donnée sensible possible]" else line
        }
    }

    // Garde la fin (journaux) ou le début (traces), proprement, avec la mention de la coupe.
    internal fun truncate(text: String, maxBytes: Int, keepTail: Boolean): String {
        val bytes = text.toByteArray(Charsets.UTF_8)
        if (bytes.size <= maxBytes) return text
        val omitted = bytes.size - maxBytes
        val marker = "[… $omitted octets tronqués …]"
        val budget = maxOf(0, maxBytes - marker.toByteArray(Charsets.UTF_8).size - 2)
        return if (keepTail) {
            var s = String(bytes, bytes.size - budget, budget, Charsets.UTF_8)
            // Repart d'un début de ligne propre.
            val nl = s.indexOf('\n')
            if (nl in 0..512) s = s.substring(nl + 1)
            "$marker\n$s"
        } else {
            var s = String(bytes, 0, budget, Charsets.UTF_8)
            val nl = s.lastIndexOf('\n')
            if (nl > budget - 512 && nl > 0) s = s.substring(0, nl)
            "$s\n$marker"
        }
    }

    private fun buildReport(
        context: Context,
        raison: String,
        timestamp: Long,
        description: String,
        trace: String,
        logcat: String,
        rustLog: String,
        details: JSONObject?,
    ): JSONObject {
        val (id, uuid) = identity(context)
        var version = ""
        var versionCode = 0L
        try {
            val pi = context.packageManager.getPackageInfo(context.packageName, 0)
            version = pi.versionName ?: ""
            @Suppress("DEPRECATION")
            versionCode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) pi.longVersionCode else pi.versionCode.toLong()
        } catch (ignored: Exception) {}
        val report = JSONObject()
        report.put("fs_support_id", id)
        report.put("uuid", uuid)
        report.put("version", version)
        report.put("version_code", versionCode)
        report.put("plateforme", "android")
        report.put("modele", Build.MODEL ?: "")
        report.put("fabricant", Build.MANUFACTURER ?: "")
        report.put("appareil", Build.DEVICE ?: "")
        report.put("materiel", Build.HARDWARE ?: "")
        report.put("android_version", Build.VERSION.RELEASE ?: "")
        report.put("sdk", Build.VERSION.SDK_INT)
        report.put("type_rom", Build.TYPE ?: "")
        report.put("ecran_client", FsClientScreen.isEnabled(context))
        report.put("raison", raison)
        report.put("horodatage", iso(timestamp))
        report.put("description", sanitize(description).take(MAX_DESCRIPTION))
        if (details != null) report.put("details", details)
        // Parts volumineuses, nettoyées puis bornées ; on réduit encore si le total dépasse 64 Ko.
        var traceMax = MAX_TRACE
        var logcatMax = MAX_LOGCAT
        var rustMax = MAX_RUST_LOG
        val cleanTrace = sanitize(trace)
        val cleanLogcat = sanitize(logcat)
        val cleanRust = sanitize(rustLog)
        for (attempt in 0 until 6) {
            report.put("trace", truncate(cleanTrace, traceMax, keepTail = false))
            report.put("logcat", truncate(cleanLogcat, logcatMax, keepTail = true))
            report.put("journal_rust", truncate(cleanRust, rustMax, keepTail = true))
            if (report.toString().toByteArray(Charsets.UTF_8).size <= MAX_TOTAL - 512) break
            traceMax /= 2
            logcatMax /= 2
            rustMax /= 2
        }
        return report
    }

    // ------------------------------------------------------------------------------------------
    // File d'attente et envoi
    // ------------------------------------------------------------------------------------------

    private fun queueDir(context: Context): File = File(context.filesDir, DIR_QUEUE).apply { mkdirs() }

    private fun enqueue(context: Context, report: JSONObject) {
        try {
            val dir = queueDir(context)
            val f = File(dir, "rapport-${System.currentTimeMillis()}-${(Math.random() * 1e6).toInt()}.json")
            f.writeText(report.toString())
            // File bornée : on garde les plus récents.
            val files = dir.listFiles()?.sortedBy { it.name } ?: return
            if (files.size > MAX_QUEUE) files.take(files.size - MAX_QUEUE).forEach { it.delete() }
            Log.i(TAG, "FS Support journal : rapport « ${report.optString("raison")} » mis en file")
        } catch (e: Exception) {
            Log.w(TAG, "FS Support journal : rapport non écrit : $e")
        }
    }

    // Envoie les rapports en file, du plus ancien au plus récent ; s'arrête au premier échec réseau.
    private fun sendQueue(context: Context): Pair<Int, String?> {
        if (context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getBoolean(KEY_SEND_DISABLED, false)) {
            Log.i(TAG, "FS Support journal : envoi desactive (test), rapports gardes en file")
            return Pair(0, "envoi désactivé")
        }
        val files = queueDir(context).listFiles()?.sortedBy { it.name } ?: return Pair(0, null)
        var sent = 0
        for (f in files) {
            val body = try { JSONObject(f.readText()) } catch (ignored: Exception) { f.delete(); continue }
            // L'identité a pu être connue après la mise en file.
            if (body.optString("fs_support_id").isBlank() || body.optString("uuid").isBlank()) {
                val (id, uuid) = identity(context)
                if (body.optString("fs_support_id").isBlank()) body.put("fs_support_id", id)
                if (body.optString("uuid").isBlank()) body.put("uuid", uuid)
            }
            val err = post(body)
            if (err == null) {
                f.delete()
                sent++
            } else if (err == "HTTP 400" || err == "HTTP 413" || err == "HTTP 415" || err == "HTTP 422") {
                // Refus définitif (rapport invalide) : inutile de le renvoyer sans fin.
                Log.w(TAG, "FS Support journal : rapport refusé ($err), supprimé")
                f.delete()
            } else {
                Log.w(TAG, "FS Support journal : envoi en échec ($err), nouvel essai au prochain démarrage")
                return Pair(sent, err)
            }
        }
        if (sent > 0) Log.i(TAG, "FS Support journal : $sent rapport(s) envoyé(s)")
        return Pair(sent, null)
    }

    /** POST JSON ; null si accepté (2xx), sinon le motif de l'échec. */
    private fun post(body: JSONObject): String? {
        var conn: HttpURLConnection? = null
        return try {
            body.put("envoye_le", isoNow())
            val bytes = body.toString().toByteArray(Charsets.UTF_8)
            conn = (URL(ENDPOINT).openConnection() as HttpURLConnection).apply {
                requestMethod = "POST"
                connectTimeout = 15_000
                readTimeout = 20_000
                doOutput = true
                setRequestProperty("Content-Type", "application/json; charset=utf-8")
                setRequestProperty("User-Agent", "FS-Support-Android")
                setFixedLengthStreamingMode(bytes.size)
            }
            conn.outputStream.use { it.write(bytes) }
            val code = conn.responseCode
            if (code in 200..299) null else "HTTP $code"
        } catch (e: Exception) {
            e.javaClass.simpleName + ": " + (e.message ?: "")
        } finally {
            try { conn?.disconnect() } catch (ignored: Exception) {}
        }
    }

    // ------------------------------------------------------------------------------------------
    // Envoi manuel (bouton « Envoyer le journal à FS Solutions »)
    // ------------------------------------------------------------------------------------------

    /**
     * Envoie tout de suite un rapport « manuel » (journaux actuels + dernières sorties connues),
     * puis les rapports encore en file. [done] reçoit (ok, message) sur le fil principal.
     */
    fun sendManual(context: Context, id: String?, uuid: String?, done: (Boolean, String) -> Unit) {
        val app = context.applicationContext
        rememberIdentity(app, id, uuid)
        executor.execute {
            var ok = false
            var message = ""
            try {
                collectPending(app)
                val summary = StringBuilder("Envoi manuel depuis l'appareil.")
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    try {
                        val am = app.getSystemService(ActivityManager::class.java)
                        val exits = am.getHistoricalProcessExitReasons(null, 0, 5)
                        val arr = JSONArray()
                        for (info in exits) arr.put("${iso(info.timestamp)} raison=${info.reason} ${info.description ?: ""}")
                        summary.append(" Dernières sorties : ").append(arr.toString())
                    } catch (ignored: Exception) {}
                }
                enqueue(app, buildReport(app, "manuel", System.currentTimeMillis(), summary.toString(), "", readLogcat(), readRustLogTail(app), null))
                val (sent, err) = sendQueue(app)
                if (err == null) {
                    ok = true
                    message = if (sent > 1) "Journal envoyé à FS Solutions ($sent rapports)." else "Journal envoyé à FS Solutions."
                } else {
                    message = "Envoi impossible pour l'instant ($err). Nouvel essai automatique au prochain démarrage."
                }
            } catch (e: Throwable) {
                message = "Envoi impossible : $e"
            }
            Handler(Looper.getMainLooper()).post { done(ok, message) }
        }
    }

    // ------------------------------------------------------------------------------------------

    private fun iso(ts: Long): String {
        val f = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.ROOT)
        f.timeZone = TimeZone.getTimeZone("UTC")
        return f.format(Date(ts))
    }

    private fun isoNow(): String = iso(System.currentTimeMillis())
}
