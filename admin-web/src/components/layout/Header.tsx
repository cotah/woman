import React from 'react';
import { getStoredUser, logout } from '../../services/auth';

const headerStyles = {
  header: {
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'space-between',
    padding: '0 24px',
    height: 56,
    borderBottom: '1px solid #e5e7eb',
    background: '#fff',
  },
  left: {
    fontSize: 14,
    color: '#6b7280',
  },
  right: {
    display: 'flex',
    alignItems: 'center',
    gap: 16,
  },
  userInfo: {
    fontSize: 13,
    color: '#374151',
  },
  role: {
    fontSize: 11,
    color: '#9ca3af',
    textTransform: 'uppercase' as const,
    marginLeft: 8,
    padding: '2px 6px',
    background: '#f3f4f6',
    borderRadius: 4,
  },
  logoutBtn: {
    padding: '6px 14px',
    borderRadius: 6,
    border: '1px solid #d1d5db',
    background: '#fff',
    cursor: 'pointer',
    fontSize: 13,
    color: '#374151',
  },
};

export const Header: React.FC = () => {
  const user = getStoredUser();

  return (
    <header style={headerStyles.header}>
      <div style={headerStyles.left}>Operations Dashboard</div>
      <div style={headerStyles.right}>
        {user && (
          <span style={headerStyles.userInfo}>
            {user.name}
            <span style={headerStyles.role}>{user.role.replace('_', ' ')}</span>
          </span>
        )}
        <button style={headerStyles.logoutBtn} onClick={logout}>
          Logout
        </button>
      </div>
    </header>
  );
};
