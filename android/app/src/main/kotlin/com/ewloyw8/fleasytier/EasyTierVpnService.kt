package com.ewloyw8.fleasytier

import android.content.Intent
import android.net.VpnService
import android.os.ParcelFileDescriptor
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.os.Build
import androidx.core.app.NotificationCompat

class EasyTierVpnService : VpnService() {

    companion object {
        const val ACTION_START = "com.easytier.START_VPN"
        const val ACTION_STOP = "com.easytier.STOP_VPN"
        const val CHANNEL_ID = "easytier_vpn"
        const val NOTIFICATION_ID = 1

        var vpnFd: Int = -1
            private set
        var isRunning: Boolean = false
            private set
    }

    private var vpnInterface: ParcelFileDescriptor? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                stopVpn()
                return START_NOT_STICKY
            }
            ACTION_START, null -> {
                val ipv4 = intent?.getStringExtra("ipv4") ?: "10.0.0.1"
                val cidr = intent?.getIntExtra("cidr", 24) ?: 24
                val mtu = intent?.getIntExtra("mtu", 1300) ?: 1300
                val routes = intent?.getStringArrayListExtra("routes") ?: arrayListOf("0.0.0.0/0")
                val dns = intent?.getStringExtra("dns")

                startVpn(ipv4, cidr, mtu, routes, dns)
            }
        }
        return START_STICKY
    }

    private fun startVpn(
        ipv4: String,
        cidr: Int,
        mtu: Int,
        routes: List<String>,
        dns: String?
    ) {
        if (isRunning) return

        val builder = Builder()
            .setSession("FlEasyTier")
            .setMtu(mtu)
            .setBlocking(false)
            .addAddress(ipv4, cidr)

        // Add routes
        for (route in routes) {
            val parts = route.split("/")
            if (parts.size == 2) {
                try {
                    builder.addRoute(parts[0], parts[1].toInt())
                } catch (_: Exception) {}
            }
        }

        // DNS
        if (!dns.isNullOrEmpty()) {
            builder.addDnsServer(dns)
        }

        // Don't route our own app through VPN (avoid loops)
        try {
            builder.addDisallowedApplication(packageName)
        } catch (_: Exception) {}

        vpnInterface = builder.establish()
        if (vpnInterface == null) {
            stopSelf()
            return
        }

        vpnFd = vpnInterface!!.fd
        isRunning = true

        // Start foreground notification
        val pendingIntent = PendingIntent.getActivity(
            this, 0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE
        )
        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("FlEasyTier VPN")
            .setContentText("VPN connection active")
            .setSmallIcon(android.R.drawable.ic_lock_lock)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .build()

        startForeground(NOTIFICATION_ID, notification)

        // Notify Flutter via broadcast
        val broadcastIntent = Intent("com.easytier.VPN_STATE_CHANGED")
        broadcastIntent.putExtra("running", true)
        broadcastIntent.putExtra("fd", vpnFd)
        sendBroadcast(broadcastIntent)
    }

    private fun stopVpn() {
        vpnInterface?.close()
        vpnInterface = null
        vpnFd = -1
        isRunning = false
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()

        val broadcastIntent = Intent("com.easytier.VPN_STATE_CHANGED")
        broadcastIntent.putExtra("running", false)
        sendBroadcast(broadcastIntent)
    }

    override fun onDestroy() {
        stopVpn()
        super.onDestroy()
    }

    override fun onRevoke() {
        stopVpn()
        super.onRevoke()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "FlEasyTier VPN",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Shows when VPN is active"
            }
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(channel)
        }
    }
}
