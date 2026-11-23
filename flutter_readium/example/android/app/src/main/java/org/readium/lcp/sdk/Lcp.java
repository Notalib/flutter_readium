package org.readium.lcp.sdk;

import android.util.Base64;

import org.json.JSONObject;

import java.nio.charset.StandardCharsets;
import java.util.Arrays;

import javax.crypto.Cipher;
import javax.crypto.spec.IvParameterSpec;
import javax.crypto.spec.SecretKeySpec;

/**
 * Test-only stand-in for the private EDRLab liblcp. It supports only the LCP basic profile
 * (SHA-256 user key, AES-256-CBC) and does not check signatures or the CRL. The Readium toolkit
 * finds this class by reflection, so the names and signatures must stay as they are.
 * Never ship it: real apps use the licensed library.
 */
public class Lcp {
    private static final int ERR_USER_KEY_CHECK = 141;
    private static final int ERR_CONTENT_KEY_DECRYPT = 131;
    private static final int ERR_CONTENT_DECRYPT = 151;
    private static final int ERR_CONTEXT_INVALID = 121;

    public DRMContext createContext(String jsonLicense, String hashedPassphrase, String pemCrl) throws DRMException {
        try {
            JSONObject license = new JSONObject(jsonLicense);
            JSONObject encryption = license.getJSONObject("encryption");
            byte[] userKey = checkedUserKey(license, hashedPassphrase);
            String encryptedContentKey = encryption.getJSONObject("content_key").getString("encrypted_value");
            byte[] contentKey;
            try {
                contentKey = cbcDecrypt(userKey, Base64.decode(encryptedContentKey, Base64.DEFAULT), true);
            } catch (Exception e) {
                throw new DRMException(ERR_CONTENT_KEY_DECRYPT, String.valueOf(e));
            }
            return new DRMContext(
                    hashedPassphrase,
                    encryptedContentKey,
                    Base64.encodeToString(contentKey, Base64.NO_WRAP),
                    encryption.getString("profile"));
        } catch (DRMException e) {
            throw e;
        } catch (Exception e) {
            throw new DRMException(ERR_CONTEXT_INVALID, String.valueOf(e));
        }
    }

    /** Returns the IV-prefixed input decrypted, with the PKCS#7 padding left for the toolkit to strip. */
    public byte[] decrypt(DRMContext context, byte[] data) throws DRMException {
        try {
            byte[] contentKey = Base64.decode(context.getToken(), Base64.DEFAULT);
            return cbcDecrypt(contentKey, data, false);
        } catch (Exception e) {
            throw new DRMException(ERR_CONTENT_DECRYPT, String.valueOf(e));
        }
    }

    public String findOneValidPassphrase(String jsonLicense, String[] hashedPassphrases) throws DRMException {
        try {
            JSONObject license = new JSONObject(jsonLicense);
            for (String candidate : hashedPassphrases) {
                try {
                    checkedUserKey(license, candidate);
                    return candidate;
                } catch (DRMException ignored) {
                    // Try the next candidate.
                }
            }
        } catch (Exception ignored) {
            // Fall through to the error below.
        }
        throw new DRMException(ERR_USER_KEY_CHECK, "No valid passphrase");
    }

    private static byte[] checkedUserKey(JSONObject license, String hashedPassphrase) throws Exception {
        byte[] userKey = hexToBytes(hashedPassphrase);
        String keyCheck = license.getJSONObject("encryption").getJSONObject("user_key").getString("key_check");
        byte[] checked;
        try {
            checked = cbcDecrypt(userKey, Base64.decode(keyCheck, Base64.DEFAULT), true);
        } catch (Exception e) {
            throw new DRMException(ERR_USER_KEY_CHECK, "Bad user key");
        }
        if (!Arrays.equals(checked, license.getString("id").getBytes(StandardCharsets.UTF_8))) {
            throw new DRMException(ERR_USER_KEY_CHECK, "Bad user key");
        }
        return userKey;
    }

    /** Decrypts IV || ciphertext. Strips the PKCS#7 padding only when [unpad] is set. */
    private static byte[] cbcDecrypt(byte[] key, byte[] blob, boolean unpad) throws Exception {
        if (blob.length < 32 || blob.length % 16 != 0) {
            throw new IllegalArgumentException("Not a valid CBC blob: " + blob.length + " bytes");
        }
        Cipher cipher = Cipher.getInstance("AES/CBC/NoPadding");
        cipher.init(Cipher.DECRYPT_MODE, new SecretKeySpec(key, "AES"),
                new IvParameterSpec(Arrays.copyOfRange(blob, 0, 16)));
        byte[] padded = cipher.doFinal(blob, 16, blob.length - 16);
        if (!unpad) {
            return padded;
        }
        int pad = padded[padded.length - 1] & 0xff;
        if (pad < 1 || pad > 16) {
            throw new IllegalArgumentException("Bad padding");
        }
        return Arrays.copyOf(padded, padded.length - pad);
    }

    private static byte[] hexToBytes(String hex) {
        byte[] out = new byte[hex.length() / 2];
        for (int i = 0; i < out.length; i++) {
            out[i] = (byte) Integer.parseInt(hex.substring(2 * i, 2 * i + 2), 16);
        }
        return out;
    }
}
