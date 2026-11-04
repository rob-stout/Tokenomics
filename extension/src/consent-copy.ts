// Wording for the first-run consent screen (popup + options page).
//
// This is the "prominent disclosure" the Chrome Web Store User Data policy
// requires before any data is read. Text is from the legal draft in
// docs/publishing/legal/chrome-web-store-privacy-practices.md §6 — keep the
// two in sync with the privacy policy at PRIVACY_URL. If the substance
// changes (new site, new data type), bump CONSENT_VERSION in storage.ts so
// existing users are asked again.

export const PRIVACY_URL = 'https://trytokenomics.com/privacy';

export const CONSENT_COPY = {
  title: 'Before Tokenomics starts',
  lede:
    'Tokenomics shows how much of your AI plan you’ve used. To do that, while you are signed in to a supported service, it will:',
  points: [
    'Use your existing sign-in on that service (your browser’s cookies, or an access token the service gives your browser) only to ask that service for your own usage numbers.',
    'Save usage numbers and settings on this computer, in your browser’s extension storage. For ElevenLabs and Leonardo it also saves the access token. The extension does not encrypt it, so someone with access to your unlocked browser profile could read it. You can delete everything by uninstalling or with “Stop reading and delete my data” in settings.',
    'On chatgpt.com, note the time and model of each message you send, to estimate usage. It never reads the text of your messages.',
    'If you have the Tokenomics Mac app, send your usage numbers (never your tokens) to it on this computer.',
  ],
  footer:
    'Nothing is sent to the developer or to any server other than the AI service you are signed in to. ' +
    'Supported services: Claude, ChatGPT, Gemini, Midjourney, ElevenLabs, Grok, Perplexity, Leonardo. ' +
    'Tokenomics is not affiliated with these services.',
  agree: 'Agree and turn on',
  decline: 'No thanks',
  privacyLink: 'Privacy policy',
} as const;
