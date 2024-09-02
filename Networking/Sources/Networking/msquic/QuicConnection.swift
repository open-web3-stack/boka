import Foundation
import msquic

class QuicConnection {
    private var connection: HQuic?
    private let api: UnsafePointer<QuicApiTable>?
    private var registration: HQuic?
    private var configuration: HQuic?
    init(api: UnsafePointer<QuicApiTable>?, registration: HQuic?, configuration: HQuic?) throws {
        self.api = api
        self.registration = registration
        self.configuration = configuration
    }

    func open() throws {
        let status = (api?.pointee.ConnectionOpen(
            registration,
            { _, context, event -> QuicStatus in

                let quicConnection = Unmanaged<QuicConnection>.fromOpaque(context!)
                    .takeUnretainedValue()
                return quicConnection.handleEvent(event)
            }, Unmanaged.passUnretained(self).toOpaque(), &connection
        )).status
        if status.isFailed {
            throw QuicError.invalidStatus(status: status.code)
        }
    }

    func start(target: String, port: UInt16) throws {
        let status =
            (api?.pointee.ConnectionStart(
                connection, configuration, UInt8(QUIC_ADDRESS_FAMILY_UNSPEC), target, port
            )).status
        if status.isFailed {
            throw QuicError.invalidStatus(status: status.code)
        }
    }

    private func handleEvent(_ event: UnsafePointer<QUIC_CONNECTION_EVENT>?) -> QuicStatus {
        // guard let event else {
        // return QuicStatusCode.connectionIdle.rawValue
        // }
        switch event?.pointee.Type {
        case QUIC_CONNECTION_EVENT_CONNECTED:
            print("Connected")

        case QUIC_CONNECTION_EVENT_SHUTDOWN_COMPLETE:
            print("Connection shutdown complete")
            if event?.pointee.SHUTDOWN_COMPLETE.AppCloseInProgress == 0 {
                relese()
            }

        default:
            break
        }
        return QuicStatusCode.success.rawValue
    }

    func relese() {
        if connection != nil {
            print("Connection Close")
            api?.pointee.ConnectionClose(connection)
            connection = nil
        }
    }

    deinit {
        relese()
        print("QuicConnection Deinit")
    }
}
