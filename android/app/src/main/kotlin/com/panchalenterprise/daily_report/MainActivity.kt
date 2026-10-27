package com.panchalenterprise.daily_report

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInstaller
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Self-update: the app installs its own new version (downloaded from
        // the website). Android only accepts it when it is signed with the
        // same key as the installed app.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "pe/update")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "canInstall" -> result.success(
                        Build.VERSION.SDK_INT < Build.VERSION_CODES.O ||
                            packageManager.canRequestPackageInstalls()
                    )
                    "openSettings" -> {
                        startActivity(
                            Intent(
                                Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                                Uri.parse("package:$packageName")
                            )
                        )
                        result.success(null)
                    }
                    "install" -> {
                        val path = call.argument<String>("path")
                        // Only the file this app downloaded into its own cache.
                        val file = path?.let { File(it) }
                        if (file == null || !file.exists() ||
                            file.canonicalPath != File(cacheDir, "pe_update.apk").canonicalPath
                        ) {
                            result.error("INSTALL", "update file missing", null)
                        } else {
                            try {
                                install(file)
                                result.success("started")
                            } catch (e: Exception) {
                                result.error("INSTALL", e.message, null)
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun install(apk: File) {
        val installer = packageManager.packageInstaller
        val params = PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL)
        params.setAppPackageName(packageName)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            // After the first self-update, later updates need no tap at all.
            params.setRequireUserAction(PackageInstaller.SessionParams.USER_ACTION_NOT_REQUIRED)
        }
        val id = installer.createSession(params)
        installer.openSession(id).use { session ->
            session.openWrite("base.apk", 0, apk.length()).use { out ->
                apk.inputStream().use { it.copyTo(out) }
                session.fsync(out)
            }
            val flags = PendingIntent.FLAG_UPDATE_CURRENT or
                (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) PendingIntent.FLAG_MUTABLE else 0)
            val pending = PendingIntent.getBroadcast(
                this, id, Intent(this, UpdateReceiver::class.java), flags
            )
            session.commit(pending.intentSender)
        }
    }
}

/// Result of the install. Only Android's installer reaches it, through this
/// app's own PendingIntent (not exported, so no other app can). Shows
/// Android's "Update this app?" box when needed (only the first time).
/// Android closes the app while it updates and does not let it open itself
/// again, so a "tap to open" message is shown instead.
class UpdateReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.getIntExtra(PackageInstaller.EXTRA_STATUS, -999)) {
            PackageInstaller.STATUS_PENDING_USER_ACTION -> {
                val confirm: Intent? = if (Build.VERSION.SDK_INT >= 33) {
                    intent.getParcelableExtra(Intent.EXTRA_INTENT, Intent::class.java)
                } else {
                    @Suppress("DEPRECATION")
                    intent.getParcelableExtra(Intent.EXTRA_INTENT)
                }
                if (confirm != null) {
                    confirm.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    context.startActivity(confirm)
                }
            }
            PackageInstaller.STATUS_SUCCESS -> {
                try {
                    tellUpdated(context)
                } catch (_: Exception) {
                }
            }
        }
    }

    private fun tellUpdated(context: Context) {
        val launch = context.packageManager.getLaunchIntentForPackage(context.packageName) ?: return
        launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        val open = PendingIntent.getActivity(context, 0, launch, PendingIntent.FLAG_IMMUTABLE)
        val nm = context.getSystemService(NotificationManager::class.java)
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            nm.createNotificationChannel(
                NotificationChannel("updates", "App updates", NotificationManager.IMPORTANCE_HIGH)
            )
            Notification.Builder(context, "updates")
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(context).setPriority(Notification.PRIORITY_HIGH)
        }
        val n = builder
            .setSmallIcon(android.R.drawable.stat_sys_download_done)
            .setContentTitle("Daily Report is updated")
            .setContentText("Tap here to open it.")
            .setContentIntent(open)
            .setAutoCancel(true)
            .build()
        nm.notify(1, n)
    }
}
