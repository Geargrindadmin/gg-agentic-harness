// CommandTextEditor.swift — NSTextView wrapper that correctly intercepts ⌘↵
// and calls onSubmit. Replaces SwiftUI TextEditor which swallows ⌘↵.
//
// The key design: onCommandReturn lives on the NSTextView itself, not in a
// closure that captures a stale SwiftUI value. updateNSView always refreshes
// the callback so the latest runCommand() is always called.

import SwiftUI
import AppKit

// MARK: - SwiftUI wrapper

struct CommandTextEditor: NSViewRepresentable {
    @Binding var text: String
    var onSubmit: (() -> Void)? = nil
    var placeholder: String = "Type a task or command…"
    var font: NSFont = .monospacedSystemFont(ofSize: 13, weight: .regular)
    var submitOnCommandReturn: Bool = false
    var autoFocus: Bool = false

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = false

        let tv = CommandNSTextView(frame: .zero, textContainer: nil)
        tv.delegate = context.coordinator
        tv.isRichText = false
        tv.isEditable = true
        tv.isSelectable = true
        tv.allowsUndo = true
        tv.font = font
        tv.textColor = NSColor.labelColor
        tv.backgroundColor = NSColor.clear
        tv.drawsBackground = false
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.textContainerInset = NSSize(width: 5, height: 7)
        tv.textContainer?.widthTracksTextView = true
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [NSView.AutoresizingMask.width]
        tv.placeholderText = placeholder

        scroll.documentView = tv
        context.coordinator.textView = tv
        // Set the initial callback
        tv.onCommandReturn = context.coordinator.submitAction
        tv.submitOnCommandReturn = submitOnCommandReturn
        tv.updatePlaceholderVisibility()
        if autoFocus {
            DispatchQueue.main.async {
                tv.window?.makeFirstResponder(tv)
            }
        }
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let tv = nsView.documentView as? CommandNSTextView else { return }

        // CRITICAL: always refresh the submit callback so the latest closure is used
        context.coordinator.onSubmit = onSubmit
        tv.onCommandReturn = context.coordinator.submitAction
        tv.submitOnCommandReturn = submitOnCommandReturn
        tv.placeholderText = placeholder

        // Only overwrite text when it changed externally (e.g. cleared after submit)
        if tv.string != text {
            let sel = tv.selectedRanges
            tv.string = text
            tv.selectedRanges = sel
        }
        tv.updatePlaceholderVisibility()
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text, onSubmit: onSubmit) }

    // MARK: - Coordinator

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        var onSubmit: (() -> Void)?
        weak var textView: NSTextView?

        init(text: Binding<String>, onSubmit: (() -> Void)?) {
            self._text = text
            self.onSubmit = onSubmit
        }

        /// Stable function reference handed to the NSTextView.
        /// Always delegates to the current `onSubmit` captured by `updateNSView`.
        lazy var submitAction: () -> Void = { [weak self] in
            self?.onSubmit?()
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            text = tv.string
            (tv as? CommandNSTextView)?.updatePlaceholderVisibility()
        }
    }
}

// MARK: - Custom NSTextView

final class CommandNSTextView: NSTextView {
    var onCommandReturn: (() -> Void)?
    var submitOnCommandReturn: Bool = false
    var placeholderText: String = "" {
        didSet {
            placeholderLabel.stringValue = placeholderText
            updatePlaceholderVisibility()
        }
    }

    private let placeholderLabel: NSTextField = {
        let label = NSTextField(labelWithString: "")
        label.textColor = .placeholderTextColor
        label.backgroundColor = .clear
        label.isBordered = false
        label.isEditable = false
        label.isSelectable = false
        label.lineBreakMode = .byTruncatingTail
        return label
    }()

    override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        super.init(frame: frameRect, textContainer: container)
        setupPlaceholder()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupPlaceholder()
    }

    private func setupPlaceholder() {
        placeholderLabel.font = self.font
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(placeholderLabel)
        NSLayoutConstraint.activate([
            placeholderLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 9),
            placeholderLabel.topAnchor.constraint(equalTo: topAnchor, constant: 9),
            placeholderLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -9)
        ])
    }

    override func didChangeText() {
        super.didChangeText()
        updatePlaceholderVisibility()
    }

    func updatePlaceholderVisibility() {
        placeholderLabel.font = self.font
        placeholderLabel.isHidden = !self.string.isEmpty
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // ⌘↵ submits
        if submitOnCommandReturn,
           event.keyCode == 36,
           event.modifierFlags.contains(.command) {
            onCommandReturn?()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}
