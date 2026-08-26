package com.fangchen.dshmobile;

import android.content.Context;
import android.content.SharedPreferences;
import android.security.keystore.KeyGenParameterSpec;
import android.security.keystore.KeyProperties;
import android.util.Base64;

import java.nio.ByteBuffer;
import java.nio.charset.StandardCharsets;
import java.security.KeyStore;

import javax.crypto.Cipher;
import javax.crypto.KeyGenerator;
import javax.crypto.SecretKey;
import javax.crypto.spec.GCMParameterSpec;

public final class SecureStore {
    private static final String KEY_ALIAS = "dsh_mobile_pairing_key";
    private static final String PREFS = "dsh_mobile_secure";
    private static final String VALUE = "connection";

    private final SharedPreferences preferences;

    public SecureStore(Context context) {
        preferences = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
    }

    public void save(RemoteConnection connection) throws Exception {
        Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
        cipher.init(Cipher.ENCRYPT_MODE, key());
        byte[] encrypted = cipher.doFinal(connection.toJson().toString().getBytes(StandardCharsets.UTF_8));
        byte[] iv = cipher.getIV();
        ByteBuffer packed = ByteBuffer.allocate(4 + iv.length + encrypted.length);
        packed.putInt(iv.length).put(iv).put(encrypted);
        preferences.edit().putString(VALUE, Base64.encodeToString(packed.array(), Base64.NO_WRAP)).apply();
    }

    public RemoteConnection load() {
        String saved = preferences.getString(VALUE, null);
        if (saved == null) return null;
        try {
            ByteBuffer packed = ByteBuffer.wrap(Base64.decode(saved, Base64.NO_WRAP));
            int ivLength = packed.getInt();
            if (ivLength < 12 || ivLength > 16 || packed.remaining() <= ivLength) throw new IllegalStateException("Invalid encrypted data");
            byte[] iv = new byte[ivLength];
            packed.get(iv);
            byte[] encrypted = new byte[packed.remaining()];
            packed.get(encrypted);
            Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
            cipher.init(Cipher.DECRYPT_MODE, key(), new GCMParameterSpec(128, iv));
            String json = new String(cipher.doFinal(encrypted), StandardCharsets.UTF_8);
            return RemoteConnection.fromJson(json);
        } catch (Exception ignored) {
            clear();
            return null;
        }
    }

    public void clear() {
        preferences.edit().remove(VALUE).apply();
    }

    private SecretKey key() throws Exception {
        KeyStore store = KeyStore.getInstance("AndroidKeyStore");
        store.load(null);
        KeyStore.Entry existing = store.getEntry(KEY_ALIAS, null);
        if (existing instanceof KeyStore.SecretKeyEntry) {
            return ((KeyStore.SecretKeyEntry) existing).getSecretKey();
        }
        KeyGenerator generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore");
        generator.init(new KeyGenParameterSpec.Builder(
                KEY_ALIAS,
                KeyProperties.PURPOSE_ENCRYPT | KeyProperties.PURPOSE_DECRYPT
        ).setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .build());
        return generator.generateKey();
    }
}

