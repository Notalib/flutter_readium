package org.readium.lcp.sdk;

/** Mirrors the error object of the private EDRLab liblcp, which the Readium toolkit reads by reflection. */
public class DRMError {
    private final int code;

    public DRMError(int code) {
        this.code = code;
    }

    public int getCode() {
        return code;
    }
}
