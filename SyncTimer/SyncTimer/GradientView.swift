import UIKit

@IBDesignable
class GradientView: UIView {
    // MARK: – IBInspectable properties
    @IBInspectable var startColor:   UIColor = .white { didSet { updateColors() } }
    @IBInspectable var endColor:     UIColor = .black { didSet { updateColors() } }
    @IBInspectable var startPointX:  CGFloat = 0 { didSet { updatePoints() } }
    @IBInspectable var startPointY:  CGFloat = 0 { didSet { updatePoints() } }
    @IBInspectable var endPointX:    CGFloat = 1 { didSet { updatePoints() } }
    @IBInspectable var endPointY:    CGFloat = 1 { didSet { updatePoints() } }

    // Make the layer into a gradient
    override class var layerClass: AnyClass { CAGradientLayer.self }

    private var gradientLayer: CAGradientLayer {
        layer as! CAGradientLayer
    }

    private func updateColors() {
        gradientLayer.colors = [ startColor.cgColor, endColor.cgColor ]
    }
    private func updatePoints() {
        gradientLayer.startPoint = CGPoint(x: startPointX, y: startPointY)
        gradientLayer.endPoint   = CGPoint(x: endPointX,   y: endPointY)
    }

    // Ensure initial values take effect when loaded from IB/storyboard
    override func awakeFromNib() {
        super.awakeFromNib()
        updateColors()
        updatePoints()
    }
}
