package com.example.avtonet_app

import android.os.Bundle
import android.util.Log
import androidx.work.WorkManager
import androidx.work.WorkInfo
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executor

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.avtonet_app/forensics"

    override fun configureFlutterEngine(flutterEngine: io.flutter.embedding.engine.FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "runForensicCheck") {
                performForensicScan()
                result.success(null)
            } else {
                result.notImplemented()
            }
        }
    }

    private fun performForensicScan() {
        val workName = "avtonet_periodic_scan_v3"
        val immediateExecutor = Executor { it.run() }
        
        Log.d("WORKER_FORENSIC", "[WORKER_FORENSIC] --- DB CHECK START (Post-Registration) ---")

        try {
            val workManager = WorkManager.getInstance(applicationContext)
            
            val uniqueWorkInfos = workManager.getWorkInfosForUniqueWork(workName)
            uniqueWorkInfos.addListener(Runnable {
                try {
                    val infos = uniqueWorkInfos.get()
                    if (infos.isNullOrEmpty()) {
                        Log.d("WORKER_FORENSIC", "[WORKER_FORENSIC] RESULT = NOT_FOUND for unique name '$workName'")
                    } else {
                        Log.d("WORKER_FORENSIC", "[WORKER_FORENSIC] WORK COUNT = ${infos.size}")
                        for (info in infos) {
                            Log.d("WORKER_FORENSIC", "[WORKER_FORENSIC] WORK FOUND")
                            Log.d("WORKER_FORENSIC", "[WORKER_FORENSIC] ID = ${info.id}")
                            Log.d("WORKER_FORENSIC", "[WORKER_FORENSIC] STATE = ${info.state}")
                            Log.d("WORKER_FORENSIC", "[WORKER_FORENSIC] RUN ATTEMPT COUNT = ${info.runAttemptCount}")
                            Log.d("WORKER_FORENSIC", "[WORKER_FORENSIC] TAGS = ${info.tags}")
                            Log.d("WORKER_FORENSIC", "[WORKER_FORENSIC] CONSTRAINTS = ${info.constraints}")
                            Log.d("WORKER_FORENSIC", "[WORKER_FORENSIC] NEXT RUN ATTEMPT (Internal) = ${info.nextScheduleTimeMillis}")
                        }
                    }
                    Log.d("WORKER_FORENSIC", "[WORKER_FORENSIC] --- DB CHECK END ---")
                } catch (e: Exception) {
                    Log.e("WORKER_FORENSIC", "[WORKER_FORENSIC] ERROR in diagnostic scan: ${e.message}")
                }
            }, immediateExecutor)

        } catch (e: Exception) {
            Log.e("WORKER_FORENSIC", "[WORKER_FORENSIC] WorkManager access error: ${e.message}")
        }
    }
}
