**Web: closing a publication stops its audio recovery and silences its late errors.**
A retry, probe or timeout from a closed audio publication no longer emits an error after another publication opens.
An audio publication still loading when it is closed now resolves quietly instead of failing the next open.
Closing it no longer clears the next publication's system media controls.
A slow error check for a track the user has already left no longer stops the track now playing.
