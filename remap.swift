// Mouse button remapper: Click, Double Click, Hold, Double Click + Hold, Click and Drag.
// Public Apple APIs only. Build:  swiftc -O remap.swift -o remap
import Cocoa

enum Action { case key(CGKeyCode, CGEventFlags), app(String), passThrough, none }   // app: launch a system app, e.g. Mission Control
enum Drag { case none, spaces, scroll }   // spaces: trackpad-style swipe (L/R = Spaces, up = Mission Control, down = App windows). scroll: drag scrolls.

struct Binding {
    var click: Action = .none, hold: Action = .none
    var doubleClick: Action = .none, doubleClickHold: Action = .none
    var drag: Drag = .none
}

// macOS button numbers: 2 = middle, 3 = "Button 4" (back), 4 = "Button 5" (forward).  `./remap --learn` prints them.
// Key codes: 33 '['  30 ']'  36 Return  8 C  2 D  123 Left  124 Right  160 Mission Control  131 App windows
let lookUp = Action.key(2, [.maskCommand, .maskControl])   // Look Up (Cmd+Ctrl+D)
let bindings: [Int64: Binding] = [
    2: Binding(click: .passThrough,           hold: .app("Mission Control"),       // Middle: click = middle click, hold = Mission Control
               doubleClick: .key(36, .maskShift), doubleClickHold: lookUp,         //         double click = Shift+Return, double click+hold = Look Up
               drag: .spaces),                                                     //         drag = Spaces & Mission Control
    3: Binding(click: .key(33, .maskCommand), hold: .key(9, .maskCommand)),        // Button 4: click = Back (Cmd+[), hold = Cmd+V
    4: Binding(click: .key(30, .maskCommand), hold: .key(8, .maskCommand)),        // Button 5: click = Forward (Cmd+]), hold = Cmd+C
]

let holdDelay: TimeInterval = 0.35      // press longer than this = Hold
let doubleClickWindow: TimeInterval = 0.3
let dragThreshold: CGFloat = 20         // pixels before a press becomes a drag (keeps a slightly shaky hold from becoming a drag)
let marker: Int64 = 0x4D4D52
let learnMode = CommandLine.arguments.contains("--learn")
func log(_ s: String) { print(s); fflush(stdout) }

func post(_ e: CGEvent) { e.setIntegerValueField(.eventSourceUserData, value: marker); e.post(tap: .cghidEventTap) }
func key(_ k: CGKeyCode, _ f: CGEventFlags) {
    for down in [true, false] { if let e = CGEvent(keyboardEventSource: nil, virtualKey: k, keyDown: down) { e.flags = f; post(e) } }
}
func perform(_ a: Action, button: Int64, at loc: CGPoint, times: Int = 1) {
    switch a {
    case .none: break
    case .app(let name):
        log("  -> open \(name)")
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/open"); p.arguments = ["-a", name]; try? p.run()
    case .key(let k, let f): log("  -> key \(k) flags \(f.rawValue) x\(times)"); for _ in 0..<times { key(k, f) }
    case .passThrough:
        log("  -> pass-through click button \(button) x\(times)")
        let btn = CGMouseButton(rawValue: UInt32(button)) ?? .center
        for i in 0..<times {
            for t in [CGEventType.otherMouseDown, .otherMouseUp] {
                if let e = CGEvent(mouseEventSource: nil, mouseType: t, mouseCursorPosition: loc, mouseButton: btn) {
                    e.setIntegerValueField(.mouseEventClickState, value: Int64(i + 1)); post(e)
                }
            }
        }
    }
}

// MARK: - Trackpad-style "dock swipe" simulation (Spaces / Mission Control that follows the pointer)
// Ported from Mac Mouse Fix's TouchSimulator.m (pre-macOS 27 path). These CGEvent fields are undocumented
// and were reverse-engineered; they work on macOS 26 and earlier. macOS 27 ignores them (needs private IOHIDEvent APIs).
func field(_ n: UInt32) -> CGEventField { unsafeBitCast(n, to: CGEventField.self) }
enum SwipeAxis { case horizontal, vertical }
struct Phase { static let began: Int = 1, changed = 2, ended = 4, cancelled = 8 }

