package com.farazlabs.kryvo

import android.app.ActivityManager
import android.app.AppOpsManager
import android.content.ComponentName
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.Drawable
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.os.Process
import android.provider.MediaStore
import android.provider.OpenableColumns
import android.provider.Settings
import android.view.WindowManager
import android.webkit.MimeTypeMap
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File

/**
 * FlutterFragmentActivity is required by the `local_auth` plugin (the biometric
 * prompt needs a FragmentActivity).
 *
 * FLAG_SECURE blocks screenshots and hides the app content in the recent-apps
 * switcher — the native "no-screenshot" protection the web app could not offer.
 */
class MainActivity : FlutterFragmentActivity() {
    // Launcher icons: <activity-alias> entries in AndroidManifest.xml, all
    // pointing at this activity. MainActivity itself is never disabled.
    private val icons = mapOf(
        "default" to ".IconDefault",
        "purple" to ".IconPurple",
        "green" to ".IconGreen",
        "dark" to ".IconDark",
        "rose" to ".IconRose",
        "calc" to ".IconCalc",
        "clock" to ".IconClock",
        "game" to ".IconGame",
        "notes" to ".IconNotes",
        "torch" to ".IconTorch",
    )

    // Name shown in the recent-apps list for disguise icons, so the switcher
    // doesn't give the vault away either.
    private val disguiseLabels = mapOf(
        "calc" to "Calculator",
        "clock" to "Clock",
        "game" to "Games",
        "notes" to "Notes",
        "torch" to "Flashlight",
    )

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Block screenshots / recents previews. Only the separate "Kryvo Dev"
        // test build (debug) allows them, for testing and store screenshots.
        if (!BuildConfig.DEBUG) {
            window.setFlags(
                WindowManager.LayoutParams.FLAG_SECURE,
                WindowManager.LayoutParams.FLAG_SECURE
            )
        }
        updateTaskLabel(currentIcon())
        handleShare(intent)
    }

    @Suppress("DEPRECATION")
    private fun updateTaskLabel(id: String) {
        val label = disguiseLabels[id] ?: "Kryvo"
        setTaskDescription(ActivityManager.TaskDescription(label))
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "kryvo/app_icon")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "get" -> result.success(currentIcon())
                    "set" -> {
                        val id = call.argument<String>("id")
                        if (id == null || !icons.containsKey(id)) {
                            result.error("bad_icon", "Unknown icon $id", null)
                        } else {
                            setIcon(id)
                            updateTaskLabel(id)
                            result.success(null)
                        }
                    }
                    // Flashlight disguise: the torch needs no camera permission.
                    "torch" -> {
                        try {
                            setTorch(call.argument<Boolean>("on") == true)
                            result.success(true)
                        } catch (e: Exception) {
                            result.success(false)
                        }
                    }
                    "hasTorch" -> result.success(torchCameraId() != null)
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "kryvo/app_lock")
            .setMethodCallHandler { call, result -> handleAppLock(call, result) }
        mediaChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "kryvo/media")
        mediaChannel!!.setMethodCallHandler { call, result ->
                when (call.method) {
                    "takeShared" -> {
                        result.success(pendingShared.toList())
                        pendingShared.clear()
                    }
                    "saveAudio" -> {
                        val path = call.argument<String>("path") ?: ""
                        val name = call.argument<String>("name") ?: "audio"
                        Thread {
                            val ok = try {
                                saveAudioToMusic(File(path), name)
                            } catch (_: Exception) {
                                false
                            }
                            runOnUiThread { result.success(ok) }
                        }.start()
                    }
                    "share" -> {
                        val send = Intent(Intent.ACTION_SEND)
                            .setType("text/plain")
                            .putExtra(Intent.EXTRA_TEXT, call.argument<String>("text") ?: "")
                        val target = call.argument<String>("package")
                        if (target != null) send.setPackage(target)
                        try {
                            startActivity(
                                if (target != null) send
                                else Intent.createChooser(send, call.argument<String>("title"))
                            )
                            result.success(true)
                        } catch (_: Exception) {
                            result.success(false)
                        }
                    }
                    // Full backup: let the user pick where to save the file
                    // (Google Drive, Downloads, USB…), then stream-copy it.
                    "saveFile" -> {
                        pendingSave?.second?.success(false)
                        pendingSave = File(call.argument<String>("path") ?: "") to result
                        try {
                            startActivityForResult(
                                Intent(Intent.ACTION_CREATE_DOCUMENT)
                                    .addCategory(Intent.CATEGORY_OPENABLE)
                                    .setType("application/octet-stream")
                                    .putExtra(Intent.EXTRA_TITLE, call.argument<String>("name")),
                                REQ_SAVE
                            )
                        } catch (_: Exception) {
                            pendingSave = null
                            result.success(false)
                        }
                    }
                    "isInstalled" -> result.success(
                        try {
                            packageManager.getPackageInfo(call.argument<String>("package") ?: "", 0)
                            true
                        } catch (_: Exception) {
                            false
                        }
                    )
                    else -> result.notImplemented()
                }
            }
    }

    private var pendingSave: Pair<File, MethodChannel.Result>? = null
    private val REQ_SAVE = 4711

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != REQ_SAVE) return
        val (src, result) = pendingSave ?: return
        pendingSave = null
        val uri = data?.data
        if (resultCode != RESULT_OK || uri == null) {
            result.success(false)
            return
        }
        Thread {
            val ok = try {
                contentResolver.openOutputStream(uri)?.use { out ->
                    src.inputStream().use { it.copyTo(out, 1 shl 20) }
                } != null
            } catch (_: Exception) {
                false
            }
            runOnUiThread { result.success(ok) }
        }.start()
    }

    /**
     * Unhide audio: put the decrypted file into the phone's Music/Kryvo folder
     * (Android 10+ needs no storage permission for this). Returns false on
     * older Android, where the user picks a place instead.
     */
    private fun saveAudioToMusic(src: File, name: String): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return false
        val ext = name.substringAfterLast('.', "").lowercase()
        val mime = MimeTypeMap.getSingleton().getMimeTypeFromExtension(ext) ?: "audio/mpeg"
        val values = ContentValues().apply {
            put(MediaStore.Audio.Media.DISPLAY_NAME, name)
            put(MediaStore.Audio.Media.MIME_TYPE, mime)
            put(MediaStore.Audio.Media.RELATIVE_PATH, "${Environment.DIRECTORY_MUSIC}/Kryvo")
            put(MediaStore.Audio.Media.IS_PENDING, 1)
        }
        val uri = contentResolver.insert(
            MediaStore.Audio.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY), values
        ) ?: return false
        try {
            contentResolver.openOutputStream(uri)?.use { out ->
                src.inputStream().use { it.copyTo(out) }
            } ?: throw IllegalStateException("no stream")
            values.clear()
            values.put(MediaStore.Audio.Media.IS_PENDING, 0)
            contentResolver.update(uri, values, null, null)
            return true
        } catch (e: Exception) {
            contentResolver.delete(uri, null, null)
            return false
        }
    }

    // ---- App Lock (locking other apps) ----------------------------------------

    private val appLock by lazy { AppLockStore(this) }

    override fun onResume() {
        super.onResume()
        // Restart the watcher if the system stopped it.
        if (appLock.enabled && hasUsageAccess() && Settings.canDrawOverlays(this)) {
            try {
                AppLockService.start(this)
            } catch (_: Exception) {
            }
        }
    }

    private fun hasUsageAccess(): Boolean {
        val ops = getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            ops.unsafeCheckOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), packageName)
        } else {
            @Suppress("DEPRECATION")
            ops.checkOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), packageName)
        }
        return mode == AppOpsManager.MODE_ALLOWED
    }

    private fun handleAppLock(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "state" -> result.success(
                mapOf(
                    "enabled" to appLock.enabled,
                    "hasPin" to appLock.hasPin(),
                    "usage" to hasUsageAccess(),
                    "overlay" to Settings.canDrawOverlays(this),
                    "bio" to appLock.useFingerprint,
                    "locked" to appLock.lockedApps.toList(),
                )
            )
            "apps" -> Thread {
                // Every app with a home-screen icon, except Kryvo itself.
                val list = try {
                    val pm = packageManager
                    pm.queryIntentActivities(
                        Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER), 0
                    ).map { it.activityInfo.packageName }
                        .distinct()
                        .filter { it != packageName }
                        .mapNotNull { pkg ->
                            try {
                                val info = pm.getApplicationInfo(pkg, 0)
                                mapOf(
                                    "pkg" to pkg,
                                    "name" to pm.getApplicationLabel(info).toString(),
                                    "icon" to iconPng(pm.getApplicationIcon(info)),
                                )
                            } catch (_: Exception) {
                                null
                            }
                        }
                        .sortedBy { (it["name"] as String).lowercase() }
                } catch (e: Exception) {
                    emptyList()
                }
                runOnUiThread { result.success(list) }
            }.start()
            "setLocked" -> {
                appLock.lockedApps = (call.argument<List<String>>("apps") ?: emptyList()).toSet()
                result.success(null)
            }
            "setPin" -> {
                val pin = call.argument<String>("pin") ?: ""
                if (pin.length in 4..8 && pin.all { it.isDigit() }) {
                    appLock.setPin(pin)
                    result.success(true)
                } else {
                    result.success(false)
                }
            }
            "setBio" -> {
                appLock.useFingerprint = call.argument<Boolean>("on") == true
                result.success(null)
            }
            "setEnabled" -> {
                val on = call.argument<Boolean>("on") == true
                appLock.enabled = on
                try {
                    if (on) AppLockService.start(this) else AppLockService.stop(this)
                    result.success(true)
                } catch (e: Exception) {
                    appLock.enabled = false
                    result.success(false)
                }
            }
            "openUsageSettings" -> {
                openSettings(Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS))
                result.success(null)
            }
            "openOverlaySettings" -> {
                openSettings(
                    Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:$packageName"))
                )
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun openSettings(i: Intent) {
        try {
            startActivity(i)
        } catch (_: Exception) {
            startActivity(Intent(Settings.ACTION_SETTINGS))
        }
    }

    private fun iconPng(d: Drawable): ByteArray {
        val size = 96
        val bmp = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bmp)
        d.setBounds(0, 0, size, size)
        d.draw(canvas)
        val out = ByteArrayOutputStream()
        bmp.compress(Bitmap.CompressFormat.PNG, 100, out)
        return out.toByteArray()
    }

    private fun torchCameraId(): String? {
        val cm = getSystemService(CAMERA_SERVICE) as CameraManager
        return cm.cameraIdList.firstOrNull {
            cm.getCameraCharacteristics(it)
                .get(CameraCharacteristics.FLASH_INFO_AVAILABLE) == true
        }
    }

    private fun setTorch(on: Boolean) {
        val id = torchCameraId() ?: return
        (getSystemService(CAMERA_SERVICE) as CameraManager).setTorchMode(id, on)
    }

    override fun onDestroy() {
        try {
            setTorch(false)
        } catch (_: Exception) {
        }
        super.onDestroy()
    }

    // Class names come from the code namespace, not the install id (the debug
    // "Kryvo Dev" build is installed as com.farazlabs.kryvo.dev).
    private fun component(cls: String) =
        ComponentName(packageName, MainActivity::class.java.`package`!!.name + cls)

    private fun isEnabled(id: String): Boolean {
        val cls = icons[id] ?: return false
        return when (packageManager.getComponentEnabledSetting(component(cls))) {
            PackageManager.COMPONENT_ENABLED_STATE_ENABLED -> true
            PackageManager.COMPONENT_ENABLED_STATE_DISABLED -> false
            // Manifest default: only IconDefault starts enabled.
            else -> id == "default"
        }
    }

    private fun currentIcon(): String =
        icons.keys.firstOrNull { it != "default" && isEnabled(it) } ?: "default"

    private fun setIcon(id: String) {
        // Enable the new entry first so the app always has a launcher icon.
        packageManager.setComponentEnabledSetting(
            component(icons.getValue(id)),
            PackageManager.COMPONENT_ENABLED_STATE_ENABLED,
            PackageManager.DONT_KILL_APP
        )
        for ((other, cls) in icons) {
            if (other == id) continue
            packageManager.setComponentEnabledSetting(
                component(cls),
                PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
                PackageManager.DONT_KILL_APP
            )
        }
        // "Share to Kryvo" would reveal the vault in other apps' share menus,
        // so it is only offered while a Kryvo icon (not a disguise) is used.
        packageManager.setComponentEnabledSetting(
            component(".ShareTarget"),
            if (disguiseLabels.containsKey(id)) PackageManager.COMPONENT_ENABLED_STATE_DISABLED
            else PackageManager.COMPONENT_ENABLED_STATE_ENABLED,
            PackageManager.DONT_KILL_APP
        )
    }

    // ---- Share to Kryvo ------------------------------------------------------------

    private val pendingShared = mutableListOf<Map<String, String>>()
    private var mediaChannel: MethodChannel? = null

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleShare(intent)
    }

    /**
     * Photos / videos / audio shared from another app: copy them into Kryvo's
     * cache (they are encrypted and the copies deleted as soon as the user
     * unlocks and confirms), then tell the Flutter side.
     */
    private fun handleShare(intent: Intent?) {
        val action = intent?.action ?: return
        if (action != Intent.ACTION_SEND && action != Intent.ACTION_SEND_MULTIPLE) return
        val uris = mutableListOf<Uri>()
        if (action == Intent.ACTION_SEND) {
            @Suppress("DEPRECATION")
            (intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM))?.let { uris.add(it) }
        } else {
            @Suppress("DEPRECATION")
            intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)?.let { uris.addAll(it) }
        }
        // Handle each share only once (not again after a rotation / recreate).
        intent.action = null
        if (uris.isEmpty()) return
        Thread {
            val dir = File(cacheDir, "shared_in").apply { mkdirs() }
            val got = mutableListOf<Map<String, String>>()
            for ((i, uri) in uris.withIndex()) {
                try {
                    var name = "shared_${System.currentTimeMillis()}_$i"
                    contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
                        ?.use { c -> if (c.moveToFirst()) c.getString(0)?.let { name = it } }
                    val mime = contentResolver.getType(uri) ?: ""
                    val out = File(dir, "${System.nanoTime()}_${name.replace('/', '_')}")
                    contentResolver.openInputStream(uri)?.use { input ->
                        out.outputStream().use { input.copyTo(it) }
                    } ?: continue
                    got.add(mapOf("path" to out.path, "name" to name, "mime" to mime))
                } catch (_: Exception) {
                }
            }
            runOnUiThread {
                pendingShared.addAll(got)
                if (got.isNotEmpty()) mediaChannel?.invokeMethod("sharedReady", null)
            }
        }.start()
    }
}
