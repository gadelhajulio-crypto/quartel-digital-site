export type AuthStatus =
    | "loading"
    | "unauthenticated"
    | "authenticated"
    | "requires_mfa"
    | "account_locked"
    | "inactive_user"
    | "password_expired";

export type SessionRevokedReason =
    | "none"
    | "user_action"
    | "session_expired"
    | "security_logout";
