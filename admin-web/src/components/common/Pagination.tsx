import React from 'react';

interface PaginationProps {
  page: number;
  totalPages: number;
  onPageChange: (page: number) => void;
}

const styles = {
  container: {
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 4,
    padding: '12px 0',
  } as React.CSSProperties,
  button: {
    padding: '6px 12px',
    border: '1px solid #d1d5db',
    borderRadius: 6,
    background: '#fff',
    cursor: 'pointer',
    fontSize: 13,
    color: '#374151',
  } as React.CSSProperties,
  active: {
    background: '#6366f1',
    color: '#fff',
    borderColor: '#6366f1',
  } as React.CSSProperties,
  disabled: {
    opacity: 0.4,
    cursor: 'not-allowed',
  } as React.CSSProperties,
};

export const Pagination: React.FC<PaginationProps> = ({
  page,
  totalPages,
  onPageChange,
}) => {
  if (totalPages <= 1) return null;

  const pages: number[] = [];
  const start = Math.max(1, page - 2);
  const end = Math.min(totalPages, page + 2);
  for (let i = start; i <= end; i++) pages.push(i);

  return (
    <div style={styles.container}>
      <button
        style={{ ...styles.button, ...(page <= 1 ? styles.disabled : {}) }}
        onClick={() => page > 1 && onPageChange(page - 1)}
        disabled={page <= 1}
      >
        Prev
      </button>
      {start > 1 && (
        <>
          <button style={styles.button} onClick={() => onPageChange(1)}>1</button>
          {start > 2 && <span style={{ color: '#9ca3af' }}>...</span>}
        </>
      )}
      {pages.map((p) => (
        <button
          key={p}
          style={{ ...styles.button, ...(p === page ? styles.active : {}) }}
          onClick={() => onPageChange(p)}
        >
          {p}
        </button>
      ))}
      {end < totalPages && (
        <>
          {end < totalPages - 1 && <span style={{ color: '#9ca3af' }}>...</span>}
          <button style={styles.button} onClick={() => onPageChange(totalPages)}>
            {totalPages}
          </button>
        </>
      )}
      <button
        style={{ ...styles.button, ...(page >= totalPages ? styles.disabled : {}) }}
        onClick={() => page < totalPages && onPageChange(page + 1)}
        disabled={page >= totalPages}
      >
        Next
      </button>
    </div>
  );
};
