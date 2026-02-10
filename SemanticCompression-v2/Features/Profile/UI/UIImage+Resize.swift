import UIKit

extension UIImage {

    func resizedSquare(to size: CGFloat = 256) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))

        return renderer.image { _ in
            self.draw(in: CGRect(x: 0, y: 0, width: size, height: size))
        }
    }
}
