package com.carriez.flutter_hbb

/**
 * FS Support — Mise a jour automatique de l'appli (mode « Ecran client »).
 *
 * Telecharge l'APK FS Support servi par api.fs-solutions.fr puis lance l'installateur systeme.
 * L'installateur est ensuite valide tout seul par le service d'accessibilite (InputService), mais
 * UNIQUEMENT si la fenetre mentionne « FS Support » et seulement dans la fenetre de temps ouverte
 * ici (FsClientScreen.markInstallConsentWindow). Au relancement, BootReceiver (ACTION_MY_PACKAGE_REPLACED)
 * redemarre le service et la capture.
 *
 * Gardes :
 *   - telechargement seulement en https depuis api.fs-solutions.fr (meme regle que le Rust/Dart) ;
 *   - on n'installe un APK que si son paquet est le notre (fr.fssolutions.support) ;
 *   - fichier pose dans getExternalFilesDir("updates"), expose par le FileProvider de l'appli.
 * Tout est garde par try/catch : jamais de plantage, seulement des Log.i / Log.w.
 */

import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.util.Log
import androidx.core.content.FileProvider
import java.io.File
import java.io.FileOutputStream
import java.net.HttpURLConnection
import java.net.URL
import kotlin.concurrent.thread

object FsSelfUpdate {
    private const val logTag = "FsSelfUpdate"

    // Seul hote accepte pour le telechargement d'une mise a jour (meme regle que fs_support.rs / Dart).
    private const val ALLOWED_HOST = "api.fs-solutions.fr"

    private const val UPDATES_DIR = "updates"
    private const val APK_NAME = "fs-support-update.apk"

    /** L'appli peut-elle installer une appli inconnue (etape « Mises a jour automatiques » de l'assistant) ? */
    fun canInstallUnknown(context: Context): Boolean {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.packageManager.canRequestPackageInstalls()
            } else {
                true // avant Android 8 : pas de reglage par appli
            }
        } catch (e: Exception) {
            Log.w(logTag, "FS Support : verification installation inconnue impossible : $e")
            false
        }
    }

    /**
     * Telecharge l'APK depuis [url] (https://api.fs-solutions.fr/...) puis lance l'installateur.
     * Travaille sur un fil dedie ; [onResult] recoit true si l'installateur a ete lance.
     */
    fun downloadAndInstall(context: Context, url: String, onResult: ((Boolean) -> Unit)? = null) {
        thread(name = "FsSelfUpdate") {
            val ok = try {
                val file = download(context, url)
                if (file != null) installFromFile(context, file) else false
            } catch (e: Exception) {
                Log.w(logTag, "FS Support : mise a jour automatique en echec : $e")
                false
            }
            onResult?.invoke(ok)
        }
    }

    private fun download(context: Context, url: String): File? {
        val uri = try {
            Uri.parse(url)
        } catch (e: Exception) {
            Log.w(logTag, "FS Support : URL de mise a jour invalide : $e")
            return null
        }
        if (!"https".equals(uri.scheme, ignoreCase = true) ||
            !ALLOWED_HOST.equals(uri.host, ignoreCase = true)
        ) {
            Log.w(logTag, "FS Support : URL de mise a jour refusee (hors https://$ALLOWED_HOST) : $url")
            return null
        }
        val dir = File(context.getExternalFilesDir(null) ?: context.filesDir, UPDATES_DIR)
        if (!dir.exists() && !dir.mkdirs()) {
            Log.w(logTag, "FS Support : dossier de mise a jour introuvable : $dir")
            return null
        }
        val target = File(dir, APK_NAME)
        var connection: HttpURLConnection? = null
        try {
            connection = (URL(url).openConnection() as HttpURLConnection).apply {
                connectTimeout = 30_000
                readTimeout = 60_000
                instanceFollowRedirects = true
                requestMethod = "GET"
            }
            val code = connection.responseCode
            if (code != HttpURLConnection.HTTP_OK) {
                Log.w(logTag, "FS Support : telechargement refuse (HTTP $code)")
                return null
            }
            connection.inputStream.use { input ->
                FileOutputStream(target).use { output ->
                    input.copyTo(output)
                }
            }
            Log.i(logTag, "FS Support : mise a jour telechargee (${target.length()} octets)")
            return target
        } catch (e: Exception) {
            Log.w(logTag, "FS Support : telechargement de la mise a jour en echec : $e")
            return null
        } finally {
            connection?.disconnect()
        }
    }

    /**
     * Lance l'installateur systeme pour [file], apres avoir verifie que c'est bien un APK FS Support.
     * Ouvre la fenetre d'auto-validation de l'installateur.
     */
    fun installFromFile(context: Context, file: File): Boolean {
        if (!file.isFile) {
            Log.w(logTag, "FS Support : APK de mise a jour absent : $file")
            return false
        }
        // L'APK doit etre celui de FS Support : on ne lance jamais l'installateur pour autre chose.
        val parsed = try {
            context.packageManager.getPackageArchiveInfo(file.absolutePath, 0)
        } catch (e: Exception) {
            Log.w(logTag, "FS Support : lecture de l'APK impossible : $e")
            null
        }
        if (parsed == null || parsed.packageName != context.packageName) {
            Log.w(logTag, "FS Support : APK ignore (paquet ${parsed?.packageName} != ${context.packageName})")
            return false
        }
        val uri = try {
            FileProvider.getUriForFile(context, context.packageName + ".fileprovider", file)
        } catch (e: Exception) {
            Log.w(logTag, "FS Support : FileProvider indisponible : $e")
            return false
        }
        val intent = Intent(Intent.ACTION_INSTALL_PACKAGE).apply {
            data = uri
            setDataAndType(uri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            putExtra(Intent.EXTRA_NOT_UNKNOWN_SOURCE, true)
            putExtra(Intent.EXTRA_RETURN_RESULT, false)
        }
        return try {
            // La fenetre de l'installateur va s'ouvrir : on l'autorise a etre validee automatiquement.
            FsClientScreen.markInstallConsentWindow()
            context.startActivity(intent)
            Log.i(logTag, "FS Support : installateur de mise a jour lance")
            true
        } catch (e: Exception) {
            Log.w(logTag, "FS Support : lancement de l'installateur en echec : $e")
            FsClientScreen.clearInstallConsentWindow()
            false
        }
    }
}
