//
//  DarockBrowserApp.swift
//  WatchBrowser Watch App
//
//  Created by Windows MEMZ on 2023/2/6.
//

import OSLog
import Combine
import SwiftUI
import Intents
import WatchKit
import NotifKit
import DarockUI
import SDWebImage
import RadarKitCore
import AVFoundation
import SwiftyStoreKit
import DarockFoundation
import SDWebImageSVGCoder
import SDWebImagePDFCoder
import SDWebImageWebPCoder
import AuthenticationServices
@_spi(_internal) import CorvusKit

#if BETA
let isAppBetaBuild = true
#else
let isAppBetaBuild = false
#endif

let setMainSceneHideStatusBarSubject = PassthroughSubject<Bool, Never>()
let appBecomeInactiveSubject = PassthroughSubject<Void, Never>()

var pTapToRadarAlertContent = ""
var pTapToRadarAttachText = ""
var pIsTapToRadarAlertPresented = false

#if !targetEnvironment(simulator)
var globalHapticEngine: CHHapticEngine?
#endif

@main
struct DarockBrowserApp: App {
    @WKApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.scenePhase) var scenePhase
    @AppStorage("ShouldTipNewFeatures9") var shouldTipNewFeatures = true
    @AppStorage("ShouldAskForBrowsingPreference") var shouldAskForBrowsingPreference: Bool = if #available(watchOS 10.0, *) { true } else { false }
    @AppStorage("UserPasscodeEncrypted") var userPasscodeEncrypted = ""
    @AppStorage("UsePasscodeForLockDarockBrowser") var usePasscodeForLockDarockBrowser = false
    @AppStorage("IsThisClusterInstalled") var isThisClusterInstalled = false
    @AppStorage("IsProPurchased") var isProPurchased = false
    @AppStorage("ABIsReduceBrightness") var isReduceBrightness = false
    @AppStorage("IsBrowserProAdFirstTipped") var isBrowserProAdFirstTipped = false
    @AppStorage("DBIsAutoAppearence") var isAutoAppearence = false
    @AppStorage("DBAutoAppearenceOptionEnableForReduceBrightness") var autoAppearenceOptionEnableForReduceBrightness = false
    @AppStorage("PRSubscriptionExpirationDate") var subscriptionExpirationDate = 0.0
    @AppStorage("PRIsPrivateRelayEnabled") var isPrivateRelayEnabled = false
    @State var isBrowserLocked = true
    @State var passcodeInputCache = ""
    @State var tapToRadarAlertContent = ""
    @State var isTapToRadarAlertPresented = false
    @State var isClusterInstalledTipPresented = false
    @State var isBrowserProAdPresented = false
    @State var isQuickAvoidanceShowingEmpty = false
    @State var isRemoteStatusBarHidden = false
    var body: some Scene {
        WindowGroup {
            ZStack {
                if !isBrowserLocked {
                    DoubleTapActionButton(forType: .global) {
                        isQuickAvoidanceShowingEmpty = true
                    }
                }
                ContentView()
                    .blur(radius: isBrowserLocked && !userPasscodeEncrypted.isEmpty && usePasscodeForLockDarockBrowser ? 12 : 0)
                    .allowsHitTesting(!(isBrowserLocked && !userPasscodeEncrypted.isEmpty && usePasscodeForLockDarockBrowser))
                    .sheet(isPresented: $shouldTipNewFeatures, content: { NewFeaturesView() })
                    .sheet(isPresented: $shouldAskForBrowsingPreference) {
                        if #available(watchOS 10.0, *) {
                            NavigationStack {
                                SettingsView.BrowsingPreferenceSettingsView(isShowingInStartup: true)
                            }
                        }
                    }
                    .sheet(isPresented: $isClusterInstalledTipPresented, content: { ClusterTipView() })
                    .sheet(isPresented: $isBrowserProAdPresented, onDismiss: { isBrowserProAdFirstTipped = true }) {
                        NavigationStack {
                            ProPurchaseView()
                        }
                    }
                    .onAppear {
                        if userPasscodeEncrypted.isEmpty || !usePasscodeForLockDarockBrowser {
                            isBrowserLocked = false
                        }
                        if !isBrowserProAdFirstTipped {
                            isBrowserProAdPresented = true
                        }
                    }
                if isBrowserLocked && !userPasscodeEncrypted.isEmpty && usePasscodeForLockDarockBrowser {
                    PasswordInputView(text: $passcodeInputCache, placeholder: "输入密码", hideCancelButton: true, dismissAfterComplete: false) { pwd in
                        if pwd.md5 == userPasscodeEncrypted {
                            isBrowserLocked = false
                        } else {
                            tipWithText("密码错误", symbol: "xmark.circle.fill")
                        }
                        passcodeInputCache = ""
                    }
                }
                if isQuickAvoidanceShowingEmpty {
                    Color.black
                        .ignoresSafeArea()
                        .onTapGesture(count: 3) {
                            isQuickAvoidanceShowingEmpty = false
                        }
                }
            }
            .brightnessReducable()
            ._statusBarHidden(
                (isBrowserLocked && !userPasscodeEncrypted.isEmpty && usePasscodeForLockDarockBrowser)
                || isQuickAvoidanceShowingEmpty
                || isRemoteStatusBarHidden
            )
            .alert("Runtime Error", isPresented: $isTapToRadarAlertPresented, actions: {
                Button(role: .cancel, action: {
                    
                }, label: {
                    Text(verbatim: "Cancel")
                })
                Button(action: {
                    WKExtension.shared().openSystemURL(URL(string: "https://darock.top/internal/tap-to-radar/new?ProductName=Darock Browser&Title=Internal autoattachd Error&Description=\(pTapToRadarAttachText)")!)
                }, label: {
                    Text(verbatim: "Tap-to-Radar")
                })
            }, message: {
                Text(tapToRadarAlertContent)
            })
            .onAppear {
                Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
                    tapToRadarAlertContent = pTapToRadarAlertContent
                    if _slowPath(pIsTapToRadarAlertPresented) {
                        isTapToRadarAlertPresented = true
                        pIsTapToRadarAlertPresented = false
                    }
                }
            }
            .onReceive(setMainSceneHideStatusBarSubject) { isHidden in
                isRemoteStatusBarHidden = isHidden
            }
            .onOpenURL { url in
                let urlString = url.absoluteString
                if urlString.hasPrefix("wget://") {
                    let splited = urlString.split(separator: "/", maxSplits: 2).map { String($0) }
                    // rdar://FB268002075005
                    if isProPurchased {
                        // switches action string
                        switch splited[1] {
                        case "openURL" where splited[2].isURL():
                            createNewTabSubject.send(.init(url: splited[2]))
                        default: break
                        }
                    }
                }
            }
        }
        .onChange(of: scenePhase) { value in
            switch value {
            case .background:
                if !userPasscodeEncrypted.isEmpty && usePasscodeForLockDarockBrowser {
                    isBrowserLocked = true
                }
            case .inactive:
                appBecomeInactiveSubject.send(())
                if isAutoAppearence {
                    AppearenceManager.shared.updateAll()
                }
            case .active:
                initHapticEngine()
                
                if (UserDefaults(suiteName: "group.darockst")?.bool(forKey: "DCIsClusterInstalled") ?? false) && !isThisClusterInstalled {
                    isThisClusterInstalled = true
                    isClusterInstalledTipPresented = true
                }
                
                if isAutoAppearence && autoAppearenceOptionEnableForReduceBrightness {
                    isReduceBrightness = AppearenceManager.shared.currentAppearence == .dark
                    AppearenceManager.shared.updateAll {
                        isReduceBrightness = AppearenceManager.shared.currentAppearence == .dark
                    }
                }
                
                if isPrivateRelayEnabled {
                    if subscriptionExpirationDate < Date.now.timeIntervalSince1970 {
                        let appleValidator = AppleReceiptValidator(service: .production, sharedSecret: "e6f95fe6efbf467084bc17ba1113e2fa")
                        SwiftyStoreKit.verifyReceipt(using: appleValidator, forceRefresh: true) { result in
                            switch result {
                            case .success(let receipt):
                                let productId = "private_relay"
                                let purchaseResult = SwiftyStoreKit.verifySubscription(
                                    ofType: .autoRenewable,
                                    productId: productId,
                                    inReceipt: receipt)
                                switch purchaseResult {
                                case .purchased(let expiryDate, _):
                                    subscriptionExpirationDate = expiryDate.timeIntervalSince1970
                                default:
                                    isPrivateRelayEnabled = false
                                }
                            case .error(let error):
                                print("Receipt verification failed: \(error)")
                            }
                        }
                    }
                }
            @unknown default:
                break
            }
        }
    }
}

