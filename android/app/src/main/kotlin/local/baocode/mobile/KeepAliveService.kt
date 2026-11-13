package local.baocode.mobile

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.drawable.Icon
import android.os.Build
import android.os.IBinder
import android.util.Log

/**
 * 只负责前台通知与系统可见性。引擎、Dart 与连接都在 [BackgroundHost]，这里不持有任何一个。
 * 类型是 remoteMessaging（手机与电脑之间的消息同步）；不自启、不粘性重启。
 */
class KeepAliveService : Service() {
    // 这个实例服务的那次启动；onDestroy 只结束自己的启动，不误伤随后发起的新一次。
    private var token = 0L

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            BackgroundHost.serviceEnded(token)
            stopSelf()
            return START_NOT_STICKY
        }
        val title = intent?.getStringExtra(EXTRA_TITLE)
        val body = intent?.getStringExtra(EXTRA_BODY)
        val stopLabel = intent?.getStringExtra(EXTRA_STOP_LABEL)
        val requested = intent?.getLongExtra(EXTRA_TOKEN, 0L) ?: 0L
        if (title == null || body == null || stopLabel == null || requested == 0L) {
            // startForegroundService 之后必须先进前台再停，否则系统会让应用崩溃。
            try {
                startForeground(NOTIFICATION_ID, buildNotification("YCode", "", "Stop"))
                stopForeground(STOP_FOREGROUND_REMOVE)
            } catch (error: RuntimeException) {
                Log.w(TAG, "foreground start rejected", error)
            }
            stopSelf()
            return START_NOT_STICKY
        }
        token = requested
        try {
            val notification = buildNotification(title, body, stopLabel)
            if (Build.VERSION.SDK_INT >= 34) {
                startForeground(NOTIFICATION_ID, notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_REMOTE_MESSAGING)
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
        } catch (error: RuntimeException) {
            Log.w(TAG, "foreground start rejected", error)
            BackgroundHost.serviceFailed(requested)
            stopSelf()
            return START_NOT_STICKY
        }
        // 已被取消、超时或被新的启动取代的迟到启动：通知已显示过，立即撤掉并停止，不空跑。
        if (!BackgroundHost.serviceForeground(requested)) {
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
        }
        return START_NOT_STICKY
    }

    // Android 15+ 超时回调；remoteMessaging 没有时限，仅作防御。
    override fun onTimeout(startId: Int, fgsType: Int) {
        BackgroundHost.serviceEnded(token)
        stopSelf()
    }

    override fun onDestroy() {
        BackgroundHost.serviceEnded(token)
        super.onDestroy()
    }

    private fun buildNotification(title: String, body: String, stopLabel: String): Notification {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val builder = if (Build.VERSION.SDK_INT >= 26) {
            manager.createNotificationChannel(
                NotificationChannel(CHANNEL, title, NotificationManager.IMPORTANCE_LOW))
            Notification.Builder(this, CHANNEL)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        builder.setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle(title)
            .setContentText(body)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setShowWhen(false)
            .setCategory(Notification.CATEGORY_SERVICE)
        val stop = PendingIntent.getService(this, 0,
            Intent(this, KeepAliveService::class.java).setAction(ACTION_STOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        builder.addAction(Notification.Action.Builder(
            Icon.createWithResource(this, android.R.drawable.ic_menu_close_clear_cancel),
            stopLabel, stop).build())
        packageManager.getLaunchIntentForPackage(packageName)?.let { launch ->
            launch.addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            builder.setContentIntent(PendingIntent.getActivity(this, 0, launch,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE))
        }
        return builder.build()
    }

    companion object {
        const val EXTRA_TITLE = "title"
        const val EXTRA_BODY = "body"
        const val EXTRA_STOP_LABEL = "stopLabel"
        const val EXTRA_TOKEN = "token"
        private const val ACTION_STOP = "local.baocode.mobile.action.STOP_KEEP_ALIVE"
        private const val CHANNEL = "baocode.mobile.background"
        private const val NOTIFICATION_ID = 47130
        private const val TAG = "KeepAliveService"
    }
}
