const CURSOR_VERSION = 1;

export type CursorPayload = {
  v: number;
  createdAt: string;
  id: string;
};

export const encodeCursor = (createdAt: Date, id: string): string => {
  const payload: CursorPayload = {
    v: CURSOR_VERSION,
    createdAt: createdAt.toISOString(),
    id,
  };
  const json = JSON.stringify(payload);
  return Buffer.from(json, 'utf8').toString('base64url');
};

export const decodeCursor = (cursor?: string | null): CursorPayload | null => {
  if (!cursor) {
    return null;
  }
  try {
    const json = Buffer.from(cursor, 'base64url').toString('utf8');
    const parsed = JSON.parse(json) as CursorPayload;
    if (
      !parsed ||
      parsed.v !== CURSOR_VERSION ||
      typeof parsed.createdAt !== 'string' ||
      typeof parsed.id !== 'string'
    ) {
      return null;
    }
    if (Number.isNaN(Date.parse(parsed.createdAt))) {
      return null;
    }
    return parsed;
  } catch {
    return null;
  }
};
