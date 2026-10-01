package com.edde746.plezy

import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.util.Log
import androidx.core.content.pm.ShortcutInfoCompat
import androidx.core.content.pm.ShortcutManagerCompat
import androidx.core.graphics.drawable.IconCompat
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Opens the app as a specific profile from a `plezy://profile` link, and pins
 * launcher shortcuts that carry one.
 *
 * `plezy://profile?id=<profileId>` matches a profile id exactly (what pinned
 * shortcuts use); `plezy://profile?name=<displayName>` matches a profile name
 * case-insensitively, for automation (`am start -a android.intent.action.VIEW
 * -d "plezy://profile?name=Kids"`). Resolution happens on the Dart side.
 */
class LaunchProfilePlugin :
  FlutterPlugin,
  MethodChannel.MethodCallHandler {
  companion object {
    private const val TAG = "LaunchProfilePlugin"
    private const val METHOD_CHANNEL = "com.plezy/launch_profile"
    private const val HOST = "profile"
    private const val ICON_SIZE_PX = 192
    private var pendingLink: Map<String, String>? = null

    /** Returns the `{id?, name?}` payload of a `plezy://profile` link, or null. */
    fun handleIntent(intent: Intent?): Map<String, String>? {
      val data = intent?.data ?: return null
      if (data.scheme != "plezy" || data.authority != HOST) return null
      val id = data.getQueryParameter("id")?.takeIf(String::isNotBlank)
      val name = data.getQueryParameter("name")?.takeIf(String::isNotBlank)
      if (id == null && name == null) return null
      return buildMap {
        id?.let { put("id", it) }
        name?.let { put("name", it) }
      }
    }

    fun buildLinkUri(profileId: String): Uri =
      Uri.Builder().scheme("plezy").authority(HOST).appendQueryParameter("id", profileId).build()
  }

  private lateinit var methodChannel: MethodChannel
  private var applicationContext: Context? = null

  override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    applicationContext = binding.applicationContext
    methodChannel = MethodChannel(binding.binaryMessenger, METHOD_CHANNEL)
    methodChannel.setMethodCallHandler(this)
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    methodChannel.setMethodCallHandler(null)
    applicationContext = null
  }

  override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
    when (call.method) {
      "getInitialProfileLink" -> {
        val link = pendingLink
        pendingLink = null
        result.success(link)
      }
      "isPinShortcutSupported" -> {
        val context = applicationContext
        result.success(context != null && ShortcutManagerCompat.isRequestPinShortcutSupported(context))
      }
      "requestPinShortcut" -> handleRequestPinShortcut(call, result)
      else -> result.notImplemented()
    }
  }

  private fun handleRequestPinShortcut(call: MethodCall, result: MethodChannel.Result) {
    val context = applicationContext
    val profileId = call.argument<String>("profileId")?.takeIf(String::isNotBlank)
    val label = call.argument<String>("label")?.takeIf(String::isNotBlank)
    if (context == null || profileId == null || label == null) {
      result.error("INVALID_ARGS", "profileId and label are required", null)
      return
    }
    if (!ShortcutManagerCompat.isRequestPinShortcutSupported(context)) {
      result.success(false)
      return
    }
    val intent = Intent(Intent.ACTION_VIEW, buildLinkUri(profileId)).setClass(context, MainActivity::class.java)
    val icon = call.argument<ByteArray>("icon")?.let(::decodeIcon)
      ?: IconCompat.createWithResource(context, R.mipmap.ic_launcher)
    val shortcut = ShortcutInfoCompat.Builder(context, "profile:$profileId")
      .setShortLabel(label)
      .setLongLabel(label)
      .setIcon(icon)
      .setIntent(intent)
      .build()
    try {
      result.success(ShortcutManagerCompat.requestPinShortcut(context, shortcut, null))
    } catch (e: IllegalStateException) {
      // Thrown when the app is not in the foreground.
      Log.w(TAG, "Pin shortcut request rejected", e)
      result.success(false)
    }
  }

  /** Center-crops the avatar to a square launcher-sized bitmap. */
  private fun decodeIcon(bytes: ByteArray): IconCompat? {
    val source = BitmapFactory.decodeByteArray(bytes, 0, bytes.size) ?: return null
    val side = minOf(source.width, source.height)
    val square = Bitmap.createBitmap(source, (source.width - side) / 2, (source.height - side) / 2, side, side)
    val scaled = Bitmap.createScaledBitmap(square, ICON_SIZE_PX, ICON_SIZE_PX, true)
    return IconCompat.createWithBitmap(scaled)
  }

  fun notifyProfileLink(link: Map<String, String>) {
    pendingLink = link
    try {
      methodChannel.invokeMethod(
        "onProfileLink",
        link,
        object : MethodChannel.Result {
          // Dart answers true only once a live profile session took the link;
          // until then it stays pending for getInitialProfileLink.
          override fun success(result: Any?) {
            if (result == true && pendingLink === link) pendingLink = null
          }

          override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {}

          override fun notImplemented() {}
        }
      )
    } catch (_: Exception) {
      Log.d(TAG, "Method channel not ready; profile link retained")
    }
  }
}
