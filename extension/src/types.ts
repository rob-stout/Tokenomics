export const PROVIDERS = [
  'claude',
  'codex',
  'chatgpt',
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
  // chatgpt = the consumer ChatGPT web pool (chat.openai.com). Separate usage
  // meter from Codex CLI; shares the OpenAI mark. Routed to its own pool on the
  // Mac side (was incorrectly riding the 'codex' key before this).
  chatgpt: { tabLabel: 'ChatGPT', displayName: 'ChatGPT', iconBase: 'Codex' },
  gemini: { tabLabel: 'Google AI', displayName: 'Google AI', iconBase: 'Gemini' },
  // geminiConsumer = the web app (gemini.google.com) reader.
  // Shares the Gemini icon with the CLI pool — same brand, separate usage meter.
  geminiConsumer: { tabLabel: 'Gemini', displayName: 'Gemini', iconBase: 'Gemini' },
  copilot: { tabLabel: 'Copilot', displayName: 'GitHub Copilot', iconBase: 'Copilot' },
  cursor: { tabLabel: 'Cursor', displayName: 'Cursor', iconBase: 'Cursor' },
  midjourney: { tabLabel: 'Midjourney', displayName: 'Midjourney', iconBase: 'midjourney' },
  // Icon assets: elevenlabs-d.blue.svg and elevenlabs-white.svg exist in
  // extension/src/icons/providers/ and are wired in popup.css.
  elevenlabs: { tabLabel: 'ElevenLabs', displayName: 'ElevenLabs', iconBase: 'elevenlabs' },
  // Icon assets: grok-d.blue.svg / grok-white.svg and perplexity-d.blue.svg /
  // perplexity-white.svg exist in extension/src/icons/providers/ and are wired
  // in popup.css. NOTE: leonardo still needs its icon asset — no clean SVG yet.
  grok: { tabLabel: 'Grok', displayName: 'Grok', iconBase: 'grok' },
  perplexity: { tabLabel: 'Perplexity', displayName: 'Perplexity', iconBase: 'perplexity' },
  leonardo: { tabLabel: 'Leonardo', displayName: 'Leonardo', iconBase: 'leonardo' },
};

export function isProviderId(value: unknown): value is ProviderId {
  return typeof value === 'string' && (PROVIDERS as readonly string[]).includes(value);
}
