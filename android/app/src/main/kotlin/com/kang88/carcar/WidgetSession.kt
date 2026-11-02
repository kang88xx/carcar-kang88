package com.kang88.carcar

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import org.json.JSONObject
import java.net.URL
import java.security.KeyStore
import java.util.UUID
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/** Tokens are encrypted with a non-exportable, device-local key. Never log this object. */
object WidgetSession {
    private const val ALIAS = "carcar.widget.session.v1"
    private fun prefs(c: Context) = c.getSharedPreferences("carcar_widget_secure", Context.MODE_PRIVATE)
    private fun key(): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        return (store.getKey(ALIAS, null) as? SecretKey) ?: KeyGenerator.getInstance("AES", "AndroidKeyStore").apply {
            init(KeyGenParameterSpec.Builder(ALIAS, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build())
        }.generateKey()
    }
    @Synchronized fun read(c: Context): JSONObject? = try {
        prefs(c).getString("ciphertext", null)?.let {
            val bytes = Base64.decode(it, Base64.NO_WRAP)
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, bytes.copyOfRange(0, 12)))
            JSONObject(String(cipher.doFinal(bytes.copyOfRange(12, bytes.size)), Charsets.UTF_8))
        }
    } catch (_: Exception) { null }
    @Synchronized fun update(c: Context, args: Map<*, *>) {
        val value = JSONObject(args)
        val url = URL(value.getString("url"))
        require(url.protocol == "https" && url.userInfo == null && url.query == null && url.ref == null && url.path in listOf("", "/"))
        for (id in listOf("userId", "vehicleId")) UUID.fromString(value.getString(id))
        require(value.getLong("expiresAt") > System.currentTimeMillis() / 1000)
        val tokenParts = value.getString("accessToken").split('.')
        require(tokenParts.size == 3)
        val tokenClaims = JSONObject(String(Base64.decode(tokenParts[1], Base64.URL_SAFE or Base64.NO_WRAP or Base64.NO_PADDING)))
        require(tokenClaims.optString("role") == "authenticated" && tokenClaims.optString("sub") == value.getString("userId"))
        require(tokenClaims.getLong("exp") >= value.getLong("expiresAt"))
        val publicKey = value.getString("publishableKey")
        require(publicKey.isNotBlank() && !publicKey.startsWith("sb_secret_"))
        if (publicKey.split('.').size == 3) {
            val claims = JSONObject(String(Base64.decode(publicKey.split('.')[1], Base64.URL_SAFE or Base64.NO_WRAP or Base64.NO_PADDING)))
            require(claims.optString("role") == "anon")
        } else require(publicKey.startsWith("sb_publishable_"))
        for (field in listOf("floors", "zones")) {
            val values = value.getJSONArray(field)
            require(values.length() in 1..100)
            for (i in 0 until values.length()) require(values.getString(i).trim().let { it.isNotEmpty() && it.length <= 20 })
        }
        val old = read(c)
        val same = old != null && listOf("userId", "vehicleId", "url").all { old.optString(it) == value.optString(it) }
        value.put("generation", if (same) old!!.getString("generation") else UUID.randomUUID().toString())
        // Persist only the explicitly supported fields, never arbitrary caller secrets.
        val clean = JSONObject()
        for (name in listOf("url", "publishableKey", "accessToken", "expiresAt", "userId", "vehicleId", "floors", "zones", "generation")) clean.put(name, value.get(name))
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, key())
        check(prefs(c).edit().putString("ciphertext", Base64.encodeToString(cipher.iv + cipher.doFinal(clean.toString().toByteArray()), Base64.NO_WRAP)).commit())
        if (!same) WidgetActions.reset(c)
    }
    @Synchronized fun clear(c: Context) {
        check(prefs(c).edit().clear().commit())
        WidgetActions.reset(c)
    }
}
