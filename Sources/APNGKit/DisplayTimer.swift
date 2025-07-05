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
    private let action: @Sendable (TimeInterval) -> Void
    private weak var target: AnyObject?

    init(mode: RunLoop.Mode, target: AnyObject, action: @escaping @Sendable (TimeInterval) -> Void) {
        self.mode = mode
        self.target = target
        self.action = action
        // actor 初始化时不能直接调用隔离方法，需用同步静态方法
        timer = TimerState.createTimerStatic(
            mode: mode,
            target: target,
            action: action,
            timerState: nil // 初始化时还没有 self
        )
    }

    var isPaused: Bool {
        get { _isPaused }
        set {
            if newValue {
                timer?.invalidate()
                _isPaused = true
            } else {
                if timer == nil || !(timer?.isValid ?? false) {
                    // actor 内部可直接调用
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

    // actor 内部可安全调用
    private func createTimer() -> Timer {
        TimerState.createTimerStatic(
            mode: mode,
            target: target,
            action: action,
            timerState: self
        )
    }

    // 静态同步方法，供 actor 初始化时调用
    private static func createTimerStatic(
        mode: RunLoop.Mode,
        target: AnyObject?,
        action: @Sendable (TimeInterval) -> Void,
        timerState: TimerState?
    ) -> Timer {
        let refreshRate = 60.0
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

        let weakTarget = target

        let timer = Timer(timeInterval: interval, repeats: true) { [weak timerState] t in
            // 只用初始化时捕获的 weakTarget
            guard let _ = weakTarget else {
                // 不能直接访问 timerState?.timer，直接使当前 timer 失效
                t.invalidate()
                return
            }
            Task { @MainActor in
                action(CACurrentMediaTime())
            }
        }
        RunLoop.main.add(timer, forMode: mode)
        return timer
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
    init(mode: RunLoop.Mode?, target: AnyObject, action: @Sendable @escaping (TimeInterval) -> Void)
}

public class NormalTimer: DrivingTimer {
    public var timestamp: TimeInterval { CACurrentMediaTime() }
    public func invalidate() { Task { await timerState.invalidate() } }

    // 兼容 DrivingTimer 协议的同步 isPaused 属性（仅用于协议要求，不建议直接用）
    public var isPaused: Bool {
        get {
            let group = DispatchGroup()
            group.enter()
            var value = false
            Task {
                value = await timerState.isPaused
                group.leave()
            }
            group.wait()
            return value
        }
        set {
            // 通过异步 Task 发送到 actor 内部，避免直接同步访问 actor 属性
            Task {
                await timerState.setPausedInternal(newValue)
            }
        }
    }

    // 推荐异步获取/设置
    public var isPausedAsync: Bool {
        get async {
            await timerState.isPaused
        }
    }
    public func setPaused(_ value: Bool) {
        Task { await timerState.setPausedInternal(value) }
    }

    private let timerState: TimerState

    public required init(mode: RunLoop.Mode? = nil, target: AnyObject, action: @Sendable @escaping (TimeInterval) -> Void) {
        timerState = TimerState(mode: mode ?? .common, target: target, action: action)
    }
}

// 给 TimerState 增加 actor 内部的安全 set 方法
extension TimerState {
    nonisolated func setPausedInternal(_ value: Bool) async {
        await self.setPaused(value)
    }
    func setPaused(_ value: Bool) {
        self.isPaused = value
    }
}