class AppDelegate: NSObject, WKApplicationDelegate {
    @AppStorage("WebSearch") var webSearch = "必应"
    @AppStorage("IsProPurchased") var isProPurchased = false
    @AppStorage("NFIsNotificationsFromDarockAllowed") var isNotificationsFromDarockAllowed = true
    
    func applicationDidFinishLaunching() {
        SwiftyStoreKit.completeTransactions(atomically: true) { purchases in
            for purchase in purchases {
                switch purchase.transaction.transactionState {
                case .purchased, .restored:
                    if purchase.needsFinishTransaction {
                        SwiftyStoreKit.finishTransaction(purchase.transaction)
                    }
                case .failed, .purchasing, .deferred:
                    break
                @unknown default:
                    break
                }
            }
        }
        
        SDImageCodersManager.shared.addCoder(SDImageWebPCoder.shared)
        SDImageCodersManager.shared.addCoder(SDImageSVGCoder.shared)
        SDImageCodersManager.shared.addCoder(SDImagePDFCoder.shared)
        
        _ = AppearenceManager.shared
        _ = CachedLocationManager.shared
        
        Task {
            do {
                let checker = COKChecker(caller: .darock)
                let updater = COKUpdater(caller: .darock)
                try await checker.appStartupAutoCheck()
                let manager = RKCFeedbackManager(projectName: "Darock Browser")
                let feedbackIds = UserDefaults.standard.stringArray(forKey: "RadarFBIDs") ?? [String]()
                for id in feedbackIds {
                    if let feedback = await manager.getFeedback(byId: id) {
                        let formatter = RKCFileFormatter(for: feedback)
                        if let lastReply = formatter.replies().last {
                            if _slowPath(lastReply.isInternalHidden),
                               let state = lastReply.UpdateCorvusState,
                               state == "true" {
                                try await updater.updateCOStatus(true)
                                checker._applyWatermarkNow()
                                checker.cachedCheckStatus = true
                                break
                            }
                        }
                    }
                }
            } catch {
                print(error)
            }
        }
        
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { isGrand, _ in
            DispatchQueue.main.async {
                if isGrand {
                    WKApplication.shared().registerForRemoteNotifications()
                }
            }
        }
        
        requestAPI("/analyze/add/DBStatsAppStartupCount") { _, _ in }
    }
    
