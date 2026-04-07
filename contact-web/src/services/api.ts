import axios, { AxiosInstance } from "axios";
import type { Incident, ContactResponseType, ContactResponse } from "../types";

const API_URL = import.meta.env.VITE_API_URL || "/api";

function getAccessToken(): string | null {
  const params = new URLSearchParams(window.location.search);
  return params.get("token");
}

function createClient(): AxiosInstance {
  const token = getAccessToken();
  return axios.create({
    baseURL: API_URL,
    headers: {
      "Content-Type": "application/json",
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
  });
}

let client = createClient();

/** Refresh the client (e.g. if the URL changes) */
export function refreshClient(): void {
  client = createClient();
}

/** Fetch the incident data linked to this contact token */
export async function fetchIncident(): Promise<Incident> {
  const { data } = await client.get<Incident>("/contact/incident");
  return data;
}

/** Submit a contact response */
export async function submitResponse(
  incidentId: string,
  responseType: ContactResponseType,
  note?: string
): Promise<ContactResponse> {
  const { data } = await client.post<ContactResponse>(
    `/contact/incident/${incidentId}/respond`,
    { responseType, note }
  );
  return data;
}

/** Validate token - returns true if valid */
export async function validateToken(): Promise<boolean> {
  try {
    await client.get("/contact/validate");
    return true;
  } catch {
    return false;
  }
}

export { getAccessToken };
