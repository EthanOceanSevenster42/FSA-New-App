package za.co.eclick.fsa_app

import android.content.ContentValues
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Saves a document into the phone's own Downloads folder.
 *
 * Flutter's file plugins write into the app's private external directory,
 * which no file manager on Android 11 or later will open — so an inspector
 * who tapped "download" had nothing to show for it. Downloads is a shared
 * collection, reachable through MediaStore without any storage permission,
 * and that is where a downloaded document belongs.
 */
class MainActivity : FlutterActivity() {
    private val channel = "za.co.eclick.fsa_app/downloads"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "saveToDownloads" -> {
                        val name = call.argument<String>("name")
                        val bytes = call.argument<ByteArray>("bytes")
                        val mime = call.argument<String>("mimeType")
                            ?: "application/pdf"
                        if (name == null || bytes == null) {
                            result.error(
                                "bad-arguments", "name and bytes are required", null
                            )
                            return@setMethodCallHandler
                        }
                        try {
                            result.success(saveToDownloads(name, bytes, mime))
                        } catch (error: Exception) {
                            result.error("save-failed", error.message, null)
                        }
                    }

                    "openDownload" -> {
                        val uri = call.argument<String>("uri")
                        val mime = call.argument<String>("mimeType")
                            ?: "application/pdf"
                        if (uri == null) {
                            result.error("bad-arguments", "uri is required", null)
                            return@setMethodCallHandler
                        }
                        try {
                            result.success(open(uri, mime))
                        } catch (error: Exception) {
                            result.error("open-failed", error.message, null)
                        }
                    }

                    "installApk" -> {
                        val path = call.argument<String>("path")
                        if (path == null) {
                            result.error("bad-arguments", "path is required", null)
                            return@setMethodCallHandler
                        }
                        try {
                            result.success(installApk(path))
                        } catch (error: Exception) {
                            result.error("install-failed", error.message, null)
                        }
                    }

                    "canInstallApks" -> result.success(canInstallApks())

                    "openInstallSettings" ->
                        result.success(openInstallSettings())

                    else -> result.notImplemented()
                }
            }
    }

    /**
     * Saves the file and returns where it went: the folder to tell the
     * inspector, and the document's own address so it can be opened again
     * from the message without hunting for it.
     */
    private fun saveToDownloads(
        name: String,
        bytes: ByteArray,
        mime: String,
    ): Map<String, String> {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val values = ContentValues().apply {
                put(MediaStore.Downloads.DISPLAY_NAME, name)
                put(MediaStore.Downloads.MIME_TYPE, mime)
                put(MediaStore.Downloads.IS_PENDING, 1)
            }
            val resolver = contentResolver
            val uri = resolver.insert(
                MediaStore.Downloads.EXTERNAL_CONTENT_URI, values
            ) ?: throw IllegalStateException("Downloads folder refused the file")

            resolver.openOutputStream(uri)?.use { it.write(bytes) }
                ?: throw IllegalStateException("Could not write to Downloads")

            values.clear()
            values.put(MediaStore.Downloads.IS_PENDING, 0)
            resolver.update(uri, values, null, null)
            return mapOf("where" to "Downloads/$name", "uri" to uri.toString())
        }

        // Before Android 10 the public folder is a plain path, and a file
        // handed to another app needs to travel as a FileProvider address.
        val folder =
            Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
        if (!folder.exists()) folder.mkdirs()
        val file = File(folder, name)
        file.writeBytes(bytes)
        val shared = FileProvider.getUriForFile(
            this, "$packageName.fileprovider", file
        )
        return mapOf("where" to file.absolutePath, "uri" to shared.toString())
    }

    /**
     * Hands a downloaded build to Android's package installer.
     *
     * The inspector still confirms the install themselves — this only opens
     * the installer on the right file. The APK is in the app's own cache, so
     * it travels as a FileProvider address; a plain path is refused from
     * Android 7 on.
     */
    private fun installApk(path: String): Boolean {
        val file = File(path)
        if (!file.exists()) return false
        val uri = FileProvider.getUriForFile(
            this, "$packageName.fileprovider", file
        )
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        return try {
            startActivity(intent)
            true
        } catch (error: android.content.ActivityNotFoundException) {
            false
        }
    }

    /**
     * Whether this phone will let the app start an install at all.
     *
     * "Install unknown apps" is granted per source and the inspector has to
     * turn it on once. Knowing beforehand is what lets the app say so
     * plainly rather than opening a settings screen with no explanation.
     */
    private fun canInstallApks(): Boolean =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            packageManager.canRequestPackageInstalls()
        } else {
            true
        }

    /**
     * Opens Android on this app's own "Install unknown apps" switch.
     *
     * The permission is off by default on every handset and no app may grant
     * it to itself, so an inspector has to flip it once per device. Told to
     * find it themselves — Settings, Apps, FSA Inspector, Install unknown
     * apps — enough of them will not, and a handset that cannot install is a
     * handset stuck on an old build with no other channel to reach it.
     *
     * The package URI is what makes the screen open on this app's switch
     * rather than on the list of every app. Where an OEM has no such screen
     * the generic security settings are better than nothing, and a device
     * before Android 8 has no per-source switch to open at all.
     */
    private fun openInstallSettings(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
        val direct = Intent(
            android.provider.Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
            Uri.parse("package:$packageName"),
        ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        return try {
            startActivity(direct)
            true
        } catch (error: android.content.ActivityNotFoundException) {
            try {
                startActivity(
                    Intent(android.provider.Settings.ACTION_SECURITY_SETTINGS)
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                )
                true
            } catch (fallbackError: android.content.ActivityNotFoundException) {
                false
            }
        }
    }

    /** Hands the saved document to whatever the phone opens PDFs with. */
    private fun open(uri: String, mime: String): Boolean {
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(Uri.parse(uri), mime)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        return try {
            startActivity(intent)
            true
        } catch (error: android.content.ActivityNotFoundException) {
            // Nothing on this phone reads PDFs; the file is still saved.
            false
        }
    }
}
