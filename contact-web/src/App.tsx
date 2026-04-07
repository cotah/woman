import { BrowserRouter, Routes, Route, Navigate } from "react-router-dom";
import IncidentPage from "./pages/IncidentPage";
import InvalidTokenPage from "./pages/InvalidTokenPage";

export default function App() {
  return (
    <BrowserRouter>
      <Routes>
        <Route path="/" element={<IncidentPage />} />
        <Route path="/invalid" element={<InvalidTokenPage />} />
        <Route path="*" element={<Navigate to="/invalid" replace />} />
      </Routes>
    </BrowserRouter>
  );
}
