package org.readium.lcp.sdk;

public class DRMContext {
    private final String hashedPassphrase;
    private final String encryptedContentKey;
    private final String token;
    private final String profile;

    public DRMContext(String hashedPassphrase, String encryptedContentKey, String token, String profile) {
        this.hashedPassphrase = hashedPassphrase;
        this.encryptedContentKey = encryptedContentKey;
        this.token = token;
        this.profile = profile;
    }

    public String getHashedPassphrase() {
        return hashedPassphrase;
    }

    public String getEncryptedContentKey() {
        return encryptedContentKey;
    }

    /** Holds the base64 content key, so decrypt() needs no license. */
    public String getToken() {
        return token;
    }

    public String getProfile() {
        return profile;
    }
}
