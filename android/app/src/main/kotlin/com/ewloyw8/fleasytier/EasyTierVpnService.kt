package com.ewloyw8.fleasytier

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import androidx.core.app.NotificationCompat
import com.easytier.jni.EasyTierJNI
import org.json.JSONObject
import kotlin.concurrent.thread

class EasyTierVpnService : VpnService() {

    data class StartSpec(
        val configId: String,
        val instanceName: String,
        val configToml: String,
        val fallbackIpv4: String,
        val fallbackRoutes: List<String>,
        val mtu: Int,
        val dns: String?,
    )

    data class RuntimeSnapshot(
        val running: Boolean,
        val errorMessage: String?,
        val virtualIpv4Cidr: String?,
        val proxyCidrs: List<String>,
    )

    companion object {
        const val ACTION_START = "com.ewloyw8.START_VPN"
        const val ACTION_STOP = "com.ewloyw8.STOP_VPN"
        private const val CHANNEL_ID = "easytier_vpn"
        private const val NOTIFICATION_ID = 1
        private const val PREFS = "fleasytier_android_service"
        private const val KEY_CONFIG_ID = "config_id"
        private const val KEY_INSTANCE_NAME = "instance_name"
        private const val KEY_CONFIG_TOML = "config_toml"
        private const val KEY_FALLBACK_IPV4 = "fallback_ipv4"
        private const val KEY_FALLBACK_ROUTES = "fallback_routes"
        private const val KEY_MTU = "mtu"
        private const val KEY_DNS = "dns"
        private const val POLL_INTERVAL_MS = 3000L

        @Volatile
        private var activeConfigId: String? = null

        @Volatile
        private var activeInstanceName: String? = null

        @Volatile
        private var lastErrorMessage: String? = null

        @Volatile
        private var lastInfoJson: String? = null

        @Volatile
        private var networkRunning: Boolean = false

        fun getStatus(): Map<String, Any?> =
            hashMapOf(
                "running" to networkRunning,
                "configId" to activeConfigId,
                "instanceName" to activeInstanceName,
                "errorMessage" to lastErrorMessage,
                "infoJson" to lastInfoJson,
            )
    }

