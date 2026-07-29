/**
 * Shared external URLs used across extension surfaces (popup, options).
 *
 * The extension always links to the marketing site for the Mac app — never a
 * raw DMG download. Linking directly to a binary reads as pointing users to
 * an "alternative distribution channel," which risks App Store review
 * guideline 2.3.10 once the Safari companion app ships. The site is also
 * where install instructions and Homebrew/Sparkle notes live.
 */
export const TRYTOKENOMICS_URL = 'https://trytokenomics.com';
