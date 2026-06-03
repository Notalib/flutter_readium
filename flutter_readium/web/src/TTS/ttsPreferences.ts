// Re-export shim — canonical location is preferences/FlutterTTSPreferences.ts
export {
  getAvailableVoicesAsync,
  ttsPreferencesFromJson,
  serializeVoices,
} from "../preferences/FlutterTTSPreferences";
export type { WebTTSPreferences } from "../preferences/FlutterTTSPreferences";