    private val stateLock = Any()
    private var vpnInterface: ParcelFileDescriptor? = null
    private var worker: Thread? = null
    private var currentSpec: StartSpec? = null
    private var currentIpv4: String? = null
    private var currentRoutes: List<String> = emptyList()

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                stopManagedNetwork(clearSavedState = true, stopService = true)
                return START_NOT_STICKY
            }
        }

        val spec = parseStartSpec(intent) ?: restoreStartSpec()
        if (spec == null) {
            stopManagedNetwork(clearSavedState = true, stopService = true)
            return START_NOT_STICKY
        }

        startForeground(
            NOTIFICATION_ID,
            buildNotification(
                title = "FlEasyTier",
                text = "Starting ${spec.instanceName}",
            ),
        )
        startManagedNetwork(spec)
        return START_STICKY
    }

    override fun onDestroy() {
        stopManagedNetwork(clearSavedState = false, stopService = false)
        super.onDestroy()
    }

    override fun onRevoke() {
        stopManagedNetwork(clearSavedState = true, stopService = true)
        super.onRevoke()
    }

    private fun startManagedNetwork(spec: StartSpec) {
        synchronized(stateLock) {
            val currentWorker = worker
            if (currentWorker?.isAlive == true &&
                currentSpec?.configId == spec.configId &&
                currentSpec?.instanceName == spec.instanceName
            ) {
                return
            }

            stopManagedNetwork(clearSavedState = false, stopService = false)
            persistStartSpec(spec)
            currentSpec = spec
            activeConfigId = spec.configId
            activeInstanceName = spec.instanceName
            lastErrorMessage = null
            lastInfoJson = null
            networkRunning = false
            currentIpv4 = null
            currentRoutes = emptyList()

            worker = thread(start = true, name = "FlEasyTier-AndroidService") {
                runManagedNetwork(spec)
            }
        }
    }

    private fun runManagedNetwork(spec: StartSpec) {
        try {
            val result = EasyTierJNI.runNetworkInstance(spec.configToml)
            if (result != 0) {
                throw IllegalStateException(
                    EasyTierJNI.getLastError() ?: "Failed to start EasyTier instance",
                )
            }

            networkRunning = true
            updateNotification("FlEasyTier", "Connecting ${spec.instanceName}")

            while (!Thread.currentThread().isInterrupted &&
                currentSpec?.configId == spec.configId
            ) {
                val infosJson = EasyTierJNI.collectNetworkInfos(16)
                lastInfoJson = infosJson

                val snapshot = parseRuntimeSnapshot(infosJson, spec.instanceName)
                if (snapshot != null) {
                    networkRunning = snapshot.running
                    if (!snapshot.errorMessage.isNullOrBlank()) {
                        lastErrorMessage = snapshot.errorMessage
                    }

                    if (snapshot.running) {
                        val effectiveIpv4 = snapshot.virtualIpv4Cidr ?: spec.fallbackIpv4
                        val effectiveRoutes =
                            if (snapshot.proxyCidrs.isNotEmpty()) {
                                snapshot.proxyCidrs
                            } else {
                                spec.fallbackRoutes
                            }

                        ensureVpnInterface(
                            instanceName = spec.instanceName,
                            ipv4Cidr = effectiveIpv4,
                            routes = effectiveRoutes,
                            mtu = spec.mtu,
                            dns = spec.dns,
                        )
                        updateNotification(
                            "FlEasyTier",
                            "${spec.instanceName} · ${effectiveIpv4.substringBefore('/')}",
                        )
                    } else {
                        closeVpnInterface()
                    }
                }

                Thread.sleep(POLL_INTERVAL_MS)
            }
        } catch (e: InterruptedException) {
            Thread.currentThread().interrupt()
        } catch (t: Throwable) {
            val typeName = t::class.java.name
            val detail = t.message?.takeIf { it.isNotBlank() } ?: t.toString()
            lastErrorMessage = "$typeName: $detail"
            networkRunning = false
            updateNotification("FlEasyTier", "Network stopped: ${lastErrorMessage ?: "error"}")
        } finally {
            closeVpnInterface()
            try {
                EasyTierJNI.stopAllInstances()
            } catch (_: Throwable) {
            }
        }
    }

    private fun stopManagedNetwork(clearSavedState: Boolean, stopService: Boolean) {
        synchronized(stateLock) {
            worker?.interrupt()
            worker = null
            currentSpec = null
            networkRunning = false
            closeVpnInterface()
            try {
                EasyTierJNI.stopAllInstances()
            } catch (_: Throwable) {
            }
            if (clearSavedState) {
                clearSavedState()
                activeConfigId = null
                activeInstanceName = null
                lastInfoJson = null
            }
            if (stopService) {
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
            }
        }
    }

    private fun ensureVpnInterface(
        instanceName: String,
        ipv4Cidr: String,
        routes: List<String>,
        mtu: Int,
        dns: String?,
    ) {
        synchronized(stateLock) {
            if (vpnInterface != null && currentIpv4 == ipv4Cidr && currentRoutes == routes) {
                return
            }

            closeVpnInterface()

            val (ipv4, cidr) = parseCidr(ipv4Cidr)
            val effectiveRoutes = if (routes.isEmpty()) listOf("0.0.0.0/0") else routes
            val builder = Builder()
                .setSession("FlEasyTier")
                .setMtu(mtu)
                .setBlocking(false)
                .addAddress(ipv4, cidr)

            for (route in effectiveRoutes) {
                try {
                    val (routeIp, routeCidr) = parseCidr(route)
                    builder.addRoute(routeIp, routeCidr)
                } catch (_: Throwable) {
                }
            }

            if (!dns.isNullOrBlank()) {
                builder.addDnsServer(dns)
            }

            try {
                builder.addDisallowedApplication(packageName)
            } catch (_: Throwable) {
            }

            val established = builder.establish()
                ?: throw IllegalStateException("Failed to create Android VPN interface")
            val fd = established.fd
            val result = EasyTierJNI.setTunFd(instanceName, fd)
            if (result != 0) {
                established.close()
                throw IllegalStateException(
                    EasyTierJNI.getLastError() ?: "Failed to attach TUN fd",
                )
            }

            vpnInterface = established
            currentIpv4 = ipv4Cidr
            currentRoutes = effectiveRoutes
        }
    }

    private fun closeVpnInterface() {
        synchronized(stateLock) {
            try {
                vpnInterface?.close()
            } catch (_: Throwable) {
            }
            vpnInterface = null
            currentIpv4 = null
            currentRoutes = emptyList()
        }
    }

    private fun parseStartSpec(intent: Intent?): StartSpec? {
        val actualIntent = intent ?: return null
        val configId = actualIntent.getStringExtra("configId") ?: return null
        val instanceName = actualIntent.getStringExtra("instanceName") ?: return null
        val configToml = actualIntent.getStringExtra("configToml") ?: return null
        val fallbackIpv4 = actualIntent.getStringExtra("fallbackIpv4") ?: "10.0.0.1/24"
        val fallbackRoutes = actualIntent.getStringArrayListExtra("fallbackRoutes")?.toList()
            ?: listOf("0.0.0.0/0")
        val mtu = actualIntent.getIntExtra("mtu", 1300)
        val dns = actualIntent.getStringExtra("dns")
        return StartSpec(
            configId = configId,
            instanceName = instanceName,
            configToml = configToml,
            fallbackIpv4 = fallbackIpv4,
            fallbackRoutes = fallbackRoutes,
            mtu = mtu,
            dns = dns,
        )
    }

    private fun restoreStartSpec(): StartSpec? {
        val prefs = getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val configId = prefs.getString(KEY_CONFIG_ID, null) ?: return null
        val instanceName = prefs.getString(KEY_INSTANCE_NAME, null) ?: return null
        val configToml = prefs.getString(KEY_CONFIG_TOML, null) ?: return null
        val fallbackIpv4 = prefs.getString(KEY_FALLBACK_IPV4, null) ?: "10.0.0.1/24"
        val fallbackRoutes = prefs.getStringSet(KEY_FALLBACK_ROUTES, null)?.toList()
            ?: listOf("0.0.0.0/0")
        val mtu = prefs.getInt(KEY_MTU, 1300)
        val dns = prefs.getString(KEY_DNS, null)
        return StartSpec(
            configId = configId,
            instanceName = instanceName,
            configToml = configToml,
            fallbackIpv4 = fallbackIpv4,
            fallbackRoutes = fallbackRoutes,
            mtu = mtu,
            dns = dns,
        )
    }

    private fun persistStartSpec(spec: StartSpec) {
        getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_CONFIG_ID, spec.configId)
            .putString(KEY_INSTANCE_NAME, spec.instanceName)
            .putString(KEY_CONFIG_TOML, spec.configToml)
            .putString(KEY_FALLBACK_IPV4, spec.fallbackIpv4)
            .putStringSet(KEY_FALLBACK_ROUTES, spec.fallbackRoutes.toSet())
            .putInt(KEY_MTU, spec.mtu)
            .putString(KEY_DNS, spec.dns)
            .apply()
    }

    private fun clearSavedState() {
        getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().clear().apply()
    }

    private fun parseRuntimeSnapshot(json: String?, instanceName: String): RuntimeSnapshot? {
        if (json.isNullOrBlank()) return null
        return try {
            val root = JSONObject(json)
            val map = root.optJSONObject("map") ?: return null
            val entry = map.optJSONObject(instanceName)
                ?: map.keys().asSequence().firstOrNull()?.let { key -> map.optJSONObject(key) }
                ?: return null

            val running = entry.optBoolean("running", false)
            val error = entry.optString("error_msg").takeIf { it.isNotBlank() }
            val virtualIpv4Cidr =
                parseIpv4Inet(entry.optJSONObject("my_node_info")?.optJSONObject("virtual_ipv4"))

            val proxyCidrs = linkedSetOf<String>()
            val routes = entry.optJSONArray("routes")
            if (routes != null) {
                for (i in 0 until routes.length()) {
                    val route = routes.optJSONObject(i) ?: continue
                    val cidrs = route.optJSONArray("proxy_cidrs") ?: continue
                    for (j in 0 until cidrs.length()) {
                        val cidr = cidrs.optString(j)
                        if (cidr.isNotBlank()) {
                            proxyCidrs.add(cidr)
                        }
                    }
                }
            }

            RuntimeSnapshot(
                running = running,
                errorMessage = error,
                virtualIpv4Cidr = virtualIpv4Cidr,
                proxyCidrs = proxyCidrs.toList(),
            )
        } catch (_: Throwable) {
            null
        }
    }

    private fun parseIpv4Inet(obj: JSONObject?): String? {
        val address = obj?.optJSONObject("address") ?: return null
        val addr = address.optLong("addr", -1L)
        if (addr < 0) return null
        val networkLength = obj.optInt("network_length", 24)
        val unsigned = addr and 0xffffffffL
        val ipv4 = listOf(
            (unsigned shr 24) and 0xff,
            (unsigned shr 16) and 0xff,
            (unsigned shr 8) and 0xff,
            unsigned and 0xff,
        ).joinToString(".")
        return "$ipv4/$networkLength"
    }

    private fun parseCidr(cidr: String): Pair<String, Int> {
        val parts = cidr.split("/")
        if (parts.size != 2) {
            throw IllegalArgumentException("Invalid CIDR: $cidr")
        }
        return parts[0] to parts[1].toInt()
    }

    private fun updateNotification(title: String, text: String) {
        val notificationManager = getSystemService(NotificationManager::class.java)
        notificationManager.notify(NOTIFICATION_ID, buildNotification(title, text))
    }

    private fun buildNotification(title: String, text: String): Notification {
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE,
        )
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(text)
            .setSmallIcon(android.R.drawable.ic_lock_lock)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .build()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "FlEasyTier VPN",
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = "Keeps the Android EasyTier network alive in the background"
            }
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(channel)
        }
    }
}
