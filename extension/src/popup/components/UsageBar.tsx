import { useEffect, useState } from 'preact/hooks';

interface Props {
  label: string;
  utilization: number;
  pace: number;
  sublabel: string;
  /** When true, paints with the long-window color (brand-300 / brand-500). */
  isLong?: boolean;
}

const BAR_HEIGHT = 6;
const BAR_FILL_MS = 500;

function prefersReducedMotion(): boolean {
  return typeof matchMedia === 'function' && matchMedia('(prefers-reduced-motion: reduce)').matches;
}

/** Rolls the number up with the bar fill (brand Bars curve, approximated). */
function useCountUp(target: number, duration: number): number {
  const [value, setValue] = useState(prefersReducedMotion() ? target : 0);
  useEffect(() => {
    if (prefersReducedMotion()) { setValue(target); return; }
    let frame = 0;
    const from = value;
    const start = performance.now();
    const tick = (now: number) => {
      const t = Math.min((now - start) / duration, 1);
      const eased = 1 - Math.pow(1 - t, 2.2);
      setValue(Math.round(from + (target - from) * eased));
      if (t < 1) frame = requestAnimationFrame(tick);
    };
    frame = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(frame);
  }, [target]);
  return value;
}

function clamp(value: number, min: number, max: number): number {
  return Math.min(Math.max(value, min), max);
}

export function UsageBar({ label, utilization, pace, sublabel, isLong = false }: Props) {
  const target = clamp(utilization / 100, 0, 1);
  const clampedPace = clamp(pace, 0, 1);
  const showPaceMarker = clampedPace > 0.01 && clampedPace < 0.99;

  // Same choreography as the Mac popover: the fill grows in 500ms while the
  // pace dot slides in over 800ms (CSS), so the dot lands last and draws the eye.
  const [animated, setAnimated] = useState(0);
  const [animatedPace, setAnimatedPace] = useState(0);
  useEffect(() => {
    const id = requestAnimationFrame(() => {
      setAnimated(target);
      setAnimatedPace(clampedPace);
    });
    return () => cancelAnimationFrame(id);
  }, [target, clampedPace]);
  const shownPercent = useCountUp(Math.round(utilization), BAR_FILL_MS);

  return (
    <div class={`usage-bar${isLong ? ' usage-bar--long' : ''}`}>
      <div class="usage-bar__header">
        <span class="usage-bar__label">{label}</span>
        <span class="usage-bar__value">{shownPercent}%</span>
      </div>

      <div class="usage-bar__track">
        <div
          class="usage-bar__fill"
          style={{ width: `${animated * 100}%` }}
        />
        {showPaceMarker ? (
          <div
            class="usage-bar__pace"
            style={{ left: `calc(${animatedPace * 100}% - ${BAR_HEIGHT / 2}px)` }}
          />
        ) : null}
      </div>

      <span class="usage-bar__sublabel">{sublabel}</span>
    </div>
  );
}
