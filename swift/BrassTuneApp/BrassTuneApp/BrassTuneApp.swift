import SwiftUI

@main
struct BrassTuneApp: App {
    @StateObject private var appModel = AppModel()

    private var effectiveLanguage: AppLanguage {
        AppLanguage.launchOverride ?? appModel.appLanguage
    }

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environmentObject(appModel)
                // Inject the engine so views that show live pitch (the Tuner)
                // observe it directly and re-render per frame, without churning
                // the whole AppModel at frame rate.
                .environmentObject(appModel.audioEngine)
                .environment(\.locale, effectiveLanguage.locale)
                .environment(\.layoutDirection, effectiveLanguage.isRightToLeft ? .rightToLeft : .leftToRight)
                .task {
#if PHYSICAL_INSTRUMENTATION
                    await NativePhysicalAudioSelfTest.runIfRequested(appModel: appModel)
#endif
                }
        }
    }
}

#if PHYSICAL_INSTRUMENTATION
/// Owner-invoked physical instrumentation that bypasses XCTest UI automation.
/// It is inert unless the isolated `.dev` app is launched with the exact
/// `PHYSICAL_AUDIO_SELFTEST` argument. The source is compiled only when the
/// owner adds the `PHYSICAL_INSTRUMENTATION` build condition.
@MainActor
private enum NativePhysicalAudioSelfTest {
    private static var hasStarted = false
    private static let launchArgument = "PHYSICAL_AUDIO_SELFTEST"

