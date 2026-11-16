import AppKit

/// System sounds only; keep the current sound alive through playback and stop overlapping previews.
@MainActor
final class ChimePlayer {
    private var currentSound: NSSound?

    func play(name: String, volume: Double) {
        currentSound?.stop()
        guard let sound = NSSound(named: NSSound.Name(name))?.copy() as? NSSound else {
            currentSound = nil
            return
        }
        sound.volume = Float(max(0, min(1, volume)))
        currentSound = sound
        sound.play()
    }
}
