# FrameShift

On-device iPhone camera that helps you recreate a reference photo.

Import a shot you liked (Photos, Pinterest, Instagram, camera roll). FrameShift analyzes it on the phone and turns on live framing guides while you shoot: head placement, level and tilt, zoom coaching, short tips, and a ghost overlay of the reference.

**App Store:** [FrameShift Camera](https://apps.apple.com/us/app/frameshift-camera/id6789638657)

No account. No backend. Vision and guides run on-device. Requires iPhone, iOS 17+, portrait orientation.

## How it works

1. Switch to Reference and add photos, or try the bundled sample pack.
2. Open Camera with a reference selected.
3. Line up the guides, then capture.
4. Review shots in the gallery. Favorite, filter, or share.

## Camera

- Live viewfinder with framing guides when a reference has a detectable person
- Level and tilt from the iPhone motion sensors
- Multi-lens zoom, front camera, flash / screen flash
- Tap to focus, drag to adjust exposure
- Hold the shutter for burst; pick a best shot later
- Aspect options for posts (4:3) and stories (16:9)

## Build

Open `Frameshift/FrameShift.xcodeproj` in Xcode 16+ and run the `FrameShift` scheme on an iPhone (camera features need a device). Bundle ID: `com.anirudhkamath.frameshift`.

## Privacy

Photos and analysis stay on the device. See [PRIVACY.md](PRIVACY.md) and the in-app policy.
