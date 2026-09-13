import SwiftUI

extension Path {
    init(circleAround centre: CGPoint, radius: Double) {
        self.init(ellipseIn: CGRect(x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2))
    }
}
