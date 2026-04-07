import { useEffect, useRef } from "react";
import L from "leaflet";
import type { LocationTrail } from "../types";

// Fix default marker icon issue with bundlers
import markerIcon2x from "leaflet/dist/images/marker-icon-2x.png";
import markerIcon from "leaflet/dist/images/marker-icon.png";
import markerShadow from "leaflet/dist/images/marker-shadow.png";

delete (L.Icon.Default.prototype as Record<string, unknown>)._getIconUrl;
L.Icon.Default.mergeOptions({
  iconRetinaUrl: markerIcon2x,
  iconUrl: markerIcon,
  shadowUrl: markerShadow,
});

interface Props {
  location: LocationTrail;
}

export default function LiveMap({ location }: Props) {
  const containerRef = useRef<HTMLDivElement>(null);
  const mapRef = useRef<L.Map | null>(null);
  const markerRef = useRef<L.Marker | null>(null);
  const polylineRef = useRef<L.Polyline | null>(null);

  // Initialize map
  useEffect(() => {
    if (!containerRef.current || mapRef.current) return;

    const map = L.map(containerRef.current, {
      zoomControl: false,
      attributionControl: false,
    }).setView([location.current.lat, location.current.lng], 16);

    L.tileLayer("https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png", {
      maxZoom: 19,
    }).addTo(map);

    // Add zoom control to bottom-right
    L.control.zoom({ position: "bottomright" }).addTo(map);

    mapRef.current = map;

    return () => {
      map.remove();
      mapRef.current = null;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // Update markers and trail on location change
  useEffect(() => {
    const map = mapRef.current;
    if (!map) return;

    const currentLatLng: L.LatLngExpression = [
      location.current.lat,
      location.current.lng,
    ];

    // Update or create marker
    if (markerRef.current) {
      markerRef.current.setLatLng(currentLatLng);
    } else {
      markerRef.current = L.marker(currentLatLng).addTo(map);
    }

    // Build trail coordinates
    const trailCoords: L.LatLngExpression[] = location.trail.map((c) => [
      c.lat,
      c.lng,
    ]);
    trailCoords.push(currentLatLng);

    // Update or create polyline
    if (polylineRef.current) {
      polylineRef.current.setLatLngs(trailCoords);
    } else {
      polylineRef.current = L.polyline(trailCoords, {
        color: "#6366f1",
        weight: 3,
        opacity: 0.7,
        dashArray: "6 4",
      }).addTo(map);
    }

    // Pan to current position
    map.panTo(currentLatLng, { animate: true, duration: 0.5 });
  }, [location]);

  return (
    <div
      ref={containerRef}
      style={{
        width: "100%",
        height: 300,
        borderRadius: 12,
        overflow: "hidden",
        border: "1px solid #e5e7eb",
      }}
    />
  );
}
