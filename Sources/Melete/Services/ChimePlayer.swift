import AppKit

/// OWNER: sol. System sounds only (no bundled audio, no license issue).
@MainActor
final class ChimePlayer {
    func play(name: String, volume: Double) {
        guard let sound = NSSound(named: NSSound.Name(name))?.copy() as? NSSound else { return }
        sound.volume = Float(max(0, min(1, volume)))
        sound.play()
    }
}
