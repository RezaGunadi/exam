export type Role = "admin" | "tutor" | "student";

export type ApiUser = {
  id: number;
  name: string;
  email: string;
  role: Role;
  school_id: number;
  class_id?: number | null;
  is_admin: boolean;
  credit_balance: number;
  referral_token?: string | null;
  school?: {
    id: number;
    name: string;
    active_until?: string | null;
    subscription_type?: string | null;
    token_balance?: number;
  } | null;
  class_room?: {
    id: number;
    name: string;
  } | null;
};

export type ApiResponse<T = unknown> = T & {
  message?: string;
};

export type ResourceItem = Record<string, unknown>;
