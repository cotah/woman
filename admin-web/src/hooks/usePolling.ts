import { useEffect, useRef, useCallback } from 'react';

/**
 * Polls a callback at a fixed interval. Stops when the component unmounts.
 * Returns a manual refresh function.
 */
export function usePolling(
  callback: () => void | Promise<void>,
  intervalMs: number = 15000,
  enabled: boolean = true
): { refresh: () => void } {
  const savedCallback = useRef(callback);

  useEffect(() => {
    savedCallback.current = callback;
  }, [callback]);

  useEffect(() => {
    if (!enabled) return;

    const tick = () => savedCallback.current();
    const id = setInterval(tick, intervalMs);
    return () => clearInterval(id);
  }, [intervalMs, enabled]);

  const refresh = useCallback(() => {
    savedCallback.current();
  }, []);

  return { refresh };
}
