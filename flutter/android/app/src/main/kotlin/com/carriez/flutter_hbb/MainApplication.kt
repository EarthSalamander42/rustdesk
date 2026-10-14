package com.carriez.flutter_hbb

import android.app.Application
import android.util.Log
import ffi.FFI

class MainApplication : Application() {
    companion object {
        private const val TAG = "MainApplication"
    }

    override fun onCreate() {
        super.onCreate()
        Log.d(TAG, "App start")
        // FS Support : journal de plantage (gestionnaire d'exceptions + envoi des sorties récentes).
        try {
            FsCrashJournal.onProcessStart(this)
        } catch (e: Throwable) {
            Log.w(TAG, "FS Support : journal de plantage indisponible : $e")
        }
        FFI.onAppStart(applicationContext)
    }
}
