import { CONSENT_COPY, PRIVACY_URL } from '../../consent-copy';

interface Props {
  onAgree: () => void;
}

/** First-run disclosure. Nothing is read until the user taps Agree. */
export function ConsentScreen({ onAgree }: Props) {
  return (
    <div class="consent">
      <h1 class="consent__title">{CONSENT_COPY.title}</h1>
      <p class="consent__lede">{CONSENT_COPY.lede}</p>
      <ul class="consent__points">
        {CONSENT_COPY.points.map((point) => (
          <li key={point}>{point}</li>
        ))}
      </ul>
      <p class="consent__lede">{CONSENT_COPY.footer}</p>
      <div class="consent__actions">
        <button type="button" class="consent__agree" onClick={onAgree}>
          {CONSENT_COPY.agree}
        </button>
        {/* Declining just closes the popup / settings tab; nothing is read. */}
        <button type="button" class="consent__decline" onClick={() => window.close()}>
          {CONSENT_COPY.decline}
        </button>
      </div>
      <a class="consent__privacy" href={PRIVACY_URL} target="_blank" rel="noreferrer noopener">
        {CONSENT_COPY.privacyLink}
      </a>
    </div>
  );
}
