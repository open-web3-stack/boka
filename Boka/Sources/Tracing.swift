import ConsoleKit
import OTel
import OTLPGRPC
import ServiceLifecycle
import TracingUtils

public enum Tracing {
    public static func bootstrap(_ serviceName: String, loggerOnly: Bool = false) async throws -> [Service] {
        // Bootstrap the logging backend with the OTel metadata provider which includes span IDs in logging messages.
        LoggingSystem.bootstrap(
            fragment: timestampDefaultLoggerFragment(),
            console: Terminal(),
            level: .trace,
            metadataProvider: .otel
        )

        if loggerOnly {
            return []
        }

        // Configure OTel resource detection to automatically apply helpful attributes to events.
        let environment = OTelEnvironment.detected()
        let resourceDetection = OTelResourceDetection(detectors: [
            OTelProcessResourceDetector(),
            OTelEnvironmentResourceDetector(environment: environment),
            .manual(
                OTelResource(
                    attributes: SpanAttributes(["service.name": serviceName.toSpanAttribute()])
                )
            ),
        ])
        let resource = await resourceDetection.resource(environment: environment, logLevel: .trace)

        // Bootstrap the metrics backend to export metrics periodically in OTLP/gRPC.
        let registry = OTelMetricRegistry()
        let metricsExporter = try OTLPGRPCMetricExporter(
            configuration: .init(environment: environment)
        )
        let metrics = OTelPeriodicExportingMetricsReader(
            resource: resource,
            producer: registry,
            exporter: metricsExporter,
            configuration: .init(environment: environment)
        )
        MetricsSystem.bootstrap(OTLPMetricsFactory(registry: registry))

        // Bootstrap the tracing backend to export traces periodically in OTLP/gRPC.
        let exporter = try OTLPGRPCSpanExporter(configuration: .init(environment: environment))
        let processor = OTelBatchSpanProcessor(
            exporter: exporter, configuration: .init(environment: environment)
        )
        let tracer = OTelTracer(
            idGenerator: OTelRandomIDGenerator(),
            sampler: OTelConstantSampler(isOn: true),
            propagator: OTelW3CPropagator(),
            processor: processor,
            environment: environment,
            resource: resource
        )
        InstrumentationSystem.bootstrap(tracer)

        return [tracer, metrics]
    }
}
