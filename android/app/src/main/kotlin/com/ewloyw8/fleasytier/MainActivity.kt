package com.ewloyw8.fleasytier

import android.app.Activity
import android.content.Intent
import android.net.VpnService
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    companion object {
        private const val CHANNEL = "com.ewloyw8.fleasytier/vpn"
        private const val VPN_REQUEST_CODE = 0x0F
    }

    private var pendingResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "prepareVpn" -> prepareVpn(result)
                    "startVpn" -> {
                        val ipv4 = call.argument<String>("ipv4") ?: "10.0.0.1"
                        val cidr = call.argument<Int>("cidr") ?: 24
                        val mtu = call.argument<Int>("mtu") ?: 1300
                        val routes = call.argument<List<String>>("routes") ?: listOf("0.0.0.0/0")
                        val dns = call.argument<String>("dns")
                        startVpnService(ipv4, cidr, mtu, routes, dns)
                        result.success(null)
                    }
                    "stopVpn" -> {
                        stopVpnService()
                        result.success(null)
                    }
                    "getVpnStatus" -> {
                        result.success(mapOf(
                            "running" to EasyTierVpnService.isRunning,
                            "fd" to EasyTierVpnService.vpnFd
                        ))
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun prepareVpn(result: MethodChannel.Result) {
        val intent = VpnService.prepare(this)
        if (intent != null) {
            pendingResult = result
            startActivityForResult(intent, VPN_REQUEST_CODE)
        } else {
            // Already authorized
            result.success(true)
        }
    }

    private fun startVpnService(
        ipv4: String,
        cidr: Int,
        mtu: Int,
        routes: List<String>,
        dns: String?
    ) {
        val intent = Intent(this, EasyTierVpnService::class.java).apply {
            action = EasyTierVpnService.ACTION_START
            putExtra("ipv4", ipv4)
            putExtra("cidr", cidr)
            putExtra("mtu", mtu)
            putStringArrayListExtra("routes", ArrayList(routes))
            if (dns != null) putExtra("dns", dns)
        }
        startService(intent)
    }

    private fun stopVpnService() {
        val intent = Intent(this, EasyTierVpnService::class.java).apply {
            action = EasyTierVpnService.ACTION_STOP
        }
        startService(intent)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == VPN_REQUEST_CODE) {
            pendingResult?.success(resultCode == Activity.RESULT_OK)
            pendingResult = null
        }
    }
}