    func didRegisterForRemoteNotifications(withDeviceToken deviceToken: Data) {
        let tokenString = deviceToken.hexEncodedString()
        debugPrint(tokenString)
        UserDefaults.standard.set(tokenString, forKey: "UserNotificationToken")
        requestAPI("/apns/devtoken/\(isNotificationsFromDarockAllowed ? "add" : "remove")/DarockBrowser_Promotion/0/\(tokenString)") { _, _ in }
    }
    
    func handle(_ userActivity: NSUserActivity) {
        if #available(watchOS 10.0, *) {
            if isProPurchased {
                if userActivity.activityType == "SearchWidgets" {
                    WKExtension.shared().visibleInterfaceController?.presentTextInputController(
                        withSuggestions: nil,
                        allowedInputMode: .allowEmoji
                    ) { result in
                        if let _texts = result as? [String], let text = _texts.first {
                            startSearch(text, with: self.webSearch)
                        }
                    }
                }
            }
        }
    }
}

public func tipWithText(_ text: LocalizedStringResource, symbol: String = "", time: Double = 3.0) {
    NKTipper.scaleStyle.present(text: text, symbol: symbol, duration: time)
    if symbol == "xmark.circle.fill" {
        playHaptic(from: Bundle.main.url(forResource: "Failure", withExtension: "ahap")!)
    } else {
        playHaptic(from: Bundle.main.url(forResource: "Success", withExtension: "ahap")!)
    }
}
@_disfavoredOverload
public func tipWithText(_ text: String, symbol: String = "", time: Double = 3.0) {
    NKTipper.scaleStyle.present(text: text, symbol: symbol, duration: time)
    if symbol == "xmark.circle.fill" {
        playHaptic(from: Bundle.main.url(forResource: "Failure", withExtension: "ahap")!)
    } else {
        playHaptic(from: Bundle.main.url(forResource: "Success", withExtension: "ahap")!)
    }
}
public func globalErrorHandler(_ error: Error, file: StaticString = #fileID, function: StaticString = #function, line: Int = #line) {
    os_log(.error, "\(error)")
    do {
        if !FileManager.default.fileExists(atPath: NSHomeDirectory() + "/Documents/SwiftErrorLogs") {
            try FileManager.default.createDirectory(atPath: NSHomeDirectory() + "/Documents/SwiftErrorLogs", withIntermediateDirectories: true)
        }
        try """
        Error：\(error.localizedDescription)
        Location：\(file):\(line) - \(function)
        """.write(
            toFile: NSHomeDirectory() + "/Documents/SwiftErrorLogs/\(Date().timeIntervalSince1970).txt",
            atomically: true,
            encoding: .utf8
        )
    } catch {
        print("Error in globalErrorHandler: \(error)")
    }
    if UserDefaults(suiteName: "group.darockst")!.bool(forKey: "DarockInternal") {
        pTapToRadarAlertContent = "Swift has caught an internal error.\nPlease help us make Darock Browser better by logging a bug. Thanks. (\(file):\(line) - \(function))"
        pTapToRadarAttachText = "Autoattachd DarockBrowser(\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as! String)). At \(file):\(line) - \(function). LocdStr: \(error.localizedDescription) Add more infomation here: "
            .replacingOccurrences(of: "\n", with: "{LineBreak}")
            .replacingOccurrences(of: "/", with: "{slash}")
            .replacingOccurrences(of: "?", with: "{questionmark}")
            .replacingOccurrences(of: "=", with: "{equal}")
            .replacingOccurrences(of: "&", with: "{and}")
        pIsTapToRadarAlertPresented = true
    }
}
func resetGlobalAudioLooper() {
    if let currentLooper = globalAudioLooper {
        NotificationCenter.default.removeObserver(currentLooper)
        globalAudioLooper = nil
    }
    globalAudioLooper = NotificationCenter.default.addObserver(
        forName: AVPlayerItem.didPlayToEndTimeNotification,
        object: globalAudioPlayer.currentItem,
        queue: .main) { _ in
            let playbackBehavior = PlaybackBehavior.init(rawValue: UserDefaults.standard.string(forKey: "MPPlaybackBehavior") ?? "pause") ?? .pause
            if playbackBehavior == .singleLoop {
                globalAudioPlayer.seek(to: .zero)
                globalAudioPlayer.play()
            } else if playbackBehavior == .listLoop {
                if let currentContent = getCurrentPlaylistContents() {
                    for i in 0..<currentContent.count {
                        if let currentUrl = (globalAudioPlayer.currentItem?.asset as? AVURLAsset)?.url {
                            if currentUrl.absoluteString == currentContent[i].replacingOccurrences(
                                of: "%DownloadedContent@=", with: "file://\(NSHomeDirectory())/Documents/DownloadedAudios/"
                            ) {
                                if let nextItem = currentContent[from: i &+ 1] {
                                    playAudio(url: nextItem, presentController: false)
                                } else if let firstItem = currentContent.first {
                                    playAudio(url: firstItem, presentController: false)
                                }
                                break
                            }
                        }
                    }
                } else {
                    globalAudioPlayer.seek(to: .zero)
                    globalAudioPlayer.play()
                }
            }
    }
}

