/**
 * Wire shapes exchanged between the browser extension and the
 * TokenomicsBridge native messaging host.
 *
 * Both sides of the bridge import from this file — the Mac app has a
 * matching Swift mirror at Tokenomics/Models/BridgeWireTypes.swift.
 * Keep the two in sync when modifying fields or adding versions.
 */

export interface ProviderVisibilitySetting {
  enabled: boolean;
  /** ISO 8601 timestamp. Last-writer-wins conflict resolution applies per provider. */
  lastChangedAt: string;
}

/** Provider tab order (provider ids). Newest `lastChangedAt` wins; the whole list shares one stamp. */
export interface ProviderOrderSetting {
  order: string[];
  /** ISO 8601, whole seconds. */
  lastChangedAt: string;
}

export interface BridgeWindow {
  label: string;
  /** Utilization expressed as a fraction in 0...1. */
  utilization: number;
  resetsAt: string;
  windowDurationSec: number;
  sublabelOverride?: string;
}

export interface BridgeSnapshot {
  /** Raw ProviderId string — both sides derive display strings locally. */
  provider: string;
  capturedAt: string;
  estimated?: boolean;
  shortWindow: BridgeWindow;
  longWindow: BridgeWindow | null;
  planLabel: string;
}

export interface BridgeSettings {
  providerVisibility: Record<string, ProviderVisibilitySetting>;
  /** Optional: older Mac apps neither send nor understand it. */
  providerOrder?: ProviderOrderSetting;
}

export interface BridgeRequest {
  schemaVersion: number;
  envelopeSentAt: string;
  extensionId: string;
  snapshots: BridgeSnapshot[];
  settings?: BridgeSettings;
  requestedActions?: { refreshNativeProviders?: boolean };
}

export interface BridgeResponse {
  ok: boolean;
  bridgeSchemaVersion: number;
  macAppVersion: string;
  ackedAt: string;
  nativeSnapshots: BridgeSnapshot[];
  settings?: BridgeSettings;
  commands: { kind: string }[];
  error?: string;
}

export const BRIDGE_HOST_NAME = 'com.tokenomics.bridge';
export const BRIDGE_SCHEMA_VERSION = 1;
