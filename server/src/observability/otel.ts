import { diag, DiagConsoleLogger, DiagLogLevel } from '@opentelemetry/api';
import { NodeSDK } from '@opentelemetry/sdk-node';
import { OTLPTraceExporter } from '@opentelemetry/exporter-trace-otlp-http';
import { getNodeAutoInstrumentations } from '@opentelemetry/auto-instrumentations-node';
import { Resource } from '@opentelemetry/resources';
import { SemanticResourceAttributes } from '@opentelemetry/semantic-conventions';

const tracingEnabled =
  process.env.OTEL_TRACING_ENABLED === 'true' ||
  !!process.env.OTEL_EXPORTER_OTLP_ENDPOINT ||
  !!process.env.OTEL_EXPORTER_OTLP_TRACES_ENDPOINT;

if (process.env.OTEL_LOG_LEVEL) {
  const level =
    process.env.OTEL_LOG_LEVEL === 'debug'
      ? DiagLogLevel.DEBUG
      : process.env.OTEL_LOG_LEVEL === 'info'
        ? DiagLogLevel.INFO
        : process.env.OTEL_LOG_LEVEL === 'warn'
          ? DiagLogLevel.WARN
          : process.env.OTEL_LOG_LEVEL === 'error'
            ? DiagLogLevel.ERROR
            : DiagLogLevel.NONE;
  diag.setLogger(new DiagConsoleLogger(), level);
}

if (tracingEnabled) {
  const resource = new Resource({
    [SemanticResourceAttributes.SERVICE_NAME]:
      process.env.OTEL_SERVICE_NAME ?? 'cogniread-sync',
    [SemanticResourceAttributes.SERVICE_VERSION]:
      process.env.APP_VERSION ?? process.env.npm_package_version ?? '0.0.0',
    [SemanticResourceAttributes.DEPLOYMENT_ENVIRONMENT]:
      process.env.OTEL_ENVIRONMENT ?? process.env.NODE_ENV ?? 'development',
  });

  const exporter = new OTLPTraceExporter({
    url:
      process.env.OTEL_EXPORTER_OTLP_TRACES_ENDPOINT ??
      process.env.OTEL_EXPORTER_OTLP_ENDPOINT,
    headers: parseHeaders(process.env.OTEL_EXPORTER_OTLP_HEADERS),
  });

  const sdk = new NodeSDK({
    resource,
    traceExporter: exporter,
    instrumentations: [
      getNodeAutoInstrumentations({
        '@opentelemetry/instrumentation-fs': { enabled: false },
      }),
    ],
  });

  try {
    sdk.start();
    diag.debug('OpenTelemetry tracing started');
  } catch (error) {
    console.error('OpenTelemetry start error', error);
  }

  const shutdown = async () => {
    try {
      await sdk.shutdown();
    } catch (error) {
      console.error('OpenTelemetry shutdown error', error);
    }
  };

  process.on('SIGTERM', shutdown);
  process.on('SIGINT', shutdown);
}

function parseHeaders(
  raw?: string,
): Record<string, string> | undefined {
  if (!raw) {
    return undefined;
  }
  const headers: Record<string, string> = {};
  for (const part of raw.split(',')) {
    const [key, value] = part.split('=').map((item) => item.trim());
    if (key && value) {
      headers[key] = value;
    }
  }
  return Object.keys(headers).length > 0 ? headers : undefined;
}
