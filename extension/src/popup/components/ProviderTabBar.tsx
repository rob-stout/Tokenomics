import { useEffect, useRef, useState } from 'preact/hooks';
import { dropIndex } from '../../provider-order';
import { PROVIDER_META, type ProviderId } from '../../types';

const IS_MAC = /Mac/i.test(navigator.platform);

interface Props {
  selected: ProviderId;
  /** Ordered list of visible provider IDs to render as tabs. */
  visibleProviderIds: readonly ProviderId[];
  onSelect: (provider: ProviderId) => void;
  /** Show every tab as its site name (no logos). The bar scrolls sideways. */
  textLabels?: boolean;
  /** ⌘-drag (Ctrl-drag off Mac) reorder (same gesture as the Mac popover). Gets the new visible order on drop. */
  onReorder?: (visibleOrder: ProviderId[], moved: ProviderId) => void;
}


export function ProviderTabBar({ selected, visibleProviderIds, onSelect, textLabels = false, onReorder }: Props) {
  const barRef = useRef<HTMLDivElement>(null);
  const [dragged, setDragged] = useState<ProviderId | null>(null);
  const [preview, setPreview] = useState<ProviderId[] | null>(null);
  const justDragged = useRef(false);
  const ids = preview ?? visibleProviderIds;

  const handlePointerDown = (e: PointerEvent, provider: ProviderId) => {
    // ⌘ on Mac; Ctrl elsewhere (Ctrl-click on a Mac is a right-click).
    if (!onReorder || !(IS_MAC ? e.metaKey : e.ctrlKey) || e.button !== 0) return;
    (e.currentTarget as HTMLElement).setPointerCapture(e.pointerId);
    setDragged(provider);
    setPreview([...visibleProviderIds]);
  };

  const handlePointerMove = (e: PointerEvent) => {
    if (!dragged || !preview || !barRef.current) return;
    const tabs = Array.from(barRef.current.querySelectorAll<HTMLElement>('[data-provider]'));
    const mids = tabs
      .filter((t) => t.dataset.provider !== dragged)
      .map((t) => {
        const r = t.getBoundingClientRect();
        return r.left + r.width / 2;
      });
    const to = dropIndex(mids, e.clientX);
    if (preview.indexOf(dragged) === to) return;
    const next = preview.filter((id) => id !== dragged);
    next.splice(to, 0, dragged);
    setPreview(next);
  };

  const handlePointerUp = () => {
    if (!dragged) return;
    const movedId = dragged;
    const finalOrder = preview;
    setDragged(null);
    setPreview(null);
    const moved = !!finalOrder && finalOrder.join() !== visibleProviderIds.join();
    justDragged.current = moved; // swallow the click that follows a drop
    if (moved && finalOrder) onReorder?.(finalOrder, movedId);
  };

  // Fade the edge(s) with more tabs past them, the hint that the strip scrolls.
  const [fade, setFade] = useState<'none' | 'left' | 'right' | 'both'>('none');
  const updateFade = () => {
    const bar = barRef.current;
    if (!bar) return;
    const left = bar.scrollLeft > 1;
    const right = bar.scrollLeft + bar.clientWidth < bar.scrollWidth - 1;
    setFade(left && right ? 'both' : left ? 'left' : right ? 'right' : 'none');
  };
  useEffect(() => {
    updateFade();
    window.addEventListener('resize', updateFade);
    return () => window.removeEventListener('resize', updateFade);
  }, [visibleProviderIds.length, selected, textLabels]);

  // When the tabs overflow and scroll, keep the selected one in view.
  useEffect(() => {
    barRef.current
      ?.querySelector<HTMLElement>('[aria-selected="true"]')
      ?.scrollIntoView({ inline: 'center', block: 'nearest', behavior: 'smooth' }); // matches the Mac's animated centering
  }, [textLabels, selected, visibleProviderIds.length]);

  // Let a plain mouse wheel scroll the bar sideways (trackpads already can).
  const handleWheel = (e: WheelEvent) => {
    const bar = barRef.current;
    if (!bar || bar.scrollWidth <= bar.clientWidth || Math.abs(e.deltaY) <= Math.abs(e.deltaX)) return;
    bar.scrollLeft += e.deltaY;
    e.preventDefault();
  };

  return (
    <div class="tab-bar-wrap">
      <div
        ref={barRef}
        class={`tab-bar${textLabels ? ' tab-bar--text' : ''}`}
        role="tablist"
        data-fade={fade}
        onScroll={updateFade}
        onWheel={handleWheel}
      >
        {ids.map((provider) => {
          const meta = PROVIDER_META[provider];
          const isSelected = provider === selected;
          return (
            <button
              key={provider}
              type="button"
              role="tab"
              aria-selected={isSelected}
              class={`tab${isSelected ? ' tab--selected' : ''}${dragged === provider ? ' tab--dragging' : ''}`}
              title={meta.tabLabel}
              data-provider={provider}
              onPointerDown={(e) => handlePointerDown(e, provider)}
              onPointerMove={handlePointerMove}
              onPointerUp={handlePointerUp}
              onPointerCancel={handlePointerUp}
              onClick={() => {
                if (justDragged.current) {
                  justDragged.current = false;
                  return;
                }
                onSelect(provider);
              }}
            >
              {textLabels ? null : <span class={`tab__icon tab__icon--${provider}`} aria-hidden="true" />}
              {textLabels || isSelected ? <span class="tab__label">{meta.tabLabel}</span> : null}
            </button>
          );
        })}
      </div>
    </div>
  );
}
