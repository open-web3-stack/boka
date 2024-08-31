import Foundation
import msquic

class QuicConnection {
    private var connection: HQUIC?
    private let api: UnsafePointer<QuicApiTable>?
    private let registration: HQuic?
    private let configuration: HQuic?
    init(api: UnsafePointer<QuicApiTable>, registration: HQuic?, configuration: HQuic?) throws {
        self.api = api
        self.registration = registration
        self.configuration = configuration
    }

    func open() throws {
        guard let api else {
            throw QuicError.getApiFailed
        }
        let status = api.pointee.ConnectionOpen(registration, { _, context, event -> QuicStatus in
            let quicConnection = Unmanaged<QuicConnection>.fromOpaque(context!).takeUnretainedValue()
            return quicConnection.handleEvent(event)
        }, Unmanaged.passUnretained(self).toOpaque(), &connection)
        if QuicStatus(status).isFailed {
            throw QuicError.invalidStatus(status: status.code)
        }
    }

    func start(target: String, port: UInt16) throws {
        guard let api else {
            throw QuicError.getApiFailed
        }
        let status = api.pointee.ConnectionStart(connection, configuration, UInt8(QUIC_ADDRESS_FAMILY_UNSPEC), target, port)
        if QuicStatus(status).isFailed {
            throw QuicError.invalidStatus(status: status.code)
        }
    }

    private func handleEvent(_ event: UnsafePointer<QUIC_CONNECTION_EVENT>?) -> QuicStatus {
//        guard let api = self.api else {
//            return QuicStatusCode.internalError.rawValue
//        }
        switch event?.pointee.Type {
        case QUIC_CONNECTION_EVENT_CONNECTED:
            print("Connected")

        case QUIC_CONNECTION_EVENT_SHUTDOWN_COMPLETE:
            print("Connection shutdown complete")
            if event?.pointee.SHUTDOWN_COMPLETE.AppCloseInProgress == 0 {
                api?.pointee.ConnectionClose(connection)
            }

        default:
            break
        }
        return QuicStatusCode.success.rawValue
    }

    deinit {
        print("QuicConnection deinit")
        if connection != nil {
            api?.pointee.ConnectionClose(connection)
        }
    }
}
