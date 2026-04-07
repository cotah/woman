import { useEffect, useState, useCallback } from "react";
import { useNavigate } from "react-router-dom";
import { format, formatDistanceToNow } from "date-fns";
import { fetchIncident, submitResponse } from "../services/api";
import type { Incident, ContactResponseType } from "../types";
import StatusBanner from "../components/StatusBanner";
import LiveMap from "../components/LiveMap";
import TimelineView from "../components/TimelineView";
import ResponseButtons from "../components/ResponseButtons";
import AudioPlayer from "../components/AudioPlayer";
import InstructionCard from "../components/InstructionCard";

const POLL_INTERVAL = 10_000;

export default function IncidentPage() {
  const navigate = useNavigate();
  const [incident, setIncident] = useState<Incident | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);

  const load = useCallback(async () => {
    try {
      const data = await fetchIncident();
      setIncident(data);
      setError(null);
    } catch (err: unknown) {
      const status = (err as { response?: { status?: number } })?.response
        ?.status;
      if (status === 401 || status === 403) {
        navigate("/invalid", { replace: true });
        return;
      }
      setError("Unable to load incident data. Retrying...");
    } finally {
      setLoading(false);
    }
  }, [navigate]);

  // Initial load + polling
  useEffect(() => {
    load();
    const interval = setInterval(load, POLL_INTERVAL);
    return () => clearInterval(interval);
  }, [load]);

  const handleRespond = async (type: ContactResponseType) => {
    if (!incident) return;
    await submitResponse(incident.id, type);
    // Refresh after responding
    await load();
  };

  // Loading state
  if (loading && !incident) {
    return (
      <div style={styles.loadingContainer}>
        <div style={styles.spinner} />
        <p style={{ color: "#6b7280", fontSize: 14, marginTop: 12 }}>
          Loading alert details...
        </p>
      </div>
    );
  }

  // Error state (no data at all)
  if (!incident) {
    return (
      <div style={styles.loadingContainer}>
        <p style={{ color: "#ef4444", fontSize: 14, textAlign: "center" }}>
          {error || "Something went wrong."}
        </p>
      </div>
    );
  }

  const triggeredDate = new Date(incident.triggeredAt);

  return (
    <div style={styles.page}>
      {/* Header */}
      <div style={styles.header}>
        <p style={styles.brandLabel}>SafeCircle</p>
      </div>

      <div style={styles.content}>
        {/* Status */}
        <StatusBanner status={incident.status} />

        {/* Person + time */}
        <div style={styles.section}>
          <h1 style={styles.personName}>
            Alert for {incident.personFirstName}
          </h1>
          <p style={styles.timeLabel}>
            Triggered {formatDistanceToNow(triggeredDate, { addSuffix: true })}
            {" -- "}
            {format(triggeredDate, "MMM d, h:mm a")}
          </p>
          {error && (
            <p style={{ fontSize: 12, color: "#f59e0b", margin: "6px 0 0" }}>
              {error}
            </p>
          )}
        </div>

        {/* Map */}
        <div style={styles.section}>
          <SectionLabel>Current Location</SectionLabel>
          <LiveMap location={incident.location} />
        </div>

        {/* Instructions */}
        {incident.instructions.length > 0 && (
          <div style={styles.section}>
            <InstructionCard instructions={incident.instructions} />
          </div>
        )}

        {/* Response buttons */}
        <div style={styles.section}>
          <SectionLabel>Your Response</SectionLabel>
          <ResponseButtons
            onRespond={handleRespond}
            disabled={incident.status === "resolved" || incident.status === "cancelled"}
          />
        </div>

        {/* Transcript summary */}
        {incident.transcriptSummary && (
          <div style={styles.section}>
            <SectionLabel>Summary</SectionLabel>
            <div style={styles.card}>
              <p style={{ margin: 0, fontSize: 14, lineHeight: 1.6, color: "#374151" }}>
                {incident.transcriptSummary}
              </p>
            </div>
          </div>
        )}

        {/* Audio clips */}
        {incident.audioClips.length > 0 && (
          <div style={styles.section}>
            <SectionLabel>Audio Clips</SectionLabel>
            <AudioPlayer clips={incident.audioClips} />
          </div>
        )}

        {/* Timeline */}
        <div style={styles.section}>
          <SectionLabel>Timeline</SectionLabel>
          <div style={styles.card}>
            <TimelineView events={incident.timeline} />
          </div>
        </div>

        {/* Footer */}
        <p style={styles.footer}>
          This page refreshes automatically every 10 seconds.
          <br />
          You are viewing this as a trusted contact.
        </p>
      </div>
    </div>
  );
}

function SectionLabel({ children }: { children: React.ReactNode }) {
  return (
    <p
      style={{
        margin: "0 0 8px",
        fontSize: 13,
        fontWeight: 600,
        color: "#6b7280",
        textTransform: "uppercase" as const,
        letterSpacing: 0.5,
      }}
    >
      {children}
    </p>
  );
}

const styles: Record<string, React.CSSProperties> = {
  page: {
    minHeight: "100dvh",
    backgroundColor: "#f9fafb",
    fontFamily:
      '-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif',
  },
  header: {
    position: "sticky",
    top: 0,
    zIndex: 50,
    backgroundColor: "#1a1a2e",
    padding: "12px 16px",
  },
  brandLabel: {
    margin: 0,
    fontSize: 15,
    fontWeight: 600,
    color: "#e0e7ff",
    letterSpacing: 0.3,
  },
  content: {
    maxWidth: 480,
    margin: "0 auto",
    padding: "16px 16px 40px",
    display: "flex",
    flexDirection: "column",
    gap: 20,
  },
  section: {},
  personName: {
    margin: 0,
    fontSize: 22,
    fontWeight: 700,
    color: "#1f2937",
  },
  timeLabel: {
    margin: "4px 0 0",
    fontSize: 13,
    color: "#6b7280",
  },
  card: {
    backgroundColor: "#fff",
    border: "1px solid #e5e7eb",
    borderRadius: 12,
    padding: 14,
  },
  loadingContainer: {
    minHeight: "100dvh",
    display: "flex",
    flexDirection: "column",
    alignItems: "center",
    justifyContent: "center",
    padding: 24,
  },
  spinner: {
    width: 32,
    height: 32,
    border: "3px solid #e5e7eb",
    borderTopColor: "#6366f1",
    borderRadius: "50%",
    animation: "spin 0.8s linear infinite",
  },
  footer: {
    fontSize: 12,
    color: "#9ca3af",
    textAlign: "center",
    lineHeight: 1.6,
    marginTop: 8,
  },
};
