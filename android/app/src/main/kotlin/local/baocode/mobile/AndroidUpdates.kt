package local.baocode.mobile

import android.content.Intent
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import androidx.core.content.FileProvider
import android.app.Activity
import android.content.Context
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.MessageDigest
import java.util.concurrent.Executors

/** 只安装本应用缓存目录中、同签名且构建号更高的正式更新。 */
class AndroidUpdates(
    private val context: Context,
    private val activityProvider: () -> Activity?,
) : AutoCloseable {
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private var closed = false
    private val directory get() = File(context.cacheDir, "updates")

    fun handle(call: MethodCall, result: MethodChannel.Result): Boolean {
        when (call.method) {
            "updateDirectory" -> {
                if (!Build.SUPPORTED_ABIS.contains("arm64-v8a")) {
                    result.error("unsupported_device", "arm64 is required", null)
                } else if (directory.isDirectory || directory.mkdirs()) {
                    result.success(directory.absolutePath)
                } else {
                    result.error("update_storage_failed", "Update storage is unavailable", null)
                }
            }
            "installUpdate" -> {
                val path = call.argument<String>("path")
                val version = call.argument<String>("version")
                val size = call.argument<Number>("size")?.toLong()
                val sha256 = call.argument<String>("sha256")
                if (path == null || version == null || size == null || size <= 0) {
                    result.error("invalid_update", "Invalid update metadata", null)
                    return true
                }
                worker.execute {
                    val file = try {
                        verify(path, version, size, sha256)
                    } catch (_: Exception) {
                        main.post {
                            if (!closed) result.error("invalid_update", "Package verification failed", null)
                        }
                        return@execute
                    }
                    main.post {
                        if (closed) return@post
                        val activity = activityProvider()
                        if (activity == null) {
                            result.error("no_activity", "The app must be open to install an update", null)
                            return@post
                        }
                        try {
                            if (Build.VERSION.SDK_INT >= 26 &&
                                !activity.packageManager.canRequestPackageInstalls()) {
                                activity.startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                                    Uri.parse("package:${activity.packageName}")))
                                result.success(false)
                            } else {
                                val uri = FileProvider.getUriForFile(activity,
                                    "${activity.packageName}.updates", file)
                                activity.startActivity(Intent(Intent.ACTION_VIEW)
                                    .setDataAndType(uri, "application/vnd.android.package-archive")
                                    .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION))
                                result.success(true)
                            }
                        } catch (_: Exception) {
                            result.error("install_failed", "The system installer could not be opened", null)
                        }
                    }
                }
            }
            else -> return false
        }
        return true
    }

    @Suppress("DEPRECATION")
    private fun verify(path: String, version: String, size: Long, sha256: String?): File {
        val file = File(path).canonicalFile
        require(file.parentFile == directory.canonicalFile && file.isFile && file.length() == size)
        if (sha256 != null) {
            require(Regex("[a-f0-9]{64}").matches(sha256))
            val digest = MessageDigest.getInstance("SHA-256")
            file.inputStream().use { input ->
                val buffer = ByteArray(64 * 1024)
                while (true) {
                    val count = input.read(buffer)
                    if (count < 0) break
                    digest.update(buffer, 0, count)
                }
            }
            require(hex(digest.digest()) == sha256)
        }
        val flags = if (Build.VERSION.SDK_INT >= 28) PackageManager.GET_SIGNING_CERTIFICATES
            else PackageManager.GET_SIGNATURES
        val manager = context.packageManager
        val installed = manager.getPackageInfo(context.packageName, flags)
        // 部分系统版本读安装包文件时只有带上 GET_SIGNATURES 才会解析证书，
        // 两个标志一起传；读不到证书时 identity 给空集合，策略会拒绝安装。
        val candidate = requireNotNull(manager.getPackageArchiveInfo(file.path,
            flags or PackageManager.GET_SIGNATURES))
        require(UpdatePolicy.isAllowed(identity(installed), identity(candidate), version))
        return file
    }

    @Suppress("DEPRECATION")
    private fun identity(info: PackageInfo): ApkIdentity {
        val signatures = if (Build.VERSION.SDK_INT >= 28)
            info.signingInfo?.apkContentsSigners?.takeIf { it.isNotEmpty() } ?: info.signatures
            else info.signatures
        val signers = signatures?.map {
            hex(MessageDigest.getInstance("SHA-256").digest(it.toByteArray()))
        }?.toSet() ?: emptySet()
        return ApkIdentity(info.packageName, info.versionName,
            if (Build.VERSION.SDK_INT >= 28) info.longVersionCode else info.versionCode.toLong(),
            signers)
    }

    private fun hex(bytes: ByteArray) = bytes.joinToString("") { "%02x".format(it) }

    override fun close() {
        closed = true
        worker.shutdown()
    }
}
