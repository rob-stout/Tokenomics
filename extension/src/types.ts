// Default order = the Mac app's `ProviderId.allCases` order (minus ids the extension
// lacks: stableDiffusion, runway), so both look the same out of the box.
export const PROVIDERS = [
  'claude',
  'codex',
  'gemini',
  'chatgpt',
  'geminiConsumer',
  'copilot',
  'cursor',
  'midjourney',
  'leonardo',
  'elevenlabs',
  'suno',
  'udio',
  'grok',
  'perplexity',
] as const;

export type ProviderId = (typeof PROVIDERS)[number];

export interface ProviderMeta {
  tabLabel: string;
  displayName: string;
  iconBase: string;
}

export const PROVIDER_META: Record<ProviderId, ProviderMeta> = {
  claude: { tabLabel: 'Claude', displayName: 'Claude', iconBase: 'Claude' },
  codex: { tabLabel: 'OpenAI', displayName: 'Codex CLI', iconBase: 'Codex' },
  // chatgpt = the consumer ChatGPT web pool (chat.openai.com). Separate usage
  // meter from Codex CLI; shares the OpenAI mark. Routed to its own pool on the
  // Mac side (was incorrectly riding the 'codex' key before this).
  chatgpt: { tabLabel: 'ChatGPT', displayName: 'ChatGPT', iconBase: 'Codex' },
  gemini: { tabLabel: 'Google AI', displayName: 'Gemini CLI', iconBase: 'Gemini' },
  // geminiConsumer = the web app (gemini.google.com) reader.
  // Shares the Gemini icon with the CLI pool — same brand, separate usage meter.
  geminiConsumer: { tabLabel: 'Gemini', displayName: 'Gemini (app)', iconBase: 'Gemini' },
  copilot: { tabLabel: 'Copilot', displayName: 'GitHub Copilot', iconBase: 'Copilot' },
  cursor: { tabLabel: 'Cursor', displayName: 'Cursor', iconBase: 'Cursor' },
  midjourney: { tabLabel: 'Midjourney', displayName: 'Midjourney', iconBase: 'midjourney' },
  // Icon assets: elevenlabs-d.blue.svg and elevenlabs-white.svg exist in
  // extension/src/icons/providers/ and are wired in popup.css.
  elevenlabs: { tabLabel: 'ElevenLabs', displayName: 'ElevenLabs', iconBase: 'elevenlabs' },
  // Icon assets for grok / perplexity / leonardo (-d.blue.svg + -white.svg) exist
  // in extension/src/icons/providers/ and are wired in popup.css.
  grok: { tabLabel: 'Grok', displayName: 'Grok', iconBase: 'grok' },
  perplexity: { tabLabel: 'Perplexity', displayName: 'Perplexity', iconBase: 'perplexity' },
  leonardo: { tabLabel: 'Leonardo', displayName: 'Leonardo', iconBase: 'leonardo' },
  suno: { tabLabel: 'Suno', displayName: 'Suno', iconBase: 'suno' },
  udio: { tabLabel: 'Udio', displayName: 'Udio', iconBase: 'udio' },
};

export function isProviderId(value: unknown): value is ProviderId {
  return typeof value === 'string' && (PROVIDERS as readonly string[]).includes(value);
}
