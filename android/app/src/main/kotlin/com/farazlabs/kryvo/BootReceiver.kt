package com.farazlabs.kryvo

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/** Turns App Lock back on after the phone restarts or Kryvo is updated. */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (AppLockStore(context).enabled) {
            try {
                AppLockService.start(context)
            } catch (_: Exception) {
            }
        }
    }
}
