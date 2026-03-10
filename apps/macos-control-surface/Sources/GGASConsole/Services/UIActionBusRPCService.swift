import Foundation
import Network

enum UIActionBusRPCRequestType: String, Codable {
    case snapshot
    case command
}

struct UIActionBusRPCRequest: Codable, Equatable {
    let type: UIActionBusRPCRequestType
    let command: UIActionBusCommandEnvelope?

    init(type: UIActionBusRPCRequestType, command: UIActionBusCommandEnvelope? = nil) {
        self.type = type
        self.command = command
    }
}

struct UIActionBusRPCResponse: Codable, Equatable {
    let ok: Bool
    let processedCommandId: String?
    let snapshot: UIActionBusSnapshot?
    let error: String?
}

@MainActor
final class UIActionBusRPCService: ObservableObject {
    nonisolated static let defaultHost = "127.0.0.1"
    nonisolated static let defaultPort: UInt16 = 7331

    @Published private(set) var isRunning = false
    @Published private(set) var endpointDescription: String
    @Published private(set) var lastErrorMessage: String?

    private let host: String
    private let port: UInt16
    private let queue = DispatchQueue(label: "gg.ui-action-bus.rpc", qos: .userInitiated)
    private var listener: NWListener?
    private var shell: AppShellState?
    private var workflow: WorkflowContextStore?

    init(
        host: String = defaultHost,
        port: UInt16 = defaultPort
    ) {
        self.host = host
        self.port = port
        self.endpointDescription = "\(host):\(port)"
    }

    deinit {
        listener?.cancel()
    }

    func bind(shell: AppShellState, workflow: WorkflowContextStore) {
        self.shell = shell
        self.workflow = workflow
    }

    func start() {
        guard listener == nil else { return }

        do {
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true
            parameters.requiredLocalEndpoint = .hostPort(
                host: NWEndpoint.Host(host),
                port: NWEndpoint.Port(rawValue: port) ?? .any
            )

            let listener = try NWListener(using: parameters)
            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor [weak self] in
                    self?.handleListenerState(state)
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                guard let self else { return }
                connection.start(queue: self.queue)
                Self.receiveRequest(on: connection) { [weak self] data in
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        let response = await self.responseData(for: data)
                        Self.sendResponse(response, on: connection)
                    }
                }
            }
            listener.start(queue: queue)
            self.listener = listener
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
    }

    static func handle(
        _ request: UIActionBusRPCRequest,
        shell: AppShellState,
        workflow: WorkflowContextStore
    ) async -> UIActionBusRPCResponse {
        switch request.type {
        case .snapshot:
            return UIActionBusRPCResponse(
                ok: true,
                processedCommandId: nil,
                snapshot: UIActionBus.snapshot(shell: shell, workflow: workflow),
                error: nil
            )
        case .command:
            guard let command = request.command else {
                return UIActionBusRPCResponse(
                    ok: false,
                    processedCommandId: nil,
                    snapshot: UIActionBus.snapshot(shell: shell, workflow: workflow),
                    error: "Missing command payload."
                )
            }

            do {
                let action = try command.resolvedAction()
                try await UIActionBus.performAsync(action, shell: shell, workflow: workflow)
                return UIActionBusRPCResponse(
                    ok: true,
                    processedCommandId: command.id,
                    snapshot: UIActionBus.snapshot(shell: shell, workflow: workflow),
                    error: nil
                )
            } catch {
                return UIActionBusRPCResponse(
                    ok: false,
                    processedCommandId: command.id,
                    snapshot: UIActionBus.snapshot(shell: shell, workflow: workflow),
                    error: error.localizedDescription
                )
            }
        }
    }

    private func handleListenerState(_ state: NWListener.State) {
        switch state {
        case .ready:
            isRunning = true
            lastErrorMessage = nil
            endpointDescription = "\(host):\(listener?.port?.rawValue ?? port)"
        case .failed(let error):
            lastErrorMessage = error.localizedDescription
            stop()
        case .cancelled:
            isRunning = false
        default:
            break
        }
    }

    private func responseData(for requestData: Data) async -> Data {
        do {
            guard let shell, let workflow else {
                return try Self.encodeResponse(
                    UIActionBusRPCResponse(
                        ok: false,
                        processedCommandId: nil,
                        snapshot: nil,
                        error: "RPC service is not bound to app state."
                    )
                )
            }

            let request = try JSONDecoder().decode(UIActionBusRPCRequest.self, from: requestData)
            let response = await Self.handle(request, shell: shell, workflow: workflow)
            if let error = response.error, !error.isEmpty {
                lastErrorMessage = error
            }
            return try Self.encodeResponse(response)
        } catch {
            lastErrorMessage = error.localizedDescription
            return (try? Self.encodeResponse(
                UIActionBusRPCResponse(
                    ok: false,
                    processedCommandId: nil,
                    snapshot: nil,
                    error: error.localizedDescription
                )
            )) ?? Data("{\"ok\":false,\"error\":\"RPC response encoding failed.\"}\n".utf8)
        }
    }

    nonisolated private static func encodeResponse(_ response: UIActionBusRPCResponse) throws -> Data {
        var data = try JSONEncoder.pretty.encode(response)
        data.append(0x0A)
        return data
    }

    nonisolated private static func receiveRequest(
        on connection: NWConnection,
        accumulated: Data = Data(),
        completion: @escaping (Data) -> Void
    ) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { content, _, isComplete, error in
            var next = accumulated
            if let content {
                next.append(content)
            }

            if error != nil || isComplete {
                completion(next)
                return
            }

            receiveRequest(on: connection, accumulated: next, completion: completion)
        }
    }

    nonisolated private static func sendResponse(_ data: Data, on connection: NWConnection) {
        connection.send(content: data, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}

private extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
