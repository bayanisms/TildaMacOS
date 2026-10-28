import AppKit
import QuartzCore

final class DropdownContentView: NSView {
    private let content: NSView
    private var generation = 0
    private let animationKey = "dropdown"
    var isAnimating: Bool { content.layer?.animation(forKey: animationKey) != nil }
    override var isFlipped: Bool { true }

    init(content: NSView) {
        self.content = content
        super.init(frame: content.frame)
        wantsLayer = true
        layer?.masksToBounds = true
        content.wantsLayer = true
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: leadingAnchor),
            content.trailingAnchor.constraint(equalTo: trailingAnchor),
            content.topAnchor.constraint(equalTo: topAnchor),
            content.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setRevealed(_ revealed: Bool, animated: Bool, completion: @escaping () -> Void = {}) {
        generation += 1
        let currentGeneration = generation
        layoutSubtreeIfNeeded()
        guard let layer = content.layer else { completion(); return }
        let from = layer.presentation()?.transform.m42 ?? layer.transform.m42
        let to = revealed ? 0 : -bounds.height
        layer.removeAnimation(forKey: animationKey)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.transform = CATransform3DMakeTranslation(0, to, 0)
        if animated && abs(from - to) > 0.5 {
            let animation = CABasicAnimation(keyPath: "transform.translation.y")
            animation.fromValue = from
            animation.toValue = to
            animation.duration = max(0.08, (revealed ? 0.26 : 0.22) * min(1, abs(from - to) / max(1, bounds.height)))
            animation.timingFunction = CAMediaTimingFunction(name: revealed ? .easeOut : .easeIn)
            CATransaction.setCompletionBlock { [weak self] in
                guard let self, self.generation == currentGeneration else { return }
                completion()
            }
            layer.add(animation, forKey: animationKey)
            CATransaction.commit()
        } else {
            CATransaction.commit()
            completion()
        }
    }
}
