const decodeJwtPayload = (token: string): Record<string, unknown> | null => {
  const segments = token.split('.');
  if (segments.length < 2) {
    return null;
  }
  try {
    const payload = Buffer.from(segments[1], 'base64url').toString('utf8');
    const parsed = JSON.parse(payload) as Record<string, unknown>;
    if (!parsed || typeof parsed !== 'object') {
      return null;
    }
    return parsed;
  } catch {
    return null;
  }
};

export const extractUserIdFromToken = (token: string): string | null => {
  const payload = decodeJwtPayload(token);
  if (!payload) {
    return null;
  }
  const candidate = payload.sub ?? payload.userId ?? payload.uid;
  if (typeof candidate !== 'string' || candidate.trim().length === 0) {
    return null;
  }
  return candidate;
};

export const extractUserIdFromAuthHeader = (
  header?: string | string[],
): string | null => {
  if (typeof header !== 'string' || !header.startsWith('Bearer ')) {
    return null;
  }
  const token = header.slice('Bearer '.length).trim();
  if (!token) {
    return null;
  }
  return extractUserIdFromToken(token);
};
