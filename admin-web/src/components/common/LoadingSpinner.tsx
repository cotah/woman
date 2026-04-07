import React from 'react';

const spinnerStyle: React.CSSProperties = {
  display: 'flex',
  justifyContent: 'center',
  alignItems: 'center',
  padding: '2rem',
};

const dotStyle: React.CSSProperties = {
  width: 10,
  height: 10,
  borderRadius: '50%',
  background: '#6366f1',
  margin: '0 4px',
  animation: 'bounce 1.4s infinite ease-in-out both',
};

export const LoadingSpinner: React.FC<{ message?: string }> = ({ message }) => (
  <div style={spinnerStyle}>
    <style>{`
      @keyframes bounce {
        0%, 80%, 100% { transform: scale(0); }
        40% { transform: scale(1); }
      }
    `}</style>
    <div style={{ ...dotStyle, animationDelay: '-0.32s' }} />
    <div style={{ ...dotStyle, animationDelay: '-0.16s' }} />
    <div style={dotStyle} />
    {message && (
      <span style={{ marginLeft: 12, color: '#6b7280', fontSize: 14 }}>
        {message}
      </span>
    )}
  </div>
);
