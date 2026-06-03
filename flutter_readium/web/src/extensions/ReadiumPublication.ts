import { Profile, Publication } from "@readium/shared";

export class ReadiumPublication extends Publication {
  private conformsToArray = this.manifest.metadata.conformsTo;

  public conformsToEpub: boolean =
    this.conformsToArray?.some((profile) => {
      return profile == Profile.EPUB;
    }) ?? false;

  public conformsToAudiobook: boolean =
    this.conformsToArray?.some((profile) => {
      return profile == Profile.AUDIOBOOK;
    }) ?? false;

  public conformsToDivina: boolean =
    this.conformsToArray?.some((profile) => {
      return profile == Profile.DIVINA;
    }) ?? false;

  public conformsToPDF: boolean =
    this.conformsToArray?.some((profile) => {
      return profile == Profile.PDF;
    }) ?? false;
}