func initHapticEngine() {
    #if !targetEnvironment(simulator)
    dlopen("/System/Library/Frameworks/CoreHaptics.framework/CoreHaptics", RTLD_NOW)
    do {
        globalHapticEngine = try CHHapticEngine(audioSession: nil)
        try globalHapticEngine?.start()
    } catch {
        print("创建引擎时出现错误： \(error.localizedDescription)")
    }
    #endif
}
func playHaptic(sharpness: Float, intensity: Float) {
    #if !targetEnvironment(simulator)
    var events = [CHHapticEvent]()
    let intensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity)
    let sharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness)
    let event = CHHapticEvent(eventType: .hapticTransient, parameters: [intensity, sharpness], relativeTime: 0)
    events.append(event)
    do {
        let pattern = try CHHapticPattern(events: events, parameters: [])
        let player = try globalHapticEngine?.createPlayer(with: pattern)
        try player?.start(atTime: 0)
    } catch {
        print("Failed to play pattern: \(error.localizedDescription).")
    }
    #endif
}
func playHaptic(from url: URL) {
    #if !targetEnvironment(simulator)
    do {
        try globalHapticEngine?.playPattern(from: url)
    } catch {
        print("Failed to play pattern: \(error.localizedDescription).")
    }
    #endif
}
