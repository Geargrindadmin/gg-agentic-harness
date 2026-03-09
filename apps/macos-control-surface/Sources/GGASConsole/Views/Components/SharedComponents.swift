// SharedComponents.swift — reusable views used across multiple tabs

import SwiftUI

// MARK: - Status indicator dot

struct StatusDot: View {
    let status: AgentRun.RunStatus
    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .overlay {
                if status == .running {
                    Circle().fill(color.opacity(0.4))
                        .scaleEffect(1.8)
                        .animation(.easeInOut(duration: 1).repeatForever(), value: status)
                }
            }
    }
    private var color: Color {
        switch status {
        case .running:   return .yellow
        case .complete:  return .green
        case .failed:    return .red
        case .cancelled: return .gray
        case .accepted:  return .blue
        }
    }
}

// MARK: - Stat badge (count + label)

struct StatBadge: View {
    let label: String
    let value: Int
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.title2.monospacedDigit().bold())
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
