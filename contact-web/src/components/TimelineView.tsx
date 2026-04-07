import { format } from "date-fns";
import type { TimelineEvent } from "../types";

const TYPE_ICONS: Record<TimelineEvent["type"], string> = {
  trigger: "!",
  location_update: "~",
  audio_clip: "m",
  contact_response: "r",
  status_change: "s",
  system: "i",
};

const TYPE_COLORS: Record<TimelineEvent["type"], string> = {
  trigger: "#ef4444",
  location_update: "#6366f1",
  audio_clip: "#8b5cf6",
  contact_response: "#10b981",
  status_change: "#f59e0b",
  system: "#6b7280",
};

interface Props {
  events: TimelineEvent[];
}

export default function TimelineView({ events }: Props) {
  const sorted = [...events].sort(
    (a, b) => new Date(b.timestamp).getTime() - new Date(a.timestamp).getTime()
  );

  if (sorted.length === 0) {
    return (
      <p style={{ color: "#9ca3af", fontSize: 14, textAlign: "center" }}>
        No timeline events yet.
      </p>
    );
  }

  return (
    <div style={{ display: "flex", flexDirection: "column", gap: 0 }}>
      {sorted.map((event, i) => (
        <div
          key={event.id}
          style={{
            display: "flex",
            gap: 12,
            padding: "10px 0",
            borderBottom:
              i < sorted.length - 1 ? "1px solid #f3f4f6" : "none",
          }}
        >
          {/* Dot */}
          <div
            style={{
              width: 28,
              height: 28,
              borderRadius: "50%",
              backgroundColor: TYPE_COLORS[event.type] + "18",
              color: TYPE_COLORS[event.type],
              display: "flex",
              alignItems: "center",
              justifyContent: "center",
              fontSize: 12,
              fontWeight: 700,
              flexShrink: 0,
              marginTop: 2,
            }}
          >
            {TYPE_ICONS[event.type]}
          </div>

          <div style={{ flex: 1, minWidth: 0 }}>
            <p
              style={{
                margin: 0,
                fontSize: 14,
                color: "#1f2937",
                lineHeight: 1.4,
              }}
            >
              {event.message}
            </p>
            <p
              style={{
                margin: "2px 0 0",
                fontSize: 12,
                color: "#9ca3af",
              }}
            >
              {format(new Date(event.timestamp), "h:mm a")}
            </p>
          </div>
        </div>
      ))}
    </div>
  );
}
