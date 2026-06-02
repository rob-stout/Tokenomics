export const PROVIDERS = [
  'claude',
  'codex',
  'gemini',
  'geminiConsumer',
  'copilot',
  'cursor',
  'midjourney',
  'elevenlabs',
  'grok',
  'perplexity',
  'leonardo',
] as const;

export type ProviderId = (typeof PROVIDERS)[number];

export interface ProviderMeta {
  tabLabel: string;
  displayName: string;
  iconBase: string;
}

export const PROVIDER_META: Record<ProviderId, ProviderMeta> = {
  claude: { tabLabel: 'Claude', displayName: 'Claude', iconBase: 'Claude' },
  codex: { tabLabel: 'OpenAI', displayName: 'OpenAI', iconBase: 'Codex' },
  gemini: { tabLabel: 'Google AI', displayName: 'Google AI', iconBase: 'Gemini' },
  // geminiConsumer = the web app (gemini.google.com) reader.
  // Shares the Gemini icon with the CLI pool — same brand, separate usage meter.
  geminiConsumer: { tabLabel: 'Gemini', displayName: 'Gemini', iconBase: 'Gemini' },
  copilot: { tabLabel: 'Copilot', displayName: 'GitHub Copilot', iconBase: 'Copilot' },
  cursor: { tabLabel: 'Cursor', displayName: 'Cursor', iconBase: 'Cursor' },
  midjourney: { tabLabel: 'Midjourney', displayName: 'Midjourney', iconBase: 'midjourney' },
  // NOTE: No ElevenLabs icon asset exists in extension/src/icons/providers/ yet.
  // iconBase 'elevenlabs' is the agreed name — add elevenlabs-d.blue.svg and
  // elevenlabs-white.svg to that directory to match the other provider icons.
  // Until then the popup icon will fall back to whatever the PopupIcon component
  // shows for an unknown iconBase (typically a generic placeholder).
  elevenlabs: { tabLabel: 'ElevenLabs', displayName: 'ElevenLabs', iconBase: 'elevenlabs' },
  // NOTE: No icon assets exist for grok/perplexity/leonardo yet.
  // Add <name>-d.blue.svg and <name>-white.svg to extension/src/icons/providers/
  // to match the other provider icons. Popup will fall back gracefully until then.
  grok: { tabLabel: 'Grok', displayName: 'Grok', iconBase: 'grok' },
  perplexity: { tabLabel: 'Perplexity', displayName: 'Perplexity', iconBase: 'perplexity' },
  leonardo: { tabLabel: 'Leonardo', displayName: 'Leonardo', iconBase: 'leonardo' },
};

export function isProviderId(value: unknown): value is ProviderId {
  return typeof value === 'string' && (PROVIDERS as readonly string[]).includes(value);
}
