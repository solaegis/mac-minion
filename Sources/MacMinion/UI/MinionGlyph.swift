import AppKit

/// The app icon's minion (the eye and the grin) as a template image for the menu bar.
/// The shapes follow `Icon/AppIcon.icon/Assets/front.svg` and `back.svg`, in their 1024 pt space.
enum MinionGlyph {
    static let menuBar: NSImage = {
        let size = NSSize(width: 18, height: 18)  // grid: ok the menu bar's standard template size
        let image = NSImage(size: size, flipped: true) { _ in
            // The artwork spans x 212...812 and y 200...936; fit its height in 16 pt, centered.
            let scale = 16.0 / 736.0
            let place = AffineTransform(translationByX: size.width / 2, byY: size.height / 2)
            var transform = AffineTransform(scale: scale)
            transform.append(place)
            transform.prepend(AffineTransform(translationByX: -512, byY: -568))

            for path in [eye(), grin()] {
                path.transform(using: transform)
                path.fill()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "MacMinion"
        return image
    }()

    /// The eye: an ellipse with the pupil cut out and a glint inside it, tilted 8°.
    private static func eye() -> NSBezierPath {
        let path = NSBezierPath()
        path.windingRule = .evenOdd
        path.appendOval(in: NSRect(x: 212, y: 215, width: 600, height: 430))  // grid: ok artwork coordinates from front.svg
        path.appendOval(in: NSRect(x: 455, y: 325, width: 210, height: 210))  // grid: ok artwork coordinates from front.svg
        path.appendOval(in: NSRect(x: 530, y: 361, width: 68, height: 68))
        var tilt = AffineTransform(translationByX: -512, byY: -430)
        tilt.append(AffineTransform(rotationByDegrees: -8))
        tilt.append(AffineTransform(translationByX: 512, byY: 430))
        path.transform(using: tilt)
        return path
    }

    /// The grin: a thick crescent with one fang hanging from its left side.
    private static func grin() -> NSBezierPath {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: 262, y: 700))
        path.curve(to: NSPoint(x: 762, y: 772), controlPoint1: NSPoint(x: 330, y: 790), controlPoint2: NSPoint(x: 560, y: 826))
        path.curve(to: NSPoint(x: 782, y: 816), controlPoint1: NSPoint(x: 796, y: 763), controlPoint2: NSPoint(x: 812, y: 800))
        path.curve(to: NSPoint(x: 222, y: 744), controlPoint1: NSPoint(x: 560, y: 916), controlPoint2: NSPoint(x: 300, y: 876))
        path.curve(to: NSPoint(x: 262, y: 700), controlPoint1: NSPoint(x: 204, y: 712), controlPoint2: NSPoint(x: 244, y: 678))
        path.close()
        path.move(to: NSPoint(x: 330, y: 772))
        path.line(to: NSPoint(x: 476, y: 818))
        path.line(to: NSPoint(x: 404, y: 936))
        path.close()
        return path
    }
}