    static func runIfRequested(appModel: AppModel) async {
        guard ProcessInfo.processInfo.arguments.contains(launchArgument), !hasStarted else { return }
        hasStarted = true

        var failures: [String] = []
        var tunerStarts = 0
        var scaleStarts = 0
        var metronomeStarts = 0
        var referenceToneStarts = 0
        var droneStarts = 0
        var featureSwitches = 0
        var droppedInputFrames = 0
        var droppedInputFrameEvents: [String] = []
        var scaleCaptureCompletions = 0
        var scaleAcceptedFrames = 0
        var scaleZeroAcceptedFrameCompletions = 0
        var scaleMissingCompletions = 0
        var scaleCaptureEvents: [String] = []
        // 4096 frames at 48 kHz is about 85 ms. Leave enough room for one
        // callback plus route/scheduling variance before evaluating input
        // delivery on a physical device.
        let scaleCaptureDurationMilliseconds = 240

        let recordedConfiguration = ProcessInfo.processInfo.environment["BRASSTUNE_SELFTEST_CONFIGURATION"] ?? "unspecified"
        log("BEGIN configuration=\(recordedConfiguration) bundle=com.aryasalem.BrassTune.dev")

        for cycle in 1...20 {
            if let capture = await runLiveCapture(appModel: appModel, label: "tuner-\(cycle)", failures: &failures) {
                tunerStarts += 1
                droppedInputFrames += capture.droppedInputFrameCount
                if capture.droppedInputFrameCount > 0 {
                    droppedInputFrameEvents.append(
                        "tuner-\(cycle):dropped=\(capture.droppedInputFrameCount),frames=\(capture.frames.count)"
                    )
                }
            }
        }

        for cycle in 1...20 {
            await appModel.startPlayAlong()
            if appModel.playAlongPhase == .running, appModel.audioEngine.recording {
                scaleStarts += 1
                await pause(milliseconds: scaleCaptureDurationMilliseconds)
                let acceptedFrameCount = appModel.audioEngine.acceptedLiveFrameCount
                if let completion = appModel.stopPlayAlong() {
                    recordScaleCapture(
                        await completion.value,
                        label: "scale-\(cycle)",
                        acceptedFrameCount: acceptedFrameCount,
                        droppedInputFrames: &droppedInputFrames,
                        droppedInputFrameEvents: &droppedInputFrameEvents,
                        completions: &scaleCaptureCompletions,
                        acceptedFrames: &scaleAcceptedFrames,
                        zeroAcceptedFrameCompletions: &scaleZeroAcceptedFrameCompletions,
                        events: &scaleCaptureEvents,
                        failures: &failures
                    )
                } else {
                    scaleMissingCompletions += 1
                    failures.append("scale-\(cycle):missing-completion")
                }
            } else {
                failures.append("scale-\(cycle):start")
                appModel.stopPlayAlong()
            }
        }

        appModel.setTempo(300)
        appModel.setMetronomeVisualOnly(false)
        appModel.setMetronomeVolume(0.65)
        for _ in 1...20 {
            appModel.startMetronome()
            metronomeStarts += 1
            await pause(milliseconds: 240)
            appModel.stopMetronome()
        }

        for cycle in 1...20 {
            do {
                try appModel.audioEngine.startTone(frequencyHz: 440, volume: 0.25)
                referenceToneStarts += 1
                await pause(milliseconds: 100)
                appModel.audioEngine.stopTone()
            } catch {
                failures.append("reference-tone-\(cycle):\(String(describing: error))")
                appModel.audioEngine.stopTone()
            }
        }

        for cycle in 1...20 {
            appModel.startDrone()
            if appModel.audioEngine.tonePlaying {
                droneStarts += 1
                await pause(milliseconds: 100)
            } else {
                failures.append("drone-\(cycle):start")
            }
            appModel.stopDrone()
        }

        for round in 1...10 {
            if let capture = await runLiveCapture(appModel: appModel, label: "switch-\(round)-tuner", failures: &failures) {
                droppedInputFrames += capture.droppedInputFrameCount
                if capture.droppedInputFrameCount > 0 {
                    droppedInputFrameEvents.append(
                        "switch-\(round)-tuner:dropped=\(capture.droppedInputFrameCount),frames=\(capture.frames.count)"
                    )
                }
            }
            featureSwitches += 1

            await appModel.startPlayAlong()
            if appModel.playAlongPhase == .running, appModel.audioEngine.recording {
                await pause(milliseconds: scaleCaptureDurationMilliseconds)
            } else {
                failures.append("switch-\(round)-scale:start")
            }
            let acceptedFrameCount = appModel.audioEngine.acceptedLiveFrameCount
            if let completion = appModel.stopPlayAlong() {
                recordScaleCapture(
                    await completion.value,
                    label: "switch-\(round)-scale",
                    acceptedFrameCount: acceptedFrameCount,
                    droppedInputFrames: &droppedInputFrames,
                    droppedInputFrameEvents: &droppedInputFrameEvents,
                    completions: &scaleCaptureCompletions,
                    acceptedFrames: &scaleAcceptedFrames,
                    zeroAcceptedFrameCompletions: &scaleZeroAcceptedFrameCompletions,
                    events: &scaleCaptureEvents,
                    failures: &failures
                )
            } else {
                scaleMissingCompletions += 1
                failures.append("switch-\(round)-scale:missing-completion")
            }
            featureSwitches += 1

            appModel.startMetronome()
            await pause(milliseconds: 120)
            appModel.stopMetronome()
            featureSwitches += 1

            do {
                try appModel.audioEngine.startTone(frequencyHz: 523.251, volume: 0.2)
                await pause(milliseconds: 80)
            } catch {
                failures.append("switch-\(round)-reference:\(String(describing: error))")
            }
            appModel.audioEngine.stopTone()
            featureSwitches += 1

            appModel.startDrone()
            await pause(milliseconds: 80)
            if !appModel.audioEngine.tonePlaying {
                failures.append("switch-\(round)-drone:start")
            }
            appModel.stopDrone()
            featureSwitches += 1
        }

        appModel.stopFeatureAudio()
        appModel.audioEngine.stopAndResetAudioEngine()

        let result: [String: Any] = [
            "tunerStarts": tunerStarts,
            "scaleStarts": scaleStarts,
            "metronomeStarts": metronomeStarts,
            "referenceToneStarts": referenceToneStarts,
            "droneStarts": droneStarts,
            "featureSwitches": featureSwitches,
            "droppedInputFrames": droppedInputFrames,
            "droppedInputFrameEvents": droppedInputFrameEvents,
            "scaleCaptureCompletions": scaleCaptureCompletions,
            "scaleAcceptedFrames": scaleAcceptedFrames,
            "scaleZeroAcceptedFrameCompletions": scaleZeroAcceptedFrameCompletions,
            "scaleMissingCompletions": scaleMissingCompletions,
            "scaleCaptureEvents": scaleCaptureEvents,
            "failureCount": failures.count,
            "failures": failures
        ]
        if let data = try? JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]),
           let json = String(data: data, encoding: .utf8) {
            log("RESULT \(json)")
        } else {
            log("RESULT encoding-failed failureCount=\(failures.count)")
        }
        log("END")
    }

    private static func runLiveCapture(
        appModel: AppModel,
        label: String,
        failures: inout [String]
    ) async -> NativeLiveCapture? {
        do {
            let started = try await appModel.audioEngine.startLiveRecording(
                instrumentId: appModel.selectedInstrumentId,
                referencePitchHz: appModel.referencePitchHz
            )
            guard started else {
                failures.append("\(label):permission-or-concurrent-start")
                return nil
            }
            await pause(milliseconds: 120)
            return await appModel.audioEngine.stopLiveRecording().value
        } catch {
            failures.append("\(label):\(String(describing: error))")
            appModel.audioEngine.stopAndResetAudioEngine()
            return nil
        }
    }

    private static func pause(milliseconds: Int) async {
        try? await Task.sleep(for: .milliseconds(milliseconds))
    }

    private static func recordDroppedInputFrames(
        _ capture: NativeLiveCapture,
        label: String,
        total: inout Int,
        events: inout [String]
    ) {
        total += capture.droppedInputFrameCount
        guard capture.droppedInputFrameCount > 0 else { return }
        events.append(
            "\(label):dropped=\(capture.droppedInputFrameCount),frames=\(capture.frames.count)"
        )
    }

    private static func recordScaleCapture(
        _ capture: NativeLiveCapture,
        label: String,
        acceptedFrameCount: Int,
        droppedInputFrames: inout Int,
        droppedInputFrameEvents: inout [String],
        completions: inout Int,
        acceptedFrames: inout Int,
        zeroAcceptedFrameCompletions: inout Int,
        events: inout [String],
        failures: inout [String]
    ) {
        completions += 1
        acceptedFrames += acceptedFrameCount
        events.append(
            "\(label):accepted=\(acceptedFrameCount),dropped=\(capture.droppedInputFrameCount)"
        )
        if acceptedFrameCount == 0 {
            zeroAcceptedFrameCompletions += 1
            failures.append("\(label):zero-accepted-frames")
        }
        recordDroppedInputFrames(
            capture,
            label: label,
            total: &droppedInputFrames,
            events: &droppedInputFrameEvents
        )
    }

    private static func log(_ message: String) {
        print("BRASSTUNE_PHYSICAL_SELFTEST \(message)")
    }
}
#endif
