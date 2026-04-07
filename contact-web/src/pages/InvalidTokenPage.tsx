export default function InvalidTokenPage() {
  return (
    <div
      style={{
        minHeight: "100dvh",
        display: "flex",
        flexDirection: "column",
        alignItems: "center",
        justifyContent: "center",
        padding: 24,
        backgroundColor: "#fafafa",
        textAlign: "center",
      }}
    >
      <div
        style={{
          width: 56,
          height: 56,
          borderRadius: "50%",
          backgroundColor: "#fee2e2",
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
          fontSize: 24,
          marginBottom: 20,
        }}
      >
        !
      </div>
      <h1
        style={{
          margin: "0 0 8px",
          fontSize: 20,
          fontWeight: 600,
          color: "#1f2937",
        }}
      >
        This link is no longer valid
      </h1>
      <p
        style={{
          margin: 0,
          fontSize: 14,
          color: "#6b7280",
          lineHeight: 1.6,
          maxWidth: 320,
        }}
      >
        The access link you used has expired or is invalid. If you believe this
        is an error, please contact the person who shared it with you.
      </p>
    </div>
  );
}
