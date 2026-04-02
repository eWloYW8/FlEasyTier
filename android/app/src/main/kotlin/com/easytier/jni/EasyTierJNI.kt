package com.easytier.jni

object EasyTierJNI {

    @Volatile
    private var librariesLoaded = false

    @Volatile
    private var loadError: Throwable? = null

    @JvmStatic
    fun ensureLoaded() {
        if (librariesLoaded) {
            return
        }
        synchronized(this) {
            if (librariesLoaded) {
                return
            }
            loadError?.let { throw it }
            try {
                System.loadLibrary("easytier_ffi")
                System.loadLibrary("easytier_android_jni")
                librariesLoaded = true
            } catch (t: Throwable) {
                loadError = t
                throw t
            }
        }
    }

    @JvmStatic external fun setTunFd(instanceName: String, fd: Int): Int

    @JvmStatic external fun parseConfig(config: String): Int

    @JvmStatic external fun runNetworkInstance(config: String): Int

    @JvmStatic external fun retainNetworkInstance(instanceNames: Array<String>?): Int

    @JvmStatic external fun collectNetworkInfos(): String?

    @JvmStatic external fun getLastError(): String?

    @JvmStatic
    fun stopAllInstances(): Int = retainNetworkInstance(null)

    @JvmStatic
    fun retainSingleInstance(instanceName: String): Int =
        retainNetworkInstance(arrayOf(instanceName))
}
