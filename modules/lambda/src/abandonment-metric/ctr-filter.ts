export interface ContactRecord {
  contactId: string;
  disconnectReason?: string;
  disconnectTimestamp?: string;
}

const ABANDONMENT_DISCONNECT_REASON = "CUSTOMER_DISCONNECT";

export function isAbandonmentCandidate(record: ContactRecord): boolean {
  return (
    record.disconnectReason === ABANDONMENT_DISCONNECT_REASON &&
    record.disconnectTimestamp !== undefined
  );
}
