package dev.vishnuv.flutter_nfc_p2p

import android.content.Context
import android.nfc.cardemulation.HostApduService
import android.os.Bundle
import android.util.Log

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
            return SW_AID_NOT_FOUND
        }

        Log.d(TAG, "SELECT AID matched — returning token")
        return token.toByteArray(Charsets.UTF_8) + SW_SUCCESS
    }

    override fun onDeactivated(reason: Int) {
        val reasonStr = if (reason == DEACTIVATION_LINK_LOSS) "LINK_LOSS" else "DESELECTED"
        Log.d(TAG, "HCE deactivated: $reasonStr")
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
