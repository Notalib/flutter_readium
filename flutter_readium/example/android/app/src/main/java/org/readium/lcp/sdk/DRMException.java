package org.readium.lcp.sdk;

public class DRMException extends Exception {
    private final DRMError drmError;

    public DRMException(int code, String message) {
        super(message);
        this.drmError = new DRMError(code);
    }

    public DRMError getDrmError() {
        return drmError;
    }
}
