interface Props {
  instructions: string[];
}

export default function InstructionCard({ instructions }: Props) {
  if (instructions.length === 0) return null;

  return (
    <div
      style={{
        backgroundColor: "#f0f9ff",
        border: "1px solid #bae6fd",
        borderRadius: 12,
        padding: 16,
      }}
    >
      <p
        style={{
          margin: "0 0 10px",
          fontSize: 14,
          fontWeight: 600,
          color: "#0c4a6e",
        }}
      >
        What you can do
      </p>
      <ul
        style={{
          margin: 0,
          paddingLeft: 18,
          display: "flex",
          flexDirection: "column",
          gap: 6,
        }}
      >
        {instructions.map((text, i) => (
          <li
            key={i}
            style={{
              fontSize: 13,
              lineHeight: 1.5,
              color: "#1e3a5f",
            }}
          >
            {text}
          </li>
        ))}
      </ul>
    </div>
  );
}
