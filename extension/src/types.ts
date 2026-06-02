export const PROVIDERS = [
  'claude',
  'codex',
  'gemini',
  'geminiConsumer',
  'copilot',
  'cursor',
  'midjourney',
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
};

export function isProviderId(value: unknown): value is ProviderId {
  return typeof value === 'string' && (PROVIDERS as readonly string[]).includes(value);
}
