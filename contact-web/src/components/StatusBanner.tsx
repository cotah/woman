import type { IncidentStatus } from "../types";

const STATUS_CONFIG: Record<
  IncidentStatus,
  { label: string; bg: string; text: string }
> = {
  active: {
    label: "Active Alert",
    bg: "#fef3c7",
    text: "#92400e",
  },
  escalated: {
    label: "Escalated",
    bg: "#fee2e2",
    text: "#991b1b",
  },
  monitoring: {
    label: "Monitoring",
    bg: "#dbeafe",
    text: "#1e40af",
  },
  resolved: {
    label: "Resolved",
    bg: "#d1fae5",
    text: "#065f46",
  },
  cancelled: {
    label: "Cancelled",
    bg: "#f3f4f6",
    text: "#374151",
  },
};

interface Props {
  status: IncidentStatus;
}

export default function StatusBanner({ status }: Props) {
  const config = STATUS_CONFIG[status] ?? STATUS_CONFIG.active;

  return (
    <div
      style={{
        backgroundColor: config.bg,
        color: config.text,
        padding: "10px 16px",
        borderRadius: 8,
        fontWeight: 600,
        fontSize: 14,
        textAlign: "center",
        letterSpacing: 0.3,
      }}
    >
      {config.label}
    </div>
  );
}