final class DockSwipe {
    var axis: SwipeAxis? = nil
    var originOffset = 0.0, lastDelta = 0.0
    var resendTimers: [Timer] = []
    var screen: CGSize { NSScreen.main?.frame.size ?? CGSize(width: 1440, height: 900) }
    // Horizontal scale makes the Space follow the pointer. MMF derives this from the number of Spaces; 1.5 ≈ 3 Spaces.
    var scaleH: Double { originOffsetPerSpace / (screen.width + 63) }
    var scaleV: Double { 1.0 / screen.height }

    func begin(axis: SwipeAxis) { self.axis = axis; originOffset = 0; lastDelta = 0; resendTimers.forEach { $0.invalidate() }; resendTimers = []; post(delta: 0, phase: Phase.began) }
    func move(dx: Double, dy: Double) {
        guard let axis else { return }
        let d = axis == .horizontal ? -dx * scaleH : dy * scaleV
        post(delta: d, phase: Phase.changed)
    }
    func end() { guard axis != nil else { return }; post(delta: 0, phase: Phase.ended); axis = nil }

    private func post(delta d: Double, phase phaseIn: Int) {
        guard let axis else { return }
        var phase = phaseIn
        if phase == Phase.began { originOffset = d } else if phase == Phase.changed { if d == 0 { return }; originOffset += d }
        var exitSpeed = 0.0
        if phase == Phase.ended || phase == Phase.cancelled { exitSpeed = lastDelta * 100 }
        if phase == Phase.ended { phase = (lastDelta.sign == originOffset.sign) ? Phase.ended : Phase.cancelled }

        let type: Double = axis == .horizontal ? 1 : 2
        let weird: Double = axis == .horizontal ? 1.401298464324817e-45 : 2.802596928649634e-45
        let e29 = CGEvent(source: nil)!, e30 = CGEvent(source: nil)!
        e29.setDoubleValueField(field(55), value: 29)       // NSEventTypeGesture
        e29.setDoubleValueField(field(41), value: 33231)
        e30.setDoubleValueField(field(55), value: 30)       // NSEventTypeMagnify (that's what real dock swipes use)
        e30.setDoubleValueField(field(110), value: 23)      // kIOHIDEventTypeDockSwipe
        e30.setDoubleValueField(field(132), value: Double(phase))
        e30.setDoubleValueField(field(134), value: Double(phase))
        e30.setDoubleValueField(field(124), value: originOffset)
        let f32 = Float32(originOffset); let bits = Int64(f32.bitPattern)
        e30.setIntegerValueField(field(135), value: bits)   // origin offset again, as float bits in an int field
        e30.setDoubleValueField(field(41), value: 33231)
        e30.setDoubleValueField(field(119), value: weird)
        e30.setDoubleValueField(field(139), value: weird)
        e30.setDoubleValueField(field(123), value: type)
        e30.setDoubleValueField(field(165), value: type)
        e30.setIntegerValueField(field(136), value: 0)      // not inverted
        if phase == Phase.ended || phase == Phase.cancelled {
            e30.setDoubleValueField(field(129), value: exitSpeed)
            e30.setDoubleValueField(field(130), value: exitSpeed)
        }
        Self.send(e30, e29)
        if phase == Phase.ended || phase == Phase.cancelled {
            // MMF re-sends the end event twice; this avoids the transition getting stuck.
            for t in [0.2, 0.5] { resendTimers.append(Timer.scheduledTimer(withTimeInterval: t, repeats: false) { _ in Self.send(e30, e29) }) }
        }
        lastDelta = d
    }
    private static func send(_ e30: CGEvent, _ e29: CGEvent) { e30.post(tap: .cghidEventTap); e29.post(tap: .cghidEventTap) }
}
let originOffsetPerSpace = 1.5
let dockSwipe = DockSwipe()

final class ButtonState {
    var holdTimer: Timer?, clickTimer: Timer?
    var consumed = false, dragging = false, clickCount = 1
    var lastUp: TimeInterval = 0, downLoc = CGPoint.zero, acc = CGPoint.zero
}
var states: [Int64: ButtonState] = [:]

