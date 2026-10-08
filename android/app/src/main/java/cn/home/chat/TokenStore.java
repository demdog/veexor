package cn.home.chat;

import android.content.Context;
import android.security.keystore.KeyGenParameterSpec;
import android.security.keystore.KeyProperties;
import android.util.Base64;
import java.security.KeyStore;
import javax.crypto.Cipher;
import javax.crypto.KeyGenerator;
import javax.crypto.SecretKey;
import javax.crypto.spec.GCMParameterSpec;

final class TokenStore {
    private final Context context;
    TokenStore(Context context) { this.context = context; }
    private SecretKey key() throws Exception {
        KeyStore store = KeyStore.getInstance("AndroidKeyStore"); store.load(null);
        if (!store.containsAlias("home_token")) {
            KeyGenerator generator = KeyGenerator.getInstance("AES", "AndroidKeyStore");
            generator.init(new KeyGenParameterSpec.Builder("home_token", KeyProperties.PURPOSE_ENCRYPT | KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build());
            generator.generateKey();
        }
        return (SecretKey) store.getKey("home_token", null);
    }
    void save(String token) throws Exception {
        save("token", token);
    }
    void save(String name, String token) throws Exception {
        Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding"); cipher.init(Cipher.ENCRYPT_MODE, key());
        boolean saved = context.getSharedPreferences("secure", 0).edit()
            .putString(name + "_iv", Base64.encodeToString(cipher.getIV(), Base64.NO_WRAP))
            .putString(name, Base64.encodeToString(cipher.doFinal(token.getBytes(java.nio.charset.StandardCharsets.UTF_8)), Base64.NO_WRAP)).commit();
        if (!saved) throw new java.io.IOException("凭据未能保存，请检查手机存储空间");
    }
    String read() throws Exception {
        return read("token");
    }
    String read(String name) throws Exception {
        android.content.SharedPreferences p = context.getSharedPreferences("secure", 0);
        if (!p.contains(name)) return "";
        Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
        cipher.init(Cipher.DECRYPT_MODE, key(), new GCMParameterSpec(128, Base64.decode(p.getString(name + "_iv", p.getString("iv", "")), Base64.NO_WRAP)));
        return new String(cipher.doFinal(Base64.decode(p.getString(name, ""), Base64.NO_WRAP)), java.nio.charset.StandardCharsets.UTF_8);
    }
}
