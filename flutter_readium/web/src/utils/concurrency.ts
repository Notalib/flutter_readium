/**
 * Maps `items` with at most `limit` in-flight tasks, preserving input order.
 * `fn` must not throw for expected failures — return a sentinel instead — so a
 * single rejected fetch can't abort the batch.
 */
export async function mapWithConcurrency<T, R>(
  items: readonly T[],
  limit: number,
  fn: (item: T, index: number) => Promise<R>
): Promise<R[]> {
  const out: R[] = new Array(items.length);
  let next = 0;
  const workers = Array.from(
    { length: Math.min(limit, items.length) },
    async () => {
      for (;;) {
        const i = next++;
        if (i >= items.length) return;
        out[i] = await fn(items[i], i);
      }
    }
  );
  await Promise.all(workers);
  return out;
}

/** Max parallel narration/guided-navigation JSON fetches at startup. */
export const SIDECAR_FETCH_CONCURRENCY = 6;
