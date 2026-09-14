//
//  UserActivityMonitor.swift
//  Rclone GUI — Services
//
//  Détecte l'interaction utilisateur (taps, scrolls, gestures) sur toutes les
//  windows actives. Quand l'utilisateur navigue activement (= a interagi
//  dans les 3 dernières secondes), `isUserActive` passe à true et notifie
//  via `userActivityDidChange`. TransferQueue s'y abonne pour throttler la
//  bande passante rclone et libérer du CPU/network pour le UI.
//
//  Implémentation : RGUIApplication (UIApplication subclass, NSPrincipalClass)
//  observe chaque UIEvent tactile dans sendEvent() et poste
//  didReceiveUserTouchNotification. C'est de la pure observation : aucun
//  gesture recognizer n'est créé, donc aucun arbitrage de gestures n'est
//  perturbé. (L'ancienne approche — un recognizer .failed attaché à chaque
//  UIWindow — bloquait la sélection de fichiers dans le document picker et
//  les taps dans les sheets sur iOS 18.0.)
//

#if os(iOS)
import Foundation
import UIKit

extension Notification.Name {
    public static let userActivityDidChange = Notification.Name("rcloneGUI.userActivityDidChange")
}

@MainActor
public final class UserActivityMonitor {
    public static let shared = UserActivityMonitor()
    private init() {}

    /// Seuil d'inactivité au-delà duquel on considère l'utilisateur comme
    /// inactif et où la pleine vitesse de transfert est restaurée. 3 s :
    /// tout contact écran (tap, scroll, drag, swipe) compte et garde le
    /// throttle ; touchesMoved/touchesEnded rafraîchissent l'horodatage
    /// même pendant un long geste, donc la pleine vitesse ne revient qu'à
    /// 3 s du DERNIER contact, pas du début du geste.
    private static let inactivityThreshold: TimeInterval = 3

    private var lastActivity: Date = .distantPast
    private var observerTask: Task<Void, Never>?
    private var touchObserver: NSObjectProtocol?
    private var didStart = false

    /// True si l'utilisateur a interagi dans les `inactivityThreshold` dernières
    /// secondes. Surveille via `Notification.Name.userActivityDidChange`.
    public private(set) var isUserActive: Bool = false {
        didSet {
            guard oldValue != isUserActive else { return }
            NotificationCenter.default.post(
                name: .userActivityDidChange,
                object: nil,
                userInfo: ["isActive": isUserActive]
            )
        }
    }

    /// Démarre la détection. Idempotent — appel multiple OK. À appeler au
    /// boot de l'app. sendEvent() poste sur le main thread ; l'observer
    /// (`queue: .main`) fait juste un hop MainActor avant de l'horodater.
    public func start() {
        guard !didStart else { return }
        didStart = true
        RGUIApplication.beginObservingTouches()
        touchObserver = NotificationCenter.default.addObserver(
            forName: RGUIApplication.didReceiveUserTouchNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.userDidInteract()
            }
        }
        startInactivityObserver()
    }

    private func userDidInteract() {
        lastActivity = .now
        if !isUserActive {
            isUserActive = true
        }
    }

    private func startInactivityObserver() {
        observerTask?.cancel()
        observerTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self else { return }
                if self.isUserActive,
                   Date().timeIntervalSince(self.lastActivity) > Self.inactivityThreshold {
                    self.isUserActive = false
                }
            }
        }
    }
}

#elseif os(macOS)
import Foundation
import AppKit

extension Notification.Name {
    public static let userActivityDidChange = Notification.Name("rcloneGUI.userActivityDidChange")
}

@MainActor
public final class UserActivityMonitor {
    public static let shared = UserActivityMonitor()
    private init() {}

    private static let inactivityThreshold: TimeInterval = 3

    private var lastActivity: Date = .distantPast
    private var observerTask: Task<Void, Never>?
    private var eventMonitor: Any?
    private var didStart = false

    public private(set) var isUserActive: Bool = false {
        didSet {
            guard oldValue != isUserActive else { return }
            NotificationCenter.default.post(
                name: .userActivityDidChange,
                object: nil,
                userInfo: ["isActive": isUserActive]
            )
        }
    }

    /// Démarre la détection via un moniteur d'événements local AppKit : clics,
    /// drags, scroll et frappes clavier dans les fenêtres de l'app comptent
    /// comme interaction. On retourne l'event sans le consommer pour ne pas
    /// perturber l'UI. (On omet `.mouseMoved` pour ne pas throttler sur un
    /// simple survol/dérive de souris au repos.)
    public func start() {
        guard !didStart else { return }
        didStart = true
        let mask: NSEvent.EventTypeMask = [
            .leftMouseDown, .leftMouseDragged, .rightMouseDown,
            .scrollWheel, .keyDown, .flagsChanged,
        ]
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            Task { @MainActor [weak self] in self?.userDidInteract() }
            return event
        }
        startInactivityObserver()
    }

    private func userDidInteract() {
        lastActivity = .now
        if !isUserActive { isUserActive = true }
    }

    private func startInactivityObserver() {
        observerTask?.cancel()
        observerTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self else { return }
                if self.isUserActive,
                   Date().timeIntervalSince(self.lastActivity) > Self.inactivityThreshold {
                    self.isUserActive = false
                }
            }
        }
    }
}
#else
import Foundation

@MainActor
public final class UserActivityMonitor {
    public static let shared = UserActivityMonitor()
    private init() {}
    public var isUserActive: Bool { false }
    public func start() {}
}

extension Notification.Name {
    public static let userActivityDidChange = Notification.Name("rcloneGUI.userActivityDidChange")
}
#endif
