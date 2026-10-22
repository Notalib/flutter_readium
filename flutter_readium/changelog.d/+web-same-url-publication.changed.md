**Web: loading or re-opening the open publication no longer replaces it, matching iOS and Android.**
`loadPublication` used to make the loaded book the current one, and `openPublication` with the open URL fetched and rebuilt it again. Now `loadPublication` never touches the open publication, and re-opening returns the open one; call `closePublication()` first to reload.
