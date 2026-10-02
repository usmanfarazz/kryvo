package com.farazlabs.kryvo

import android.content.Context
import android.util.Base64
import java.security.MessageDigest
import java.security.SecureRandom
import javax.crypto.SecretKeyFactory
import javax.crypto.spec.PBEKeySpec

/**
 * Settings for App Lock (locking OTHER apps on the phone): which apps are
 * locked, and the App Lock PIN — stored only as a salted PBKDF2 hash in the
 * app's private storage. Wrong PINs are rate-limited.
 */
class AppLockStore(context: Context) {
    private val prefs = context.getSharedPreferences("kryvo_app_lock", Context.MODE_PRIVATE)

    var enabled: Boolean
        get() = prefs.getBoolean("enabled", false)
        set(v) = prefs.edit().putBoolean("enabled", v).apply()

    var useFingerprint: Boolean
        get() = prefs.getBoolean("bio", true)
        set(v) = prefs.edit().putBoolean("bio", v).apply()

    var lockedApps: Set<String>
        get() = prefs.getStringSet("apps", emptySet())?.toSet() ?: emptySet()
        set(v) = prefs.edit().putStringSet("apps", v).apply()

    fun hasPin(): Boolean = prefs.contains("pinHash")

    /** Length of the App Lock PIN, so the lock screen can check it as soon as
     *  it is fully typed (like the phone's own lock screen). */
    val pinLength: Int
        get() = prefs.getInt("pinLen", 4)

    fun setPin(pin: String) {
        val salt = ByteArray(16).also { SecureRandom().nextBytes(it) }
        prefs.edit()
            .putString("pinSalt", Base64.encodeToString(salt, Base64.NO_WRAP))
            .putString("pinHash", Base64.encodeToString(hash(pin, salt), Base64.NO_WRAP))
            .putInt("pinLen", pin.length)
            .remove("fails").remove("until")
            .apply()
    }

    /** Seconds left in a wrong-PIN lockout (0 = can try). */
    fun lockoutLeft(): Int {
        val left = prefs.getLong("until", 0) - System.currentTimeMillis()
        return if (left > 0) ((left + 999) / 1000).toInt() else 0
    }

    fun checkPin(pin: String): Boolean {
        if (lockoutLeft() > 0) return false
        val salt = prefs.getString("pinSalt", null) ?: return false
        val stored = prefs.getString("pinHash", null) ?: return false
        val ok = MessageDigest.isEqual(
            hash(pin, Base64.decode(salt, Base64.NO_WRAP)),
            Base64.decode(stored, Base64.NO_WRAP)
        )
        if (ok) {
            prefs.edit().remove("fails").remove("until").apply()
        } else {
            val fails = prefs.getInt("fails", 0) + 1
            val e = prefs.edit().putInt("fails", fails)
            if (fails >= 5) {
                // 30 s, then 60 s, 120 s … for repeated failures
                val secs = 30L shl (fails - 5).coerceIn(0, 5)
                e.putLong("until", System.currentTimeMillis() + secs * 1000)
            }
            e.apply()
        }
        return ok
    }

    private fun hash(pin: String, salt: ByteArray): ByteArray {
        val spec = PBEKeySpec(pin.toCharArray(), salt, 20000, 256)
        return SecretKeyFactory.getInstance("PBKDF2WithHmacSHA256").generateSecret(spec).encoded
    }
}
