package com.farazlabs.kryvo

import android.content.Intent
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.widget.Button
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import androidx.activity.OnBackPressedCallback
import androidx.biometric.BiometricManager
import androidx.biometric.BiometricPrompt
import androidx.core.content.ContextCompat
import androidx.fragment.app.FragmentActivity

/**
 * Lock screen shown over a locked app. The user must enter the App Lock PIN
 * (or use fingerprint) to continue; Back / Home take them to the home screen
 * instead of the app.
 */
class AppLockActivity : FragmentActivity() {
    companion object {
        const val EXTRA_PKG = "pkg"
        private const val BG = 0xFF0B0F17.toInt()
        private const val PANEL = 0xFF1A2230.toInt()
        private const val ACCENT = 0xFF4F8CFF.toInt()
        private const val MUTED = 0xFF93A1B5.toInt()
        private const val BAD = 0xFFFF5C6C.toInt()
    }

    private lateinit var store: AppLockStore
    private var pkg: String = ""
    private var pin = ""

    private lateinit var icon: ImageView
    private lateinit var name: TextView
    private lateinit var dots: TextView
    private lateinit var message: TextView

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        store = AppLockStore(this)
        window.statusBarColor = BG
        window.navigationBarColor = BG
        setContentView(buildUi())
        onBackPressedDispatcher.addCallback(this, object : OnBackPressedCallback(true) {
            override fun handleOnBackPressed() = goHome()
        })
        load(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        load(intent)
    }

    override fun onStop() {
        super.onStop()
        // Left without unlocking (Home / recents): close; it shows again
        // next time the locked app is opened.
        if (!isFinishing) finish()
    }

    private fun load(i: Intent) {
        pkg = i.getStringExtra(EXTRA_PKG) ?: ""
        pin = ""
        try {
            val info = packageManager.getApplicationInfo(pkg, 0)
            name.text = packageManager.getApplicationLabel(info)
            icon.setImageDrawable(packageManager.getApplicationIcon(info))
        } catch (_: Exception) {
            name.text = pkg
        }
        if (!store.hasPin()) {
            // Not set up properly: don't trap the user.
            unlocked()
            return
        }
        render(null)
        if (store.useFingerprint) askFingerprint()
    }

    private fun dp(v: Int) = TypedValue.applyDimension(
        TypedValue.COMPLEX_UNIT_DIP, v.toFloat(), resources.displayMetrics
    ).toInt()

    private fun buildUi(): View {
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            setBackgroundColor(BG)
            setPadding(dp(24), dp(56), dp(24), dp(24))
        }
        icon = ImageView(this)
        root.addView(icon, LinearLayout.LayoutParams(dp(72), dp(72)))
        name = TextView(this).apply {
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 22f)
            gravity = Gravity.CENTER
            setPadding(0, dp(12), 0, 0)
        }
        root.addView(name)
        root.addView(TextView(this).apply {
            text = "Locked by Kryvo · enter your App Lock PIN"
            setTextColor(MUTED)
            gravity = Gravity.CENTER
            setPadding(0, dp(6), 0, dp(18))
        })
        dots = TextView(this).apply {
            setTextColor(ACCENT)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 30f)
            gravity = Gravity.CENTER
            letterSpacing = 0.4f
        }
        root.addView(dots)
        message = TextView(this).apply {
            setTextColor(BAD)
            gravity = Gravity.CENTER
            setPadding(0, dp(6), 0, dp(10))
        }
        root.addView(message)

        val rows = listOf(
            listOf("1", "2", "3"), listOf("4", "5", "6"),
            listOf("7", "8", "9"), listOf("bio", "0", "<")
        )
        for (row in rows) {
            val line = LinearLayout(this).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER
            }
            for (k in row) line.addView(key(k))
            root.addView(line)
        }
        return root
    }

    private fun key(k: String): View {
        val size = dp(76)
        val b = Button(this).apply {
            isAllCaps = false
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, if (k.length == 1 && k != "<") 26f else 16f)
            text = when (k) {
                "<" -> "⌫"
                "bio" -> if (canUseFingerprint()) "👆" else ""
                else -> k
            }
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(if (k == "bio" && !canUseFingerprint()) BG else PANEL)
            }
            stateListAnimator = null
            setOnClickListener {
                when (k) {
                    "<" -> if (pin.isNotEmpty()) pin = pin.dropLast(1)
                    "bio" -> if (canUseFingerprint()) askFingerprint()
                    else -> if (pin.length < 8) pin += k
                }
                render(null)
                if (k != "<" && k != "bio" && pin.length == store.pinLength) tryPin()
            }
            setOnLongClickListener {
                if (k == "<") {
                    pin = ""
                    render(null)
                }
                true
            }
        }
        return b.also {
            it.layoutParams = LinearLayout.LayoutParams(size, size).apply {
                setMargins(dp(10), dp(7), dp(10), dp(7))
            }
        }
    }

    private fun render(error: String?) {
        dots.text = "●".repeat(pin.length) +
            "○".repeat((store.pinLength - pin.length).coerceAtLeast(0))
        val wait = store.lockoutLeft()
        message.text = error ?: if (wait > 0) "Too many tries. Wait $wait s." else ""
    }

    /** Checked as soon as the PIN has its full length; every miss counts. */
    private fun tryPin() {
        if (store.lockoutLeft() > 0) {
            pin = ""
            render(null)
            return
        }
        if (store.checkPin(pin)) {
            unlocked()
        } else {
            pin = ""
            render("Wrong PIN")
        }
    }

    private fun unlocked() {
        AppLockService.unlockedPkg = pkg
        // This screen runs in its own task, so just closing it would drop the
        // user on the home screen. Bring the unlocked app back to the front
        // (the same intent the launcher uses resumes it where it was).
        try {
            packageManager.getLaunchIntentForPackage(pkg)?.let {
                it.addFlags(
                    Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED
                )
                startActivity(it)
            }
        } catch (_: Exception) {
        }
        finish()
        overridePendingTransition(0, 0)
    }

    private fun goHome() {
        startActivity(
            Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        )
        finish()
    }

    private fun canUseFingerprint(): Boolean =
        store.useFingerprint && BiometricManager.from(this).canAuthenticate(
            BiometricManager.Authenticators.BIOMETRIC_WEAK
        ) == BiometricManager.BIOMETRIC_SUCCESS

    private fun askFingerprint() {
        if (!canUseFingerprint()) return
        // Wait a moment so the prompt appears over this screen, not under it.
        Handler(Looper.getMainLooper()).postDelayed({
            if (isFinishing) return@postDelayed
            val prompt = BiometricPrompt(this, ContextCompat.getMainExecutor(this),
                object : BiometricPrompt.AuthenticationCallback() {
                    override fun onAuthenticationSucceeded(
                        result: BiometricPrompt.AuthenticationResult
                    ) = unlocked()
                })
            prompt.authenticate(
                BiometricPrompt.PromptInfo.Builder()
                    .setTitle("Unlock ${name.text}")
                    .setNegativeButtonText("Use PIN")
                    .setAllowedAuthenticators(BiometricManager.Authenticators.BIOMETRIC_WEAK)
                    .build()
            )
        }, 250)
    }
}
