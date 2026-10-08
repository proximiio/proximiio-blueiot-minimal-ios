//
//  RouteConnector.swift
//  BlueiotMinimal
//
//  A line from the position to the start of the route ahead.
//
//  The route ahead starts at the visitor's projection onto the route,
//  `RouteGuidance.progress.point`. A visitor beside the route, within
//  `offRouteMeters`, otherwise sees a gap between the position marker and the
//  line. The connector is `#3F69FF`, the route's start colour, 6 pt wide with a
//  round cap, and is drawn below the route layer. It is drawn on the visitor's
//  floor only, and not after arrival.
//
//  The map library has no layer for it. The source and the layer are added
//  through `ProximiioMapCanvas.addLayer(_:at:)` on each style load, because a
//  style reload removes every layer the app added.
//
import MapLibre
import ProximiioMap
import UIKit

@MainActor
final class RouteConnector {
    private static let identifier = "app-route-connector"

    private weak var session: ProximiioMapSession?
    private var token: MapCanvasToken?
    private var points: [MapCoordinate] = []

    /// Waits up to 5 s for the map view to create its canvas, then adds the
    /// layer on the current style and on every later style load.
    /// `ProximiioMapSession.onStyleLoaded` returns `nil` while there is no canvas.
    func attach(to session: ProximiioMapSession) async {
        self.session = session
        for _ in 0 ..< 50 where session.canvas == nil {
            try? await Task.sleep(for: .milliseconds(100))
        }
        token = session.onStyleLoaded { [weak self] _, style in
            MainActor.assumeIsolated { self?.install(on: style) }
        }
    }

    /// Redraws the line from the session's guidance, position and shown floor.
    /// Call it when `guidance` or `selectedFloor` changes; the session updates
    /// `guidance` on every fix.
    func update() {
        guard let session else { return }
        let next = Self.points(
            guidance: session.guidance,
            position: session.position,
            shownFloor: session.selectedFloor
        )
        guard next != points else { return }
        points = next
        if let style = session.canvas?.style { draw(on: style) }
    }

    /// The line's two ends, or an empty array for no line.
    ///
    /// Empty without guidance, after arrival, without a split point, without a
    /// position, and while the map shows a floor other than the visitor's. A
    /// position without a floor counts as on the shown floor.
    nonisolated static func points(guidance: RouteGuidance?, position: VenuePosition?, shownFloor: FloorKey) -> [MapCoordinate] {
        guard let guidance, !guidance.hasArrived,
              let start = guidance.progress.point,
              let position,
              position.floor.map({ Int($0.level.rounded()) == Int(shownFloor.level.rounded()) }) ?? true
        else { return [] }
        return [position.coordinate, start]
    }

    private func install(on style: MLNStyle) {
        guard let canvas = session?.canvas else { return }
        if style.source(withIdentifier: Self.identifier) == nil {
            let source = MLNShapeSource(identifier: Self.identifier, shape: nil)
            style.addSource(source)
            let layer = MLNLineStyleLayer(identifier: Self.identifier, source: source)
            layer.lineColor = NSExpression(forConstantValue: UIColor(red: 0x3F / 255, green: 0x69 / 255, blue: 1, alpha: 1))
            layer.lineWidth = NSExpression(forConstantValue: 6)
            layer.lineCap = NSExpression(forConstantValue: "round")
            canvas.addLayer(layer, at: .below(.route))
        }
        draw(on: style)
    }

    private func draw(on style: MLNStyle) {
        guard let source = style.source(withIdentifier: Self.identifier) as? MLNShapeSource else { return }
        guard points.count == 2 else {
            source.shape = nil
            return
        }
        var coordinates = points.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
        source.shape = MLNPolylineFeature(coordinates: &coordinates, count: UInt(coordinates.count))
    }
}
