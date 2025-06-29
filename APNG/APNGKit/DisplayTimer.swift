//
//  DisplayTimer.swift
//  APNGKit
//
//  Created by 李旭 on 2025/6/22.
//

import Foundation
import QuartzCore

// 并发安全的 actor 用于管理 Timer 状态
actor TimerState {
    private var _isPaused: Bool = false
    private var timer: Timer?
    private let mode: RunLoop.Mode
    private let action: (TimeInterval) -> Void
    private weak var target: AnyObject?

    init(mode: RunLoop.Mode, target: AnyObject, action: @escaping (TimeInterval) -> Void) {
        self.mode = mode
        self.target = target
        self.action = action
        self.timer = createTimer()
    }

    var isPaused: Bool {
        get { _isPaused }
        set {
            if newValue {
                timer?.invalidate()
                _isPaused = true
            } else {
                if timer == nil || !(timer?.isValid ?? false) {
                    timer = createTimer()
                }
                _isPaused = false
            }
        }
    }

    func invalidate() {
        timer?.invalidate()
        timer = nil
        _isPaused = true
    }

    private func createTimer() -> Timer {
        #if canImport(AppKit)
        let displayMode = CGDisplayCopyDisplayMode(CGMainDisplayID())
        let refreshRate = max(displayMode?.refreshRate ?? 60.0, 60.0)
        #else
        let refreshRate = 60.0
        #endif

        let interval: TimeInterval
        #if DEBUG
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            interval = 0.0
        } else {
            interval = 1 / refreshRate
        }
        #else
        interval = 1 / refreshRate
        #endif

        let timer = Timer(timeInterval: interval, target: self, selector: #selector(step), userInfo: nil, repeats: true)
        RunLoop.main.add(timer, forMode: mode)
        return timer
    }

    @objc private func step(timer: Timer) {
        if target == nil {
            timer.invalidate()
        } else {
            action(CACurrentMediaTime())
        }
    }
}

/// Provides a timer to drive the animation.
///
/// The implementation of this protocol should make sure to not hold the timer's target. This allows the target not to
/// be held longer than it is needed. In other words, it should behave as a "weak timer".
public protocol DrivingTimer {
    
    /// The current timestamp of the timer.
    var timestamp: TimeInterval { get }
    
    /// Invalidates the timer to prevent it from being fired again.
    func invalidate()
    
    /// The timer pause state. When `isPaused` is `true`, the timer should not fire an event. Setting it to `false`
    /// should make the timer be valid again.
    var isPaused: Bool { get set }
    
    /// Creates a timer in a certain mode. The timer should call `action` in main thread every time the timer is fired.
    /// However, it should not hold the `target` object, so as soon as `target` is released, this timer can be stopped
    /// to prevent any retain cycle.
    init(mode: RunLoop.Mode?, target: AnyObject, action: @escaping (TimeInterval) -> Void)
}

#if canImport(UIKit)
/// A timer driven by display link.
///
/// This class fires an event synchronized with the display loop. This prevents unnecessary check of animation status
/// and only update the image bounds to the display refreshing.
public class DisplayTimer: DrivingTimer {
    // Exposed properties
    public var timestamp: TimeInterval { displayLink.timestamp }
    public func invalidate() { displayLink.invalidate() }
    public var isPaused: Bool {
        get { displayLink.isPaused }
        set { displayLink.isPaused = newValue }
    }
    
    // Holder, the underline display link.
    private var displayLink: CADisplayLink!
    private let action: (TimeInterval) -> Void
    private weak var target: AnyObject?

    public required init(mode: RunLoop.Mode? = nil, target: AnyObject, action: @escaping (TimeInterval) -> Void) {
        self.action = action
        self.target = target
        let displayLink = CADisplayLink(target: self, selector: #selector(step))
        displayLink.add(to: .main, forMode: mode ?? .common)
        self.displayLink = displayLink
    }

    @objc private func step(displayLink: CADisplayLink) {
        if target == nil {
            // The original target is already release. No need to hold the display link anymore.
            // This also allows `self` to be released.
            displayLink.invalidate()
        } else {
            action(displayLink.timestamp)
        }
    }
}
#endif

public class NormalTimer: DrivingTimer {
    public var timestamp: TimeInterval { CACurrentMediaTime() }
    public func invalidate() { Task { await timerState.invalidate() } }
    public var isPaused: Bool {
        get {
            get async {
                await timerState.isPaused
            }
        }
        set {
            Task { await timerState.isPaused = newValue }
        }
    }

    private let timerState: TimerState

    public required init(mode: RunLoop.Mode? = nil, target: AnyObject, action: @escaping (TimeInterval) -> Void) {
        self.timerState = TimerState(mode: mode ?? .common, target: target, action: action)
    }
}
