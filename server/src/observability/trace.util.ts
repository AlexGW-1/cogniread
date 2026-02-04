import { context, trace } from '@opentelemetry/api';

export type TraceContext = {
  traceId?: string;
  spanId?: string;
};

export const getTraceContext = (): TraceContext => {
  const span = trace.getSpan(context.active());
  if (!span) {
    return {};
  }
  const spanContext = span.spanContext();
  return {
    traceId: spanContext.traceId,
    spanId: spanContext.spanId,
  };
};
