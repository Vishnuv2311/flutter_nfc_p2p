package dev.vishnuv.flutter_nfc_p2p

import android.app.Activity
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.nfc.NfcAdapter
import android.nfc.Tag
import android.nfc.cardemulation.CardEmulation
import android.nfc.tech.IsoDep
import android.os.Bundle
import android.provider.Settings
import android.util.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.io.IOException

class FlutterNfcP2pPlugin :
    FlutterPlugin,
    MethodCallHandler,
    ActivityAware,
    NfcAdapter.ReaderCallback,
    EventChannel.StreamHandler {

    companion object {
        private const val TAG = "FlutterNfcP2p"
        private const val METHOD_CHANNEL = "flutter_nfc_p2p/methods"
        private const val EVENT_CHANNEL = "flutter_nfc_p2p/events"

        /** Timeout for IsoDep transceive in ms */
        private const val TRANSCEIVE_TIMEOUT_MS = 5_000

        /** True while the host activity is in the foreground. Read by HceService. */
        @Volatile
        var isAppInForeground: Boolean = false
    }

    private lateinit var methodChannel: MethodChannel
    private lateinit var eventChannel: EventChannel
    private lateinit var appContext: Context

    private var activity: Activity? = null
    private var nfcAdapter: NfcAdapter? = null
    private var eventSink: EventChannel.EventSink? = null

    // -------------------------------------------------------------------------
    // FlutterPlugin lifecycle
    // -------------------------------------------------------------------------

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        appContext = binding.applicationContext
        methodChannel = MethodChannel(binding.binaryMessenger, METHOD_CHANNEL)
        methodChannel.setMethodCallHandler(this)
        eventChannel = EventChannel(binding.binaryMessenger, EVENT_CHANNEL)
        eventChannel.setStreamHandler(this)
        nfcAdapter = NfcAdapter.getDefaultAdapter(appContext)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
    }

    // -------------------------------------------------------------------------
    // ActivityAware lifecycle
    // -------------------------------------------------------------------------

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        isAppInForeground = true
    }

    override fun onDetachedFromActivityForConfigChanges() {
        isAppInForeground = false
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
        isAppInForeground = true
    }

    override fun onDetachedFromActivity() {
        stopReaderInternal()
        isAppInForeground = false
        activity = null
    }

    // -------------------------------------------------------------------------
    // EventChannel.StreamHandler
    // -------------------------------------------------------------------------

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    // -------------------------------------------------------------------------
    // MethodCallHandler
    // -------------------------------------------------------------------------

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "isNfcAvailable" -> result.success(isNfcAvailable())
            "startHce" -> {
                val token = call.argument<String>("token")
                if (token == null) {
                    result.error("INVALID_ARGUMENT", "token is required", null)
                    return
                }
                startHce(
                    token,
                    call.argument<String>("notificationTitle"),
                    call.argument<String>("notificationBody"),
                    result
                )
            }
            "stopHce" -> stopHce(result)
            "startReader" -> startReader(result)
            "stopReader" -> {
                stopReaderInternal()
                result.success(null)
            }
            "isDefaultHceService" -> result.success(isDefaultHceService())
            "setPreferredHceService" -> result.success(setPreferredHceService())
            "clearPreferredHceService" -> {
                clearPreferredHceService()
                result.success(null)
            }
            "openHceDefaultSettings" -> {
                openHceDefaultSettings()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    // -------------------------------------------------------------------------
    // HCE (Sender side)
    // -------------------------------------------------------------------------

    private fun startHce(
        token: String,
        notificationTitle: String?,
        notificationBody: String?,
        result: Result
    ) {
        val adapter = nfcAdapter
        if (adapter == null || !adapter.isEnabled) {
            result.error("NFC_UNAVAILABLE", "NFC is not available or disabled", null)
            return
        }
        if (!appContext.packageManager.hasSystemFeature("android.hardware.nfc.hce")) {
            result.error("HCE_UNSUPPORTED", "This device does not support HCE", null)
            return
        }

        HceService.currentToken = token

        // Persist token and optional notification text so HceService can use them
        // even if this process is killed.
        val notificationEnabled = notificationTitle != null || notificationBody != null
        appContext.getSharedPreferences(HceService.PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putString(HceService.PREFS_KEY_TOKEN, token)
            .putBoolean(HceService.PREFS_KEY_NOTIFICATION_ENABLED, notificationEnabled)
            .apply {
                if (notificationTitle != null)
                    putString(HceService.PREFS_KEY_NOTIFICATION_TITLE, notificationTitle)
                if (notificationBody != null)
                    putString(HceService.PREFS_KEY_NOTIFICATION_BODY, notificationBody)
            }
            .apply()

        sendEvent(mapOf("type" to "hceStarted"))
        result.success(null)
    }

    private fun stopHce(result: Result) {
        HceService.currentToken = null
        appContext.getSharedPreferences(HceService.PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .remove(HceService.PREFS_KEY_TOKEN)
            .remove(HceService.PREFS_KEY_NOTIFICATION_ENABLED)
            .apply()
        sendEvent(mapOf("type" to "hceStopped"))
        result.success(null)
    }

    // -------------------------------------------------------------------------
    // HCE service routing (foreground-preferred / default selection)
    // -------------------------------------------------------------------------

    private fun hceComponent() = ComponentName(appContext, HceService::class.java)

    private fun cardEmulation(): CardEmulation? {
        val adapter = nfcAdapter ?: return null
        return try {
            CardEmulation.getInstance(adapter)
        } catch (e: Exception) {
            Log.w(TAG, "CardEmulation unavailable: ${e.message}")
            null
        }
    }

    /**
     * Whether this app's HCE service is the system default for its AID category.
     * Only CATEGORY_PAYMENT has a notion of a default service; an "other"-category
     * service is always reachable, so we report true when the API doesn't apply.
     */
    private fun isDefaultHceService(): Boolean {
        val ce = cardEmulation() ?: return false
        return try {
            ce.isDefaultServiceForCategory(hceComponent(), CardEmulation.CATEGORY_PAYMENT)
        } catch (e: Exception) {
            Log.w(TAG, "isDefaultServiceForCategory failed: ${e.message}")
            false
        }
    }

    /**
     * Marks this app's HCE service as the foreground-preferred service so NFC taps
     * route here without a disambiguation dialog. Requires a resumed activity.
     */
    private fun setPreferredHceService(): Boolean {
        val ce = cardEmulation() ?: return false
        val act = activity ?: return false
        return try {
            ce.setPreferredService(act, hceComponent())
        } catch (e: Exception) {
            Log.w(TAG, "setPreferredService failed: ${e.message}")
            false
        }
    }

    private fun clearPreferredHceService() {
        val ce = cardEmulation() ?: return
        val act = activity ?: return
        try {
            ce.unsetPreferredService(act)
        } catch (e: Exception) {
            Log.w(TAG, "unsetPreferredService failed: ${e.message}")
        }
    }

    /** Opens the system NFC contactless-payment / default-app settings screen. */
    private fun openHceDefaultSettings() {
        val intent = Intent(Settings.ACTION_NFC_PAYMENT_SETTINGS)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        try {
            (activity ?: appContext).startActivity(intent)
        } catch (e: Exception) {
            Log.w(TAG, "ACTION_NFC_PAYMENT_SETTINGS failed, falling back: ${e.message}")
            try {
                (activity ?: appContext).startActivity(
                    Intent(Settings.ACTION_NFC_SETTINGS)
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                )
            } catch (e2: Exception) {
                Log.w(TAG, "ACTION_NFC_SETTINGS failed: ${e2.message}")
            }
        }
    }

    // -------------------------------------------------------------------------
    // Reader mode (Receiver side)
    // -------------------------------------------------------------------------

    private fun startReader(result: Result) {
        val adapter = nfcAdapter
        val act = activity

        if (adapter == null || !adapter.isEnabled) {
            result.error("NFC_UNAVAILABLE", "NFC is not available or disabled", null)
            return
        }
        if (act == null) {
            result.error("NO_ACTIVITY", "Plugin is not attached to an activity", null)
            return
        }

        val flags = NfcAdapter.FLAG_READER_NFC_A or
                NfcAdapter.FLAG_READER_NFC_B or
                NfcAdapter.FLAG_READER_SKIP_NDEF_CHECK

        val extras = Bundle()
        extras.putInt(NfcAdapter.EXTRA_READER_PRESENCE_CHECK_DELAY, 250)

        adapter.enableReaderMode(act, this, flags, extras)
        sendEvent(mapOf("type" to "listening"))
        result.success(null)
    }

    private fun stopReaderInternal() {
        try {
            activity?.let { nfcAdapter?.disableReaderMode(it) }
        } catch (e: Exception) {
            Log.w(TAG, "disableReaderMode failed: ${e.message}")
        }
    }

    // -------------------------------------------------------------------------
    // NfcAdapter.ReaderCallback — called on a background binder thread
    // -------------------------------------------------------------------------

    override fun onTagDiscovered(tag: Tag?) {
        if (tag == null) return
        sendEvent(mapOf("type" to "deviceDetected"))

        val isoDep = IsoDep.get(tag) ?: run {
            sendError("TAG_NOT_ISODEP", "Discovered tag does not support ISO-DEP")
            return
        }

        try {
            isoDep.connect()
            isoDep.timeout = TRANSCEIVE_TIMEOUT_MS

            val selectApdu = buildSelectApdu(HceService.NFC_AID)
            Log.d(TAG, "Sending SELECT APDU: ${selectApdu.toHex()}")

            val response = isoDep.transceive(selectApdu)
            Log.d(TAG, "APDU response: ${response.toHex()}")

            if (response.size < 2) {
                sendError("APDU_ERROR", "Response too short: ${response.toHex()}")
                return
            }

            val sw1 = response[response.size - 2].toInt() and 0xFF
            val sw2 = response[response.size - 1].toInt() and 0xFF

            if (sw1 == 0x90 && sw2 == 0x00) {
                val tokenBytes = response.copyOfRange(0, response.size - 2)
                val token = String(tokenBytes, Charsets.UTF_8)
                sendEvent(mapOf("type" to "tokenReceived", "token" to token))
            } else {
                sendError("APDU_SW_ERROR", "Status word: %02X%02X".format(sw1, sw2))
            }
        } catch (e: IOException) {
            sendError("IO_ERROR", "NFC communication error: ${e.message}")
        } finally {
            try { isoDep.close() } catch (_: IOException) {}
        }
    }

    // -------------------------------------------------------------------------
    // Helpers
    // -------------------------------------------------------------------------

    private fun isNfcAvailable(): Boolean {
        val adapter = nfcAdapter ?: return false
        return adapter.isEnabled
    }

    private fun buildSelectApdu(aid: ByteArray): ByteArray {
        return byteArrayOf(
            0x00.toByte(), // CLA
            0xA4.toByte(), // INS: SELECT
            0x04.toByte(), // P1: by DF name
            0x00.toByte(), // P2
            aid.size.toByte()  // Lc
        ) + aid + byteArrayOf(0x00) // Le
    }

    /**
     * Posts an event to the Flutter event stream.
     * Safe to call from any thread.
     */
    private fun sendEvent(event: Map<String, Any?>) {
        activity?.runOnUiThread {
            eventSink?.success(event)
        }
    }

    private fun sendError(code: String, message: String) {
        sendEvent(mapOf("type" to "error", "code" to code, "message" to message))
    }
}

private fun ByteArray.toHex(): String =
    joinToString(separator = "") { "%02X".format(it) }
