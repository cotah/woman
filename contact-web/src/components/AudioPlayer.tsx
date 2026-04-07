import { useRef, useState } from "react";
import { format } from "date-fns";
import type { AudioClip } from "../types";

interface Props {
  clips: AudioClip[];
}

function ClipRow({ clip }: { clip: AudioClip }) {
  const audioRef = useRef<HTMLAudioElement>(null);
  const [playing, setPlaying] = useState(false);
  const [progress, setProgress] = useState(0);

  const toggle = () => {
    const el = audioRef.current;
    if (!el) return;
    if (playing) {
      el.pause();
    } else {
      el.play();
    }
    setPlaying(!playing);
  };

  const onTimeUpdate = () => {
    const el = audioRef.current;
    if (!el || !el.duration) return;
    setProgress((el.currentTime / el.duration) * 100);
  };

  const onEnded = () => {
    setPlaying(false);
    setProgress(0);
  };

  const durationLabel = () => {
    const s = Math.round(clip.duration);
    const m = Math.floor(s / 60);
    const sec = s % 60;
    return `${m}:${sec.toString().padStart(2, "0")}`;
  };

  return (
    <div
      style={{
        display: "flex",
        alignItems: "center",
        gap: 10,
        padding: "10px 12px",
        border: "1px solid #e5e7eb",
        borderRadius: 10,
        backgroundColor: "#fafafa",
      }}
    >
      <audio
        ref={audioRef}
        src={clip.url}
        preload="metadata"
        onTimeUpdate={onTimeUpdate}
        onEnded={onEnded}
      />

      {/* Play / pause button */}
      <button
        onClick={toggle}
        style={{
          width: 36,
          height: 36,
          borderRadius: "50%",
          border: "none",
          backgroundColor: "#6366f1",
          color: "#fff",
          fontSize: 14,
          cursor: "pointer",
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
          flexShrink: 0,
        }}
        aria-label={playing ? "Pause" : "Play"}
      >
        {playing ? "||" : "\u25B6"}
      </button>

      {/* Progress bar and meta */}
      <div style={{ flex: 1, minWidth: 0 }}>
        <div
          style={{
            height: 4,
            borderRadius: 2,
            backgroundColor: "#e5e7eb",
            overflow: "hidden",
            marginBottom: 4,
          }}
        >
          <div
            style={{
              height: "100%",
              width: `${progress}%`,
              backgroundColor: "#6366f1",
              transition: "width 0.2s linear",
            }}
          />
        </div>
        <div
          style={{
            display: "flex",
            justifyContent: "space-between",
            fontSize: 11,
            color: "#9ca3af",
          }}
        >
          <span>{durationLabel()}</span>
          <span>{format(new Date(clip.timestamp), "h:mm a")}</span>
        </div>
      </div>
    </div>
  );
}

export default function AudioPlayer({ clips }: Props) {
  if (clips.length === 0) return null;

  return (
    <div style={{ display: "flex", flexDirection: "column", gap: 8 }}>
      {clips.map((clip) => (
        <ClipRow key={clip.id} clip={clip} />
      ))}
    </div>
  );
}
