import { useEffect, useRef } from 'preact/hooks';
import { PROVIDER_META, type ProviderId } from '../../types';

interface Props {
  selected: ProviderId;
  /** Ordered list of visible provider IDs to render as tabs. */
  visibleProviderIds: readonly ProviderId[];
  onSelect: (provider: ProviderId) => void;
  /** Show every tab as its site name (no logos). The bar scrolls sideways. */
  textLabels?: boolean;
}

export function ProviderTabBar({ selected, visibleProviderIds, onSelect, textLabels = false }: Props) {
  const barRef = useRef<HTMLDivElement>(null);

  // Text tabs don't all fit in 368px, so keep the selected one in view.
  useEffect(() => {
    if (!textLabels) return;
    barRef.current
      ?.querySelector<HTMLElement>('[aria-selected="true"]')
      ?.scrollIntoView({ inline: 'nearest', block: 'nearest' });
  }, [textLabels, selected, visibleProviderIds.length]);

  // Let a plain mouse wheel scroll the bar sideways (trackpads already can).
  const handleWheel = (e: WheelEvent) => {
    const bar = barRef.current;
    if (!textLabels || !bar || Math.abs(e.deltaY) <= Math.abs(e.deltaX)) return;
    bar.scrollLeft += e.deltaY;
    e.preventDefault();
  };

  return (
    <div
      ref={barRef}
      class={`tab-bar${textLabels ? ' tab-bar--text' : ''}`}
      role="tablist"
      onWheel={handleWheel}
    >
      {visibleProviderIds.map((provider) => {
        const meta = PROVIDER_META[provider];
        const isSelected = provider === selected;
        return (
          <button
            key={provider}
            type="button"
            role="tab"
            aria-selected={isSelected}
            class={`tab${isSelected ? ' tab--selected' : ''}`}
            title={meta.tabLabel}
            onClick={() => onSelect(provider)}
          >
            {textLabels ? null : <span class={`tab__icon tab__icon--${provider}`} aria-hidden="true" />}
            {textLabels || isSelected ? <span class="tab__label">{meta.tabLabel}</span> : null}
          </button>
        );
      })}
    </div>
  );
}
