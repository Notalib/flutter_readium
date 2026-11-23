**Web: closing a publication stops its audio recovery and silences its late errors.**
A retry, probe or timeout from a closed audio publication no longer emits an error after another publication opens.
An audio publication still loading when it is closed now resolves quietly instead of failing the next open.
