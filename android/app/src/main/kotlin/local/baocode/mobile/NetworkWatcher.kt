package local.baocode.mobile

import android.content.Context
import android.net.ConnectivityManager
import android.net.LinkProperties
import android.net.Network
import android.net.NetworkCapabilities
import android.os.Handler
import android.os.SystemClock
import android.util.Log

/**
 * 默认网络变化观察者，随引擎的生命周期（不是 Activity 或 Service）存在。
 * 只在默认网络换了、丢了，IP 地址或底层传输变了时通知，1 秒防抖；注册时系统立即回放的状态不算变化。
 * 开着 VPN 时默认网络一直是 VPN，Wi-Fi 和移动网络互换只体现在它的传输类型上。
 */
internal class NetworkWatcher(
    context: Context,
    private val main: Handler,
    private val onChanged: () -> Unit,
) {
    private val manager = context.applicationContext
        .getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
    private var callback: ConnectivityManager.NetworkCallback? = null
    private var known: Network? = null
    private var signature: String? = null
    private var transports: String? = null
    private var quietUntil = 0L
    private val fire = Runnable { if (callback != null) onChanged() }

    /** 默认网络回调是否已成功注册。 */
    val watching get() = callback != null

    fun start() {
        if (callback != null) return
        known = null
        signature = null
        transports = null
        quietUntil = SystemClock.elapsedRealtime() + SETTLE_MS
        val created = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) = onMain(this) {
                if (network != known) {
                    known = network
                    signature = null
                    transports = null
                    changed()
                }
            }

            override fun onLost(network: Network) = onMain(this) {
                if (network == known) {
                    known = null
                    signature = null
                    transports = null
                    changed()
                }
            }

            override fun onLinkPropertiesChanged(network: Network, properties: LinkProperties) =
                onMain(this) {
                    if (network != known) return@onMain
                    val next = signatureOf(properties)
                    val previous = signature
                    signature = next
                    if (previous != null && previous != next) changed()
                }

            override fun onCapabilitiesChanged(network: Network, capabilities: NetworkCapabilities) =
                onMain(this) {
                    if (network != known) return@onMain
                    val next = transportsOf(capabilities)
                    val previous = transports
                    transports = next
                    if (previous != null && previous != next) changed()
                }
        }
        try {
            manager.registerDefaultNetworkCallback(created)
            callback = created
        } catch (error: RuntimeException) {
            // 不暗中降级：watching 保持 false，由宿主把状态告知 Dart。
            Log.w(TAG, "default network callback unavailable", error)
        }
    }

    fun stop() {
        val registered = callback ?: return
        callback = null
        main.removeCallbacks(fire)
        try {
            manager.unregisterNetworkCallback(registered)
        } catch (_: IllegalArgumentException) {
            // 已经不在注册表里。
        }
        known = null
        signature = null
        transports = null
    }

    private fun onMain(owner: ConnectivityManager.NetworkCallback, block: () -> Unit) {
        main.post { if (callback === owner) block() }
    }

    private fun changed() {
        if (SystemClock.elapsedRealtime() < quietUntil) return
        main.removeCallbacks(fire)
        main.postDelayed(fire, DEBOUNCE_MS)
    }

    private fun signatureOf(properties: LinkProperties) =
        properties.interfaceName + "|" + properties.linkAddresses
            .mapNotNull { it.address.hostAddress }.sorted().joinToString(",")

    private fun transportsOf(capabilities: NetworkCapabilities) = listOf(
        NetworkCapabilities.TRANSPORT_WIFI,
        NetworkCapabilities.TRANSPORT_CELLULAR,
        NetworkCapabilities.TRANSPORT_ETHERNET,
        NetworkCapabilities.TRANSPORT_VPN,
    ).filter(capabilities::hasTransport).joinToString(",")

    private companion object {
        const val TAG = "NetworkWatcher"
        const val DEBOUNCE_MS = 1000L
        const val SETTLE_MS = 1500L
    }
}
