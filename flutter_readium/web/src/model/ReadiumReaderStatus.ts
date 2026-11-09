export enum ReadiumReaderStatus {
  loading = "loading",
  ready = "ready",
  // Enum members are always accessed qualified, so this cannot shadow `window.closed`.
  // eslint-disable-next-line @typescript-eslint/no-shadow
  closed = "closed",
  reachedEndOfPublication = "reachedEndOfPublication",
  error = "error",
}
