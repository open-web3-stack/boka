import ConsoleKit
import Foundation
import OTel
import OTLPGRPC
import ServiceLifecycle
import TracingUtils

public func parse(from: String) -> (
    filters: [String: Logger.Level],
    defaultLevel: Logger.Level,
    minimalLevel: Logger.Level
)? {
    var defaultLevel: Logger.Level?
    var lowestLevel = Logger.Level.critical
    var filters: [String: Logger.Level] = [:]
    let parts = from.split(separator: ",")
    for part in parts {
        let entry = part.split(separator: "=")
        switch entry.count {
        case 1:
            guard let level = parseLevel(String(entry[0])) else {
                return nil
            }
            defaultLevel = level
        case 2:
            guard let level = parseLevel(String(entry[1])) else {
                return nil
            }
            filters[String(entry[0].lowercased())] = level
            lowestLevel = min(lowestLevel, level)
        default:
            return nil
        }
    }

    return (
        filters: filters,
        defaultLevel: defaultLevel ?? .info,
        minimalLevel: min(lowestLevel, defaultLevel ?? .critical)
    )
}

private func parseLevel(_ level: String) -> Logger.Level? {
    switch level.lowercased().trimmingCharacters(in: .whitespaces) {
    case "trace": .trace
    case "debug": .debug
    case "info": .info
    case "notice": .notice
    case "warn", "warning": .warning
    case "error": .error
    case "critical": .critical
    default: nil
    }
}

public enum Tracing {
    public static func bootstrap(_ serviceName: String, loggerOnly: Bool = false) async throws -> [Service] {
        let env = ProcessInfo.processInfo.environment

        let (filters, defaultLevel, minimalLevel) = parse(from: env["LOG_LEVEL"] ?? "") ?? {
            print("Invalid LOG_LEVEL, using default")
            return (filters: [:], defaultLevel: .info, minimalLevel: .info)
        }()

        LoggingSystem.bootstrap({ label, metadataProvider in
            BokaLogger(
                fragment: LogFragment(),
                label: label,
                level: minimalLevel,
                metadataProvider: metadataProvider,
                defaultLevel: defaultLevel,
                filters: filters
            )
        }, metadataProvider: .otel)

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
