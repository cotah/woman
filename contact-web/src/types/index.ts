export type IncidentStatus =
  | "active"
  | "resolved"
  | "escalated"
  | "monitoring"
  | "cancelled";

export type ContactResponseType =
  | "trying_to_reach"
  | "could_not_reach"
  | "going_to_location"
  | "calling_authorities"
  | "mark_reviewed";

export interface Coordinates {
  lat: number;
  lng: number;
  timestamp: string;
  accuracy?: number;
}

export interface LocationTrail {
  current: Coordinates;
  trail: Coordinates[];
}

export interface TimelineEvent {
  id: string;
  type: "trigger" | "location_update" | "audio_clip" | "contact_response" | "status_change" | "system";
  message: string;
  timestamp: string;
  metadata?: Record<string, unknown>;
}

export interface AudioClip {
  id: string;
  url: string;
  duration: number;
  timestamp: string;
  transcript?: string;
}

export interface Incident {
  id: string;
  status: IncidentStatus;
  personFirstName: string;
  triggeredAt: string;
  resolvedAt?: string;
  location: LocationTrail;
  timeline: TimelineEvent[];
  audioClips: AudioClip[];
  transcriptSummary?: string;
  instructions: string[];
  contactId: string;
  contactName: string;
}

export interface ContactResponse {
  incidentId: string;
  contactId: string;
  responseType: ContactResponseType;
  timestamp: string;
  note?: string;
}

export interface ApiError {
  code: string;
  message: string;
}
