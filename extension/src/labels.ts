/**
 * Tab label mode: vendor logos (default) or plain site names.
 *
 * Why this exists: store reviewers can object to third-party logos. This
 * setting plus the `--text-labels` build flag give us a fast logo-free path.
 *
 * `--text-labels` builds define __TEXT_LABELS_ONLY__ = true: site names are
 * forced, the logo files are not copied into the package, and the options
 * toggle is hidden (there is nothing to switch back to). Normal builds let the
 * user choose, defaulting to logos.
 */

declare const __TEXT_LABELS_ONLY__: boolean | undefined;

/** True in `--text-labels` builds. Safe under node tests (global undefined). */
export const TEXT_LABELS_ONLY: boolean =
  typeof __TEXT_LABELS_ONLY__ !== 'undefined' && __TEXT_LABELS_ONLY__ === true;

/** Resolve the effective mode from the stored user choice (null = never set). */
export function resolveTextLabels(stored: boolean | null, textOnlyBuild: boolean = TEXT_LABELS_ONLY): boolean {
  if (textOnlyBuild) return true;
  return stored === true;
}
