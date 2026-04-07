import React from 'react';
import { NavLink } from 'react-router-dom';

const NAV_ITEMS = [
  { to: '/', label: 'Dashboard', icon: '\u{1F4CA}' },
  { to: '/incidents', label: 'Incidents', icon: '\u{1F6A8}' },
  { to: '/audit-logs', label: 'Audit Logs', icon: '\u{1F4DC}' },
  { to: '/feature-flags', label: 'Feature Flags', icon: '\u{1F6A9}' },
  { to: '/system-health', label: 'System Health', icon: '\u{1F49A}' },
];

const sidebarStyles = {
  sidebar: {
    width: 240,
    minHeight: '100vh',
    background: '#111827',
    color: '#fff',
    display: 'flex',
    flexDirection: 'column' as const,
    flexShrink: 0,
  },
  logo: {
    padding: '20px 20px 16px',
    borderBottom: '1px solid #1f2937',
  },
  logoText: {
    fontSize: 18,
    fontWeight: 700,
    color: '#fff',
    letterSpacing: '-0.02em',
  },
  logoSub: {
    fontSize: 11,
    color: '#6b7280',
    marginTop: 2,
  },
  nav: {
    padding: '12px 8px',
    flex: 1,
  },
  link: {
    display: 'flex',
    alignItems: 'center',
    gap: 10,
    padding: '10px 12px',
    borderRadius: 8,
    textDecoration: 'none',
    color: '#9ca3af',
    fontSize: 14,
    fontWeight: 500,
    transition: 'all 0.15s',
    marginBottom: 2,
  },
  activeLink: {
    background: '#1f2937',
    color: '#fff',
  },
};

export const Sidebar: React.FC = () => {
  return (
    <aside style={sidebarStyles.sidebar}>
      <div style={sidebarStyles.logo}>
        <div style={sidebarStyles.logoText}>SafeCircle</div>
        <div style={sidebarStyles.logoSub}>Admin Operations</div>
      </div>
      <nav style={sidebarStyles.nav}>
        {NAV_ITEMS.map((item) => (
          <NavLink
            key={item.to}
            to={item.to}
            end={item.to === '/'}
            style={({ isActive }) => ({
              ...sidebarStyles.link,
              ...(isActive ? sidebarStyles.activeLink : {}),
            })}
          >
            <span style={{ fontSize: 16 }}>{item.icon}</span>
            {item.label}
          </NavLink>
        ))}
      </nav>
      <div style={{ padding: '12px 20px', borderTop: '1px solid #1f2937', fontSize: 11, color: '#4b5563' }}>
        v1.0.0
      </div>
    </aside>
  );
};
