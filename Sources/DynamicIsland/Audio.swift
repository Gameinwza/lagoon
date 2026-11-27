import AudioToolbox
import CoreAudio
import Foundation

/// System output volume / mute and the current output device, kept live with CoreAudio listeners (no polling).
@MainActor
final class OutputAudio: ObservableObject {
    @Published private(set) var volume: Float = 0.5
    @Published private(set) var muted = false
    @Published private(set) var deviceName = ""
    @Published private(set) var canSetVolume = true

    private var device = AudioObjectID(kAudioObjectUnknown)
    private var deviceListener: AudioObjectPropertyListenerBlock?

    private static func addr(_ sel: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: sel, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }
    private static let volumeAddr = addr(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioDevicePropertyScopeOutput)
    private static let muteAddr = addr(kAudioDevicePropertyMute, kAudioDevicePropertyScopeOutput)

    func start() {
        var a = Self.addr(kAudioHardwarePropertyDefaultOutputDevice)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &a, .main) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.attach() }  // queue is .main
        }
        attach()
    }

    /// Follow the default output device (switching to AirPods etc.) and listen to its volume and mute.
    private func attach() {
        var a = Self.addr(kAudioHardwarePropertyDefaultOutputDevice)
        var id = AudioObjectID(kAudioObjectUnknown), size = UInt32(MemoryLayout<AudioObjectID>.size)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size, &id)
        if let l = deviceListener, device != kAudioObjectUnknown {
            var v = Self.volumeAddr, m = Self.muteAddr
            AudioObjectRemovePropertyListenerBlock(device, &v, .main, l)
            AudioObjectRemovePropertyListenerBlock(device, &m, .main, l)
        }
        device = id
        let l: AudioObjectPropertyListenerBlock = { [weak self] _, _ in MainActor.assumeIsolated { self?.read() } }
        deviceListener = l
        var v = Self.volumeAddr, m = Self.muteAddr
        AudioObjectAddPropertyListenerBlock(id, &v, .main, l)
        AudioObjectAddPropertyListenerBlock(id, &m, .main, l)

        var n = Self.addr(kAudioObjectPropertyName)
        var name: Unmanaged<CFString>?
        size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        if AudioObjectGetPropertyData(id, &n, 0, nil, &size, &name) == noErr, let s = name?.takeRetainedValue() {
            deviceName = s as String
        }
        var settable: DarwinBoolean = false
        canSetVolume = AudioObjectIsPropertySettable(id, &v, &settable) == noErr && settable.boolValue
        read()
    }

    private func read() {
        var v = Self.volumeAddr, m = Self.muteAddr
        var vol: Float32 = 0, size = UInt32(MemoryLayout<Float32>.size)
        if AudioObjectGetPropertyData(device, &v, 0, nil, &size, &vol) == noErr { volume = vol }
        var mute: UInt32 = 0; size = UInt32(MemoryLayout<UInt32>.size)
        if AudioObjectGetPropertyData(device, &m, 0, nil, &size, &mute) == noErr { muted = mute != 0 }
    }

    func setVolume(_ x: Float) {
        var v = Self.volumeAddr, vol = Float32(min(max(x, 0), 1))
        AudioObjectSetPropertyData(device, &v, 0, nil, UInt32(MemoryLayout<Float32>.size), &vol)
        volume = vol
        if muted && vol > 0 { toggleMute() }  // dragging up un-mutes, like the menu bar slider
    }

    func toggleMute() {
        var m = Self.muteAddr, mute: UInt32 = muted ? 0 : 1
        AudioObjectSetPropertyData(device, &m, 0, nil, UInt32(MemoryLayout<UInt32>.size), &mute)
        muted = mute != 0
    }

    /// Speaker symbol that matches the level, like the system's.
    var icon: String {
        if muted || volume == 0 { return "speaker.slash.fill" }
        return volume < 0.34 ? "speaker.wave.1.fill" : volume < 0.67 ? "speaker.wave.2.fill" : "speaker.wave.3.fill"
    }
}
