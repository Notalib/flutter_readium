/**
 * Converts a Dart Color hex string from AARRGGBB to CSS RRGGBBAA format.
 * Dart's Color.toCSS() emits '#AARRGGBB'; CSS expects '#RRGGBBAA'.
 * Shorter or non-hex formats (e.g. '#RGB', '#RRGGBB', named colors) are returned unchanged.
 */
export function dartColorToCss(color: string): string {
  if (/^#[0-9a-fA-F]{8}$/.test(color)) {
    return "#" + color.slice(3) + color.slice(1, 3);
  }
  return color;
}