// Ask macOS to show the Accessibility prompt for whichever app launched us.
let trusted = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary)
if !trusted { print("Accessibility not granted yet (prompt shown). Grant it, then run again."); exit(1) }

let mask: CGEventMask = (1 << CGEventType.otherMouseDown.rawValue) | (1 << CGEventType.otherMouseUp.rawValue) | (1 << CGEventType.otherMouseDragged.rawValue)

guard let tap = CGEvent.tapCreate(
    tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: mask,
    callback: { _, type, event, _ in
        if event.getIntegerValueField(.eventSourceUserData) == marker { return Unmanaged.passUnretained(event) }
        let button = event.getIntegerValueField(.mouseEventButtonNumber)
        if learnMode { if type == .otherMouseDown { print("button \(button) pressed") }; return Unmanaged.passUnretained(event) }
        guard let b = bindings[button] else { return Unmanaged.passUnretained(event) }
        let s = states[button] ?? { let n = ButtonState(); states[button] = n; return n }()
        let loc = event.location, now = Date().timeIntervalSince1970
        if type != .otherMouseDragged { log("button \(button) \(type == .otherMouseDown ? "down" : "up")") }

        switch type {
        case .otherMouseDown:
            let isDouble = (now - s.lastUp) < doubleClickWindow && s.clickTimer != nil
            s.clickTimer?.invalidate(); s.clickTimer = nil
            s.clickCount = isDouble ? 2 : 1
            s.consumed = false; s.dragging = false; s.downLoc = loc; s.acc = .zero
            s.holdTimer?.invalidate()
            s.holdTimer = Timer.scheduledTimer(withTimeInterval: holdDelay, repeats: false) { _ in
                s.consumed = true
                perform(s.clickCount == 2 ? b.doubleClickHold : b.hold, button: button, at: loc)
            }

        case .otherMouseDragged:
            guard b.drag != .none, !s.consumed || s.dragging else { break }
            if !s.dragging {
                if hypot(loc.x - s.downLoc.x, loc.y - s.downLoc.y) < dragThreshold { break }
                s.dragging = true; s.consumed = true; s.holdTimer?.invalidate(); log("  -> drag start (button \(button))")
            }
            let dx = event.getDoubleValueField(.mouseEventDeltaX), dy = event.getDoubleValueField(.mouseEventDeltaY)
            switch b.drag {
            case .scroll:
                if let e = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: Int32(-dy), wheel2: Int32(-dx), wheel3: 0) { post(e) }
            case .spaces:
                if dockSwipe.axis == nil {
                    let tx = loc.x - s.downLoc.x, ty = loc.y - s.downLoc.y
                    dockSwipe.begin(axis: abs(tx) >= abs(ty) ? .horizontal : .vertical)
                }
                dockSwipe.move(dx: dx, dy: dy)
            case .none: break
            }

        case .otherMouseUp:
            s.holdTimer?.invalidate(); s.lastUp = now
            if s.dragging && b.drag == .spaces { dockSwipe.end() }
            if s.consumed { break }
            if s.clickCount == 2 {
                if case .none = b.doubleClick { perform(b.click, button: button, at: loc, times: 2) }
                else { perform(b.doubleClick, button: button, at: loc) }
            } else if case .none = b.doubleClick, case .none = b.doubleClickHold {
                perform(b.click, button: button, at: loc)           // nothing bound to double click: fire instantly
            } else {                                                 // wait briefly to see if a second click follows
                s.clickTimer = Timer.scheduledTimer(withTimeInterval: doubleClickWindow, repeats: false) { _ in
                    s.clickTimer = nil; perform(b.click, button: button, at: loc)
                }
            }
        default: break
        }
        return nil
    }, userInfo: nil)
else {
    print("Could not create event tap. Grant this program Accessibility access:")
    print("System Settings > Privacy & Security > Accessibility, then run it again.")
    exit(1)
}

CFRunLoopAddSource(CFRunLoopGetCurrent(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
CGEvent.tapEnable(tap: tap, enable: true)
print(learnMode ? "Learn mode: press mouse buttons, Ctrl+C to quit." : "remap running (Ctrl+C to quit)")
CFRunLoopRun()
