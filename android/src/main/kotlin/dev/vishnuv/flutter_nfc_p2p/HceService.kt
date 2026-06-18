package dev.vishnuv.flutter_nfc_p2p

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.nfc.cardemulation.HostApduService
import android.os.Build
import android.os.Bundle
import android.util.Log
import androidx.core.app.NotificationCompat

/**
 * Host Card Emulation service — runs on the Sender (payer) device.
 *
 * When a reader sends a SELECT AID APDU addressed to our custom AID,
 * this service responds with the stored token followed by SW 90 00 (success).
 *
 * Token lookup order:
 *   1. In-memory [currentToken] — set when the app is open.
 *   2. SharedPreferences — survives the app being killed or backgrounded,
 *      so the payer can tap without reopening the app.
 */
class HceService : HostApduService() {

    companion object {
        private const val TAG = "HceService"
        internal const val PREFS_NAME = "dev.vishnuv.flutter_nfc_p2p.hce_prefs"
        internal const val PREFS_KEY_TOKEN = "hce_token"
        internal const val PREFS_KEY_NOTIFICATION_ENABLED = "notification_enabled"
        internal const val PREFS_KEY_NOTIFICATION_TITLE = "notification_title"
        internal const val PREFS_KEY_NOTIFICATION_BODY = "notification_body"
        private const val NOTIFICATION_CHANNEL_ID = "dev.vishnuv.flutter_nfc_p2p.payment"
        private const val NOTIFICATION_ID = 1001

        /** Proprietary AID — must match apdu_service.xml */
        val NFC_AID: ByteArray = byteArrayOf(
            0xF0.toByte(), 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07
        )

        private val SELECT_APDU_HEADER = byteArrayOf(
            0x00.toByte(), // CLA
            0xA4.toByte(), // INS: SELECT
            0x04.toByte(), // P1: by DF name
            0x00.toByte()  // P2
        )

        private val SW_SUCCESS = byteArrayOf(0x90.toByte(), 0x00)
        private val SW_UNKNOWN = byteArrayOf(0x6F.toByte(), 0x00)
        private val SW_AID_NOT_FOUND = byteArrayOf(0x6A.toByte(), 0x82.toByte())

        /** Fast in-memory token — valid while the app process is alive. */
        @Volatile
        var currentToken: String? = null
    }

    private var lastTapSucceeded = false

    override fun processCommandApdu(commandApdu: ByteArray, extras: Bundle?): ByteArray {
        Log.d(TAG, "Received APDU: ${commandApdu.toHex()}")

        if (!isSelectAid(commandApdu)) {
            Log.w(TAG, "Unknown APDU command")
            return SW_UNKNOWN
        }

        // Prefer in-memory; fall back to SharedPreferences (app not in foreground).
        val token = currentToken
            ?: applicationContext
                .getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                .getString(PREFS_KEY_TOKEN, null)

        if (token == null) {
            Log.w(TAG, "SELECT received but no token available")
            lastTapSucceeded = false
            return SW_AID_NOT_FOUND
        }

        Log.d(TAG, "SELECT AID matched — returning token")
        lastTapSucceeded = true
        return token.toByteArray(Charsets.UTF_8) + SW_SUCCESS
    }

    override fun onDeactivated(reason: Int) {
        val reasonStr = if (reason == DEACTIVATION_LINK_LOSS) "LINK_LOSS" else "DESELECTED"
        Log.d(TAG, "HCE deactivated: $reasonStr")

        val notificationEnabled = applicationContext
            .getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getBoolean(PREFS_KEY_NOTIFICATION_ENABLED, false)

        if (lastTapSucceeded && !FlutterNfcP2pPlugin.isAppInForeground && notificationEnabled) {
            showPaymentSentNotification()
        }
        lastTapSucceeded = false
    }

    private fun showPaymentSentNotification() {
        val ctx = applicationContext
        val prefs = ctx.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val title = prefs.getString(PREFS_KEY_NOTIFICATION_TITLE, "Payment Sent") ?: "Payment Sent"
        val body = prefs.getString(PREFS_KEY_NOTIFICATION_BODY, "Tap to open") ?: "Tap to open"

        val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            nm.createNotificationChannel(
                NotificationChannel(
                    NOTIFICATION_CHANNEL_ID,
                    "Payment Notifications",
                    NotificationManager.IMPORTANCE_DEFAULT
                )
            )
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            if (ctx.checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS)
                != PackageManager.PERMISSION_GRANTED
            ) return
        }

        val launchIntent = ctx.packageManager
            .getLaunchIntentForPackage(ctx.packageName)
            ?.apply { flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP }

        val pendingIntent = launchIntent?.let {
            PendingIntent.getActivity(
                ctx, 0, it,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
        }

        val notification = NotificationCompat.Builder(ctx, NOTIFICATION_CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_popup_reminder)
            .setContentTitle(title)
            .setContentText(body)
            .setAutoCancel(true)
            .apply { pendingIntent?.let { pi -> setContentIntent(pi) } }
            .build()

        nm.notify(NOTIFICATION_ID, notification)
    }

    private fun isSelectAid(apdu: ByteArray): Boolean {
        if (apdu.size < SELECT_APDU_HEADER.size + 1) return false
        for (i in SELECT_APDU_HEADER.indices) {
            if (apdu[i] != SELECT_APDU_HEADER[i]) return false
        }
        val lcIndex = SELECT_APDU_HEADER.size
        val lc = apdu[lcIndex].toInt() and 0xFF
        if (apdu.size < lcIndex + 1 + lc) return false
        val aidInApdu = apdu.copyOfRange(lcIndex + 1, lcIndex + 1 + lc)
        return aidInApdu.contentEquals(NFC_AID)
    }
}

private fun ByteArray.toHex(): String =
    joinToString(separator = "") { "%02X".format(it) }
