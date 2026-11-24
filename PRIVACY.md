# FrameShift Privacy Policy

**Last updated: November 24, 2026**

FrameShift is designed to work entirely on your device. This policy explains exactly what that means.

## Information We Collect

FrameShift does not collect, transmit, or store any information outside of your device. There are no accounts and no sign-in, and the app has no backend server to send data to.

The app makes one kind of network request: on launch it downloads the list of curated Explore reference photos, and any new photos on it, from a public website (anikam13.github.io). These are plain downloads of public files. Nothing about you, your device, or your photos is sent with them — no identifiers, cookies, or analytics. If you're offline, the app works normally with the photos it already has.

## Camera Access

FrameShift requests camera access to show the live viewfinder and to capture photos when you tap the shutter. Camera frames are analyzed on-device (using Apple's Vision framework) to draw framing guides — this analysis never leaves your device, and frames are not stored unless you deliberately capture a photo.

## Photo Library Access

FrameShift requests two separate, limited permissions:

- **Importing reference photos**: handled through Apple's system photo picker, which runs outside of FrameShift's process. FrameShift only ever receives the specific photos you choose to import — it never receives broad access to your photo library.
- **Saving your photos**: FrameShift saves the photos you take to your camera roll. This is "add-only" access — FrameShift cannot read, browse, or modify the rest of your photo library.
- **Deleting your photos**: if you choose Delete on a photo you took in FrameShift, iOS asks you to allow photo library access and then to confirm the deletion. FrameShift uses this access only to delete the specific photos it saved for you (they go to Recently Deleted); it never reads, browses, or uploads the rest of your library.

## On-Device Processing

When you import a reference photo, FrameShift uses Apple's Vision framework to analyze it (detecting the subject, pose, and horizon) entirely on your device, in order to build the framing guide shown on the camera screen. No image, video, or analysis result is ever uploaded anywhere.

## Data Storage

Reference photos and your app settings are stored locally in FrameShift's private storage on your device. Photos you take are saved to your camera roll; FrameShift keeps only a temporary copy while your shooting session is open, deleted when the session ends (30 minutes after your last photo). Nothing is synced to iCloud or any external server by FrameShift itself.

## Data Deletion

You can remove imported reference photos at any time from within the app, or use "Clear Imported References" in Settings → Storage. Deleting the app removes all of its data from your device.

## Third-Party Sharing

FrameShift does not share data with any third party. FrameShift contains no third-party analytics, advertising, or tracking SDKs.

## Children's Privacy

FrameShift does not knowingly collect personal information from anyone, including children, because it does not collect personal information from anyone.

## Changes to This Policy

If this policy changes, the "Last updated" date above will change, and the updated policy will be available both in the app and at this URL.

## Contact

Questions about this policy can be sent to: anirudhkamath01@gmail.com
