import SwiftUI
import UIKit

struct CanvasInputOverlay: UIViewRepresentable {
    var onTap: (CGPoint) -> Void
    var onPan: (CGSize, CanvasInputPhase) -> Void
    var onPinch: (CGFloat, CanvasInputPhase) -> Void
    var onPaintStroke: (CGPoint, CanvasInputPhase) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onTap: onTap, onPan: onPan, onPinch: onPinch, onPaintStroke: onPaintStroke)
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isMultipleTouchEnabled = true

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        tap.delegate = context.coordinator

        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        pan.minimumNumberOfTouches = 1
        pan.maximumNumberOfTouches = 1
        pan.delegate = context.coordinator

        let pinch = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePinch(_:)))
        pinch.delegate = context.coordinator

        let longPress = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleLongPress(_:)))
        longPress.minimumPressDuration = 0.3
        longPress.allowableMovement = 10
        longPress.delegate = context.coordinator

        tap.require(toFail: longPress)
        pan.require(toFail: longPress)

        view.addGestureRecognizer(tap)
        view.addGestureRecognizer(pan)
        view.addGestureRecognizer(pinch)
        view.addGestureRecognizer(longPress)

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onTap = onTap
        context.coordinator.onPan = onPan
        context.coordinator.onPinch = onPinch
        context.coordinator.onPaintStroke = onPaintStroke
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onTap: (CGPoint) -> Void
        var onPan: (CGSize, CanvasInputPhase) -> Void
        var onPinch: (CGFloat, CanvasInputPhase) -> Void
        var onPaintStroke: (CGPoint, CanvasInputPhase) -> Void

        init(
            onTap: @escaping (CGPoint) -> Void,
            onPan: @escaping (CGSize, CanvasInputPhase) -> Void,
            onPinch: @escaping (CGFloat, CanvasInputPhase) -> Void,
            onPaintStroke: @escaping (CGPoint, CanvasInputPhase) -> Void
        ) {
            self.onTap = onTap
            self.onPan = onPan
            self.onPinch = onPinch
            self.onPaintStroke = onPaintStroke
        }

        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended, let view = recognizer.view else { return }
            onTap(recognizer.location(in: view))
        }

        @objc func handlePan(_ recognizer: UIPanGestureRecognizer) {
            guard let view = recognizer.view else { return }
            let translation = recognizer.translation(in: view)
            let phase = CanvasInputPhase(recognizer.state)
            onPan(CGSize(width: translation.x, height: translation.y), phase)
        }

        @objc func handlePinch(_ recognizer: UIPinchGestureRecognizer) {
            let phase = CanvasInputPhase(recognizer.state)
            onPinch(recognizer.scale, phase)
        }

        @objc func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
            guard let view = recognizer.view else { return }
            let location = recognizer.location(in: view)
            let phase = CanvasInputPhase(recognizer.state)
            onPaintStroke(location, phase)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            gestureRecognizer is UIPinchGestureRecognizer || otherGestureRecognizer is UIPinchGestureRecognizer
        }
    }
}

enum CanvasInputPhase: Equatable {
    case began
    case changed
    case ended
    case cancelled

    init(_ state: UIGestureRecognizer.State) {
        switch state {
        case .began:
            self = .began
        case .changed:
            self = .changed
        case .ended:
            self = .ended
        case .cancelled, .failed:
            self = .cancelled
        default:
            self = .changed
        }
    }
}
