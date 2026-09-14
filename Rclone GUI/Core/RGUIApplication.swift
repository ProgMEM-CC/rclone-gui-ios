//
//  RGUIApplication.swift
//  Rclone GUI
//
//  UIApplication subclass registered via NSPrincipalClass in Info.plist.
//
//  Pourquoi : le monitoring global d'activité utilisateur ne doit PAS passer
//  par un UIGestureRecognizer ajouté sur chaque UIWindow. Un recognizer au
//  niveau window participe à l'arbitrage de gestures pour chaque contact
//  écran — y compris à l'intérieur des présentations système (document
//  picker, alertes, sheets). Sur iOS 18.0, cette ingérence rend le document
//  picker inutilisable (fichiers non sélectionnables) et les boutons des
//  sheets inertes.
//
//  sendEvent() observe les events en pure lecture : il est appelé avant tout
//  dispatch, ne consomme rien, ne crée aucun gesture recognizer et ne touche
//  donc à aucun arbitrage. C'est la voie officielle pour le « global touch
//  monitoring » dans une app sans AppDelegate custom.
//

#if os(iOS)
import UIKit

final class RGUIApplication: UIApplication {
    static let didReceiveUserTouchNotification = Notification.Name("RGUIApplication.didReceiveUserTouch")

    /// Set par UserActivityMonitor.start() — évite de poster des notifications
    /// pour rien quand personne n'écoute (ex. tests unitaires).
    /// Accès main-thread uniquement (sendEvent + boot), d'où nonisolated(unsafe).
    private nonisolated(unsafe) static var isObserving = false

    static func beginObservingTouches() {
        isObserving = true
    }

    override func sendEvent(_ event: UIEvent) {
        super.sendEvent(event)

        guard event.type == .touches, Self.isObserving else { return }
        guard let touches = event.allTouches, touches.contains(where: { $0.phase != .cancelled }) else { return }

        // Un seul post par batch d'events suffit — l'horodatage d'activité
        // est le même quel que soit le touch.
        NotificationCenter.default.post(name: Self.didReceiveUserTouchNotification, object: self)
    }
}
#endif
