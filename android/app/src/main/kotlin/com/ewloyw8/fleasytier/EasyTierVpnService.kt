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
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
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
        val routeCount: Int,
        val peerCount: Int,
        val peerEvents: List<String>,
        val routeEvents: List<String>,
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

        private val serviceLogs = mutableListOf<String>()
        private const val MAX_LOG_LINES = 400
        private val logTimeFormat =
            SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.US)

        fun getStatus(): Map<String, Any?> =
            hashMapOf(
                "running" to networkRunning,
                "configId" to activeConfigId,
                "instanceName" to activeInstanceName,
                "errorMessage" to lastErrorMessage,
                "infoJson" to lastInfoJson,
                "logs" to synchronized(serviceLogs) { serviceLogs.toList() },
            )

        private fun clearServiceLogs() {
            synchronized(serviceLogs) {
                serviceLogs.clear()
            }
        }

        private fun appendServiceLog(message: String) {
            val line = "[${logTimeFormat.format(Date())}] $message"
            synchronized(serviceLogs) {
                serviceLogs.add(line)
                if (serviceLogs.size > MAX_LOG_LINES) {
                    serviceLogs.removeAt(0)
                }
            }
        }
    }

    private val stateLock = Any()
    private var vpnInterface: ParcelFileDescriptor? = null
    private var worker: Thread? = null
    private var currentSpec: StartSpec? = null
    private var currentIpv4: String? = null
    private var currentRoutes: List<String> = emptyList()
    private var lastLoggedRunningState: Boolean? = null
    private var lastLoggedError: String? = null
    private var lastLoggedVirtualIpv4: String? = null
    private var lastLoggedRouteCount: Int? = null
    private var lastLoggedPeerCount: Int? = null
    private var lastLoggedPeers: Set<String> = emptySet()
    private var lastLoggedRoutes: Set<String> = emptySet()
    private var lastLoggedProxyCidrs: Set<String> = emptySet()
    private var logcatProcess: Process? = null
    private var logcatThread: Thread? = null
    @Volatile
    private var logcatBridgeRunning: Boolean = false

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        appendServiceLog("VPN service created")
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
            appendServiceLog("No start spec available, stopping service")
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
            clearServiceLogs()
            appendServiceLog("Starting managed network ${spec.instanceName}")
            appendServiceLog(
                "Config: mtu=${spec.mtu}, fallbackIpv4=${spec.fallbackIpv4}, dns=${spec.dns ?: "-"}, routes=${spec.fallbackRoutes.joinToString(", ").ifEmpty { "-" }}",
            )
            startNativeLogBridge()
            currentSpec = spec
            activeConfigId = spec.configId
            activeInstanceName = spec.instanceName
            lastErrorMessage = null
            lastInfoJson = null
            networkRunning = false
            currentIpv4 = null
            currentRoutes = emptyList()
            lastLoggedRunningState = null
            lastLoggedError = null
            lastLoggedVirtualIpv4 = null
            lastLoggedRouteCount = null
            lastLoggedPeerCount = null
            lastLoggedPeers = emptySet()
            lastLoggedRoutes = emptySet()
            lastLoggedProxyCidrs = emptySet()

            worker = thread(start = true, name = "FlEasyTier-AndroidService") {
                runManagedNetwork(spec)
            }
        }
    }

    private fun runManagedNetwork(spec: StartSpec) {
        try {
            appendServiceLog("Loading embedded EasyTier libraries")
            EasyTierJNI.ensureLoaded()
            appendServiceLog("Launching embedded EasyTier instance")
            val result = EasyTierJNI.runNetworkInstance(spec.configToml)
            if (result != 0) {
                throw IllegalStateException(
                    EasyTierJNI.getLastError() ?: "Failed to start EasyTier instance",
                )
            }

            networkRunning = true
            appendServiceLog("Embedded instance started")
            updateNotification("FlEasyTier", "Connecting ${spec.instanceName}")
            var announcedRunning = false

            while (!Thread.currentThread().isInterrupted &&
                currentSpec?.configId == spec.configId
            ) {
                val infosJson = EasyTierJNI.collectNetworkInfos()
                lastInfoJson = infosJson

                val snapshot = parseRuntimeSnapshot(infosJson, spec.instanceName)
                if (snapshot != null) {
                    networkRunning = snapshot.running
                    val snapshotError = normalizeErrorMessage(snapshot.errorMessage)
                    if (snapshotError != null) {
                        lastErrorMessage = snapshotError
                    }
                    logSnapshotChanges(snapshot, spec)

                    if (snapshot.running) {
                        if (!announcedRunning) {
                            appendServiceLog(
                                "Network is running with ${snapshot.virtualIpv4Cidr ?: spec.fallbackIpv4}",
                            )
                            announcedRunning = true
                        }
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
            appendServiceLog("Managed worker interrupted")
            Thread.currentThread().interrupt()
        } catch (t: Throwable) {
            val typeName = t::class.java.name
            val detail = normalizeErrorMessage(t.message) ?: t.toString()
            lastErrorMessage = "$typeName: $detail"
            appendServiceLog("Network failed: $lastErrorMessage")
            networkRunning = false
            updateNotification("FlEasyTier", "Network stopped: ${lastErrorMessage ?: "error"}")
        } finally {
            closeVpnInterface()
            try {
                EasyTierJNI.stopAllInstances()
                appendServiceLog("All managed instances stopped")
            } catch (_: Throwable) {
            }
        }
    }

    private fun logSnapshotChanges(snapshot: RuntimeSnapshot, spec: StartSpec) {
        if (lastLoggedRunningState != snapshot.running) {
            appendServiceLog(
                if (snapshot.running) {
                    "Runtime state changed: running"
                } else {
                    "Runtime state changed: not running"
                },
            )
            lastLoggedRunningState = snapshot.running
        }

        val effectiveIpv4 = snapshot.virtualIpv4Cidr ?: spec.fallbackIpv4
        if (effectiveIpv4 != lastLoggedVirtualIpv4) {
            appendServiceLog("Virtual IPv4: $effectiveIpv4")
            lastLoggedVirtualIpv4 = effectiveIpv4
        }

        if (snapshot.routeCount != lastLoggedRouteCount ||
            snapshot.peerCount != lastLoggedPeerCount
        ) {
            appendServiceLog(
                "Topology update: peers=${snapshot.peerCount}, routes=${snapshot.routeCount}",
            )
            lastLoggedRouteCount = snapshot.routeCount
            lastLoggedPeerCount = snapshot.peerCount
        }

        logSetChanges(
            titleAdded = "Peer connected",
            titleRemoved = "Peer disconnected",
            current = snapshot.peerEvents.toSet(),
            previous = lastLoggedPeers,
        )
        lastLoggedPeers = snapshot.peerEvents.toSet()

        logSetChanges(
            titleAdded = "Route added",
            titleRemoved = "Route removed",
            current = snapshot.routeEvents.toSet(),
            previous = lastLoggedRoutes,
        )
        lastLoggedRoutes = snapshot.routeEvents.toSet()

        logSetChanges(
            titleAdded = "Proxy CIDR advertised",
            titleRemoved = "Proxy CIDR withdrawn",
            current = snapshot.proxyCidrs.toSet(),
            previous = lastLoggedProxyCidrs,
        )
        lastLoggedProxyCidrs = snapshot.proxyCidrs.toSet()

        val snapshotError = normalizeErrorMessage(snapshot.errorMessage)
        if (snapshotError != null && snapshotError != lastLoggedError) {
            appendServiceLog("Runtime error: $snapshotError")
            lastLoggedError = snapshotError
        } else if (snapshotError == null) {
            lastLoggedError = null
        }
    }

    private fun logSetChanges(
        titleAdded: String,
        titleRemoved: String,
        current: Set<String>,
        previous: Set<String>,
    ) {
        (current - previous).sorted().forEach { item ->
            appendServiceLog("$titleAdded: $item")
        }
        (previous - current).sorted().forEach { item ->
            appendServiceLog("$titleRemoved: $item")
        }
    }

    private fun stopManagedNetwork(clearSavedState: Boolean, stopService: Boolean) {
        synchronized(stateLock) {
            appendServiceLog("Stopping managed network")
            stopNativeLogBridge()
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
                appendServiceLog("Clearing persisted Android VPN state")
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

    private fun startNativeLogBridge() {
        stopNativeLogBridge()
        try {
            logcatBridgeRunning = true
            val process = ProcessBuilder(
                "logcat",
                "-v",
                "time",
                "-T",
                "1",
                "EasyTier-JNI:D",
                "*:S",
            )
                .redirectErrorStream(true)
                .start()
            logcatProcess = process
            logcatThread = thread(start = true, name = "FlEasyTier-LogcatBridge") {
                try {
                    process.inputStream.bufferedReader().useLines { lines ->
                        lines.forEach { raw ->
                            if (!logcatBridgeRunning || Thread.currentThread().isInterrupted) {
                                return@forEach
                            }
                            val line = raw.trim()
                            if (line.isEmpty()) return@forEach
                            appendServiceLog("[JNI] $line")
                        }
                    }
                } catch (_: Throwable) {
                    if (logcatBridgeRunning) {
                        appendServiceLog("Native logcat bridge stopped unexpectedly")
                    }
                }
            }
            appendServiceLog("Attached native logcat bridge for EasyTier-JNI")
        } catch (t: Throwable) {
            logcatBridgeRunning = false
            appendServiceLog("Failed to attach native logcat bridge: ${t.message ?: t}")
        }
    }

    private fun stopNativeLogBridge() {
        logcatBridgeRunning = false
        try {
            logcatProcess?.destroy()
        } catch (_: Throwable) {
        }
        logcatProcess = null
        try {
            logcatThread?.interrupt()
        } catch (_: Throwable) {
        }
        logcatThread = null
    }

    private fun ensureVpnInterface(
        instanceName: String,
        ipv4Cidr: String,
        routes: List<String>,
        mtu: Int,
        dns: String?,
    ) {
        synchronized(stateLock) {
            val effectiveRoutes = buildVpnRoutes(ipv4Cidr, routes)
            if (vpnInterface != null &&
                currentIpv4 == ipv4Cidr &&
                currentRoutes == effectiveRoutes
            ) {
                return
            }

            appendServiceLog("Rebuilding VPN interface")
            closeVpnInterface()

            val (ipv4, cidr) = parseCidr(ipv4Cidr)
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
                appendServiceLog("Configured DNS server: $dns")
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
            appendServiceLog("Attached TUN fd to instance $instanceName")

            vpnInterface = established
            currentIpv4 = ipv4Cidr
            currentRoutes = effectiveRoutes
            appendServiceLog(
                "VPN interface established: $ipv4Cidr via ${effectiveRoutes.joinToString(", ")}",
            )
        }
    }

    private fun closeVpnInterface() {
        synchronized(stateLock) {
            if (vpnInterface != null) {
                appendServiceLog("Closing VPN interface")
            }
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
            ?: emptyList()
        val mtu = actualIntent.getIntExtra("mtu", 1300)
        val dns = actualIntent.getStringExtra("dns")
        appendServiceLog("Received start intent for $instanceName")
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
            ?: emptyList()
        val mtu = prefs.getInt(KEY_MTU, 1300)
        val dns = prefs.getString(KEY_DNS, null)
        appendServiceLog("Restored persisted start spec for $instanceName")
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
            val error = normalizeErrorMessage(entry.optString("error_msg"))
            val virtualIpv4Cidr =
                parseIpv4Inet(entry.optJSONObject("my_node_info")?.optJSONObject("virtual_ipv4"))

            val proxyCidrs = linkedSetOf<String>()
            val routeEvents = linkedSetOf<String>()
            val peerHostnames = linkedMapOf<Int, String>()
            val routes = entry.optJSONArray("routes")
            if (routes != null) {
                for (i in 0 until routes.length()) {
                    val route = routes.optJSONObject(i) ?: continue
                    val peerId = route.optInt("peer_id", 0)
                    val hostname = normalizeErrorMessage(route.optString("hostname"))
                    if (peerId > 0 && hostname != null) {
                        peerHostnames[peerId] = hostname
                    }
                    val ipv4Route = parseIpv4Inet(route.optJSONObject("ipv4_addr"))
                    val ipv6Route = parseIpv6Inet(route.optJSONObject("ipv6_addr"))
                    val primaryRoute = ipv4Route ?: ipv6Route
                    if (primaryRoute != null) {
                        val peerLabel = formatPeerLabel(peerId, hostname)
                        routeEvents.add("$peerLabel -> $primaryRoute")
                    }
                    val cidrs = route.optJSONArray("proxy_cidrs") ?: continue
                    for (j in 0 until cidrs.length()) {
                        val cidr = cidrs.optString(j)
                        if (cidr.isNotBlank()) {
                            proxyCidrs.add(cidr)
                        }
                    }
                }
            }

            val peerEvents = linkedSetOf<String>()
            val peers = entry.optJSONArray("peers")
            if (peers != null) {
                for (i in 0 until peers.length()) {
                    val peer = peers.optJSONObject(i) ?: continue
                    val peerId = peer.optInt("peer_id", 0)
                    val peerLabel = formatPeerLabel(peerId, peerHostnames[peerId])
                    val conns = peer.optJSONArray("conns")
                    if (conns == null || conns.length() == 0) {
                        peerEvents.add(peerLabel)
                        continue
                    }

                    for (j in 0 until conns.length()) {
                        val conn = conns.optJSONObject(j) ?: continue
                        val tunnel = conn.optJSONObject("tunnel")
                        val tunnelType = normalizeErrorMessage(tunnel?.optString("tunnel_type")) ?: "unknown"
                        val remote = normalizeErrorMessage(
                            tunnel?.optJSONObject("remote_addr")?.optString("url"),
                        )
                        val local = normalizeErrorMessage(
                            tunnel?.optJSONObject("local_addr")?.optString("url"),
                        )
                        val parts = buildList {
                            add(peerLabel)
                            add("via $tunnelType")
                            if (remote != null) add("remote=$remote")
                            if (local != null) add("local=$local")
                        }
                        peerEvents.add(parts.joinToString(", "))
                    }
                }
            }

            RuntimeSnapshot(
                running = running,
                errorMessage = error,
                virtualIpv4Cidr = virtualIpv4Cidr,
                proxyCidrs = proxyCidrs.toList(),
                routeCount = routes?.length() ?: 0,
                peerCount = entry.optJSONArray("peers")?.length() ?: 0,
                peerEvents = peerEvents.toList(),
                routeEvents = routeEvents.toList(),
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

    private fun parseIpv6Inet(obj: JSONObject?): String? {
        obj ?: return null
        val address = obj.optJSONObject("address") ?: return null
        val parts = listOf(
            address.optInt("part1", 0),
            address.optInt("part2", 0),
            address.optInt("part3", 0),
            address.optInt("part4", 0),
        )
        if (parts.all { it == 0 }) return null
        val groups = buildList(8) {
            for (part in parts) {
                add(((part ushr 16) and 0xFFFF).toString(16))
                add((part and 0xFFFF).toString(16))
            }
        }
        return "${groups.joinToString(":")}/${obj.optInt("network_length", 64)}"
    }

    private fun formatPeerLabel(peerId: Int, hostname: String?): String {
        val suffix = if (!hostname.isNullOrBlank()) " ($hostname)" else ""
        return if (peerId > 0) "peer $peerId$suffix" else "peer$suffix"
    }

    private fun parseCidr(cidr: String): Pair<String, Int> {
        val parts = cidr.split("/")
        if (parts.size != 2) {
            throw IllegalArgumentException("Invalid CIDR: $cidr")
        }
        return parts[0] to parts[1].toInt()
    }

    private fun buildVpnRoutes(ipv4Cidr: String, routes: List<String>): List<String> {
        val normalized = linkedSetOf<String>()
        networkRouteFor(ipv4Cidr)?.let { normalized.add(it) }
        for (route in routes) {
            val cleaned = route.trim()
            if (cleaned.isEmpty()) continue
            normalized.add(cleaned)
        }
        return normalized.toList()
    }

    private fun networkRouteFor(cidr: String): String? {
        val (ip, prefix) = parseCidr(cidr)
        if (prefix !in 0..32) {
            throw IllegalArgumentException("Invalid CIDR prefix: $cidr")
        }
        val addr = ipv4ToInt(ip)
        val mask = if (prefix == 0) 0 else (-1 shl (32 - prefix))
        val network = addr and mask
        return "${intToIpv4(network)}/$prefix"
    }

    private fun ipv4ToInt(ip: String): Int {
        val parts = ip.split(".")
        if (parts.size != 4) {
            throw IllegalArgumentException("Invalid IPv4 address: $ip")
        }
        var value = 0
        for (part in parts) {
            val octet = part.toInt()
            if (octet !in 0..255) {
                throw IllegalArgumentException("Invalid IPv4 address: $ip")
            }
            value = (value shl 8) or octet
        }
        return value
    }

    private fun intToIpv4(value: Int): String =
        listOf(
            (value ushr 24) and 0xff,
            (value ushr 16) and 0xff,
            (value ushr 8) and 0xff,
            value and 0xff,
        ).joinToString(".")

    private fun normalizeErrorMessage(value: String?): String? {
        val normalized = value?.trim()
        if (normalized.isNullOrEmpty()) return null
        if (normalized.equals("null", ignoreCase = true)) return null
        if (normalized.equals("undefined", ignoreCase = true)) return null
        return normalized
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
