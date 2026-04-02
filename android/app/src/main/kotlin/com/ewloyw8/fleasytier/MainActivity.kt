package com.ewloyw8.fleasytier

import android.app.Activity
import android.content.Intent
import android.net.VpnService
import androidx.core.content.ContextCompat
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
                    "startManagedNetwork" -> {
                        val configId = call.argument<String>("configId")
                        val instanceName = call.argument<String>("instanceName")
                        val configToml = call.argument<String>("configToml")
                        val fallbackIpv4 = call.argument<String>("fallbackIpv4") ?: "10.0.0.1/24"
                        val mtu = call.argument<Int>("mtu") ?: 1300
                        val routes = call.argument<List<String>>("routes") ?: listOf("0.0.0.0/0")
                        val dns = call.argument<String>("dns")
                        if (configId.isNullOrBlank() || instanceName.isNullOrBlank() || configToml.isNullOrBlank()) {
                            result.error("invalid_args", "configId, instanceName and configToml are required", null)
                            return@setMethodCallHandler
                        }
                        startManagedNetworkService(
                            configId = configId,
                            instanceName = instanceName,
                            configToml = configToml,
                            fallbackIpv4 = fallbackIpv4,
                            mtu = mtu,
                            routes = routes,
                            dns = dns,
                        )
                        result.success(null)
                    }
                    "stopManagedNetwork" -> {
                        stopManagedNetworkService()
                        result.success(null)
                    }
                    "getManagedNetworkStatus" -> {
                        result.success(EasyTierVpnService.getStatus())
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

    private fun startManagedNetworkService(
        configId: String,
        instanceName: String,
        configToml: String,
        fallbackIpv4: String,
        mtu: Int,
        routes: List<String>,
        dns: String?
    ) {
        val intent = Intent(this, EasyTierVpnService::class.java).apply {
            action = EasyTierVpnService.ACTION_START
            putExtra("configId", configId)
            putExtra("instanceName", instanceName)
            putExtra("configToml", configToml)
            putExtra("fallbackIpv4", fallbackIpv4)
            putExtra("mtu", mtu)
            putStringArrayListExtra("fallbackRoutes", ArrayList(routes))
            if (dns != null) putExtra("dns", dns)
        }
        ContextCompat.startForegroundService(this, intent)
    }

    private fun stopManagedNetworkService() {
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
