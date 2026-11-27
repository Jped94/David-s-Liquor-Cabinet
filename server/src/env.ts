export interface Env {
  DB: D1Database;
  /** Lets an iPad or browser read the menu. */
  GUEST_PASSCODE: string;
  /** Also allows syncing, edits and photos. */
  ADMIN_PASSCODE: string;
  /** Signs session tokens. Changing it signs every device out. */
  SESSION_SECRET: string;
}

export type Role = "guest" | "admin";
