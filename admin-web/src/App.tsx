import React from 'react';
import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom';
import { AppLayout } from './components/layout/AppLayout';
import { LoginPage } from './pages/LoginPage';
import { DashboardPage } from './pages/DashboardPage';
import { IncidentsPage } from './pages/IncidentsPage';
import { IncidentDetailPage } from './pages/IncidentDetailPage';
import { AuditLogsPage } from './pages/AuditLogsPage';
import { FeatureFlagsPage } from './pages/FeatureFlagsPage';
import { SystemHealthPage } from './pages/SystemHealthPage';
import { getStoredUser } from './services/auth';

/**
 * Role-based route guard. Wraps a page component and checks
 * the stored user role against allowed roles.
 */
const RoleGuard: React.FC<{
  allowedRoles: string[];
  children: React.ReactNode;
}> = ({ allowedRoles, children }) => {
  const user = getStoredUser();
  if (!user || !allowedRoles.includes(user.role)) {
    return (
      <div style={{ padding: 40, textAlign: 'center' }}>
        <h2 style={{ color: '#dc2626', marginBottom: 8 }}>Access Denied</h2>
        <p style={{ color: '#6b7280' }}>You do not have permission to view this page.</p>
      </div>
    );
  }
  return <>{children}</>;
};

const ALL_ROLES = ['super_admin', 'admin', 'operator', 'viewer'];
const ADMIN_ROLES = ['super_admin', 'admin'];

export const App: React.FC = () => {
  return (
    <BrowserRouter>
      <Routes>
        <Route path="/login" element={<LoginPage />} />

        {/* Auth-protected layout */}
        <Route element={<AppLayout />}>
          <Route
            index
            element={
              <RoleGuard allowedRoles={ALL_ROLES}>
                <DashboardPage />
              </RoleGuard>
            }
          />
          <Route
            path="incidents"
            element={
              <RoleGuard allowedRoles={ALL_ROLES}>
                <IncidentsPage />
              </RoleGuard>
            }
          />
          <Route
            path="incidents/:id"
            element={
              <RoleGuard allowedRoles={ALL_ROLES}>
                <IncidentDetailPage />
              </RoleGuard>
            }
          />
          <Route
            path="audit-logs"
            element={
              <RoleGuard allowedRoles={ADMIN_ROLES}>
                <AuditLogsPage />
              </RoleGuard>
            }
          />
          <Route
            path="feature-flags"
            element={
              <RoleGuard allowedRoles={ADMIN_ROLES}>
                <FeatureFlagsPage />
              </RoleGuard>
            }
          />
          <Route
            path="system-health"
            element={
              <RoleGuard allowedRoles={ALL_ROLES}>
                <SystemHealthPage />
              </RoleGuard>
            }
          />
        </Route>

        <Route path="*" element={<Navigate to="/" replace />} />
      </Routes>
    </BrowserRouter>
  );
};

export default App;
