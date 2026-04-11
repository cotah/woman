import api from './api';
import type { AdminUser, LoginRequest, LoginResponse } from '../types';

export async function login(credentials: LoginRequest): Promise<LoginResponse> {
  const { data } = await api.post('/auth/login', credentials);
  // Backend returns { user: { id, email, firstName, lastName, role }, tokens: { accessToken, refreshToken, expiresIn } }
  const token = data.tokens.accessToken;
  const user: AdminUser = {
    id: data.user.id,
    email: data.user.email,
    name: `${data.user.firstName} ${data.user.lastName}`,
    role: data.user.role,
    createdAt: data.user.createdAt ?? new Date().toISOString(),
  };
  localStorage.setItem('admin_token', token);
  localStorage.setItem('admin_user', JSON.stringify(user));
  return { token, user };
}

export function logout(): void {
  localStorage.removeItem('admin_token');
  localStorage.removeItem('admin_user');
  window.location.href = '/login';
}

export function getStoredUser(): AdminUser | null {
  const raw = localStorage.getItem('admin_user');
  if (!raw) return null;
  try {
    return JSON.parse(raw) as AdminUser;
  } catch {
    return null;
  }
}

export function getToken(): string | null {
  return localStorage.getItem('admin_token');
}

export function isAuthenticated(): boolean {
  return !!getToken();
}
