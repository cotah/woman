import { useState } from "react";
import type { ContactResponseType } from "../types";

interface ResponseOption {
  type: ContactResponseType;
  label: string;
  color: string;
  bgColor: string;
}

const RESPONSES: ResponseOption[] = [
  {
    type: "trying_to_reach",
    label: "I am trying to reach her",
    color: "#1e40af",
    bgColor: "#dbeafe",
  },
  {
    type: "could_not_reach",
    label: "I could not reach her",
    color: "#92400e",
    bgColor: "#fef3c7",
  },
  {
    type: "going_to_location",
    label: "I am going to her location",
    color: "#065f46",
    bgColor: "#d1fae5",
  },
  {
    type: "calling_authorities",
    label: "I am calling authorities",
    color: "#991b1b",
    bgColor: "#fee2e2",
  },
  {
    type: "mark_reviewed",
    label: "Mark as reviewed",
    color: "#374151",
    bgColor: "#f3f4f6",
  },
];

interface Props {
  onRespond: (type: ContactResponseType) => Promise<void>;
  disabled?: boolean;
}

export default function ResponseButtons({ onRespond, disabled }: Props) {
  const [loading, setLoading] = useState<ContactResponseType | null>(null);
  const [sent, setSent] = useState<Set<ContactResponseType>>(new Set());

  const handleClick = async (type: ContactResponseType) => {
    if (loading || sent.has(type)) return;
    setLoading(type);
    try {
      await onRespond(type);
      setSent((prev) => new Set(prev).add(type));
    } catch {
      // Error handling is done at parent level
    } finally {
      setLoading(null);
    }
  };

  return (
    <div style={{ display: "flex", flexDirection: "column", gap: 8 }}>
      <p
        style={{
          margin: "0 0 4px",
          fontSize: 13,
          color: "#6b7280",
          fontWeight: 500,
        }}
      >
        Let us know your status:
      </p>
      {RESPONSES.map((r) => {
        const isSent = sent.has(r.type);
        const isLoading = loading === r.type;
        return (
          <button
            key={r.type}
            onClick={() => handleClick(r.type)}
            disabled={disabled || isLoading}
            style={{
              display: "block",
              width: "100%",
              padding: "12px 16px",
              border: isSent ? `2px solid ${r.color}` : "1px solid #e5e7eb",
              borderRadius: 10,
              backgroundColor: isSent ? r.bgColor : "#fff",
              color: r.color,
              fontSize: 14,
              fontWeight: 500,
              cursor: disabled || isLoading ? "not-allowed" : "pointer",
              opacity: disabled ? 0.5 : 1,
              textAlign: "left",
              transition: "all 0.15s ease",
            }}
          >
            {isLoading ? "Sending..." : isSent ? `${r.label} (sent)` : r.label}
          </button>
        );
      })}
    </div>
  );
}
