---
name: Boyfriend Camera
colors:
  surface: '#131313'
  surface-dim: '#131313'
  surface-bright: '#393939'
  surface-container-lowest: '#0e0e0e'
  surface-container-low: '#1c1b1b'
  surface-container: '#201f1f'
  surface-container-high: '#2a2a2a'
  surface-container-highest: '#353534'
  on-surface: '#e5e2e1'
  on-surface-variant: '#c7c4d6'
  inverse-surface: '#e5e2e1'
  inverse-on-surface: '#313030'
  outline: '#918f9f'
  outline-variant: '#464554'
  surface-tint: '#c2c1ff'
  primary: '#c2c1ff'
  on-primary: '#1c0b9f'
  primary-container: '#5856d6'
  on-primary-container: '#e7e4ff'
  inverse-primary: '#4f4ccd'
  secondary: '#53e16f'
  on-secondary: '#003911'
  secondary-container: '#05b046'
  on-secondary-container: '#003a11'
  tertiary: '#ffb785'
  on-tertiary: '#502500'
  tertiary-container: '#a25100'
  on-tertiary-container: '#ffe1cf'
  error: '#ffb4ab'
  on-error: '#690005'
  error-container: '#93000a'
  on-error-container: '#ffdad6'
  primary-fixed: '#e2dfff'
  primary-fixed-dim: '#c2c1ff'
  on-primary-fixed: '#0c006a'
  on-primary-fixed-variant: '#3631b4'
  secondary-fixed: '#72fe88'
  secondary-fixed-dim: '#53e16f'
  on-secondary-fixed: '#002107'
  on-secondary-fixed-variant: '#00531c'
  tertiary-fixed: '#ffdcc6'
  tertiary-fixed-dim: '#ffb785'
  on-tertiary-fixed: '#301400'
  on-tertiary-fixed-variant: '#713700'
  background: '#131313'
  on-background: '#e5e2e1'
  surface-variant: '#353534'
typography:
  screen-title:
    fontFamily: Inter
    fontSize: 17px
    fontWeight: '600'
    lineHeight: 22px
  body:
    fontFamily: Inter
    fontSize: 15px
    fontWeight: '400'
    lineHeight: 20px
  label-caps:
    fontFamily: Inter
    fontSize: 12px
    fontWeight: '600'
    lineHeight: 16px
    letterSpacing: 0.06em
  value-mono:
    fontFamily: Courier Prime
    fontSize: 14px
    fontWeight: '400'
    lineHeight: 18px
  cta:
    fontFamily: Inter
    fontSize: 16px
    fontWeight: '600'
    lineHeight: 20px
  micro:
    fontFamily: Inter
    fontSize: 11px
    fontWeight: '500'
    lineHeight: 14px
  wordmark:
    fontFamily: Inter
    fontSize: 15px
    fontWeight: '500'
    lineHeight: 20px
rounded:
  sm: 0.125rem
  DEFAULT: 0.25rem
  md: 0.375rem
  lg: 0.5rem
  xl: 0.75rem
  full: 9999px
spacing:
  margin-side: 20px
  card-padding: 16px
  component-gap: 8px
  safe-area-bottom: 34px
  hairline: 0.5px
---

## Brand & Style

The design system is anchored in a philosophy of "Quiet Precision." It treats the mobile interface as a high-end physical tool—a piece of professional equipment that recedes to prioritize the image. The target audience values technical mastery, understated luxury, and a "dark-first" environment that preserves night vision and focus.

The aesthetic blends **Minimalism** with **Modern Corporate** precision, utilizing:
- **Pure Black Foundation:** An absolute `#000000` base to achieve infinite contrast on OLED displays.
- **Instrumental Detail:** Use of hairline borders and monospaced data values to evoke the feel of a calibrated lens or high-end watch.
- **Confident Restraint:** Interactions are subtle; the UI does not compete with the viewfinder.

## Colors

The palette is strictly functional. Pure black (`#000000`) is the canvas for all photography-centric screens. Surface colors are tiered to create a hierarchy of depth without relying on traditional shadows.

- **Primary (Indigo):** Used sparingly for active states, focus points, and critical CTAs.
- **Secondary (Green):** Specifically reserved for "Level Locked" or "In Focus" confirmation states, mimicking digital rangefinders.
- **Grayscale:** Text scales from pure white for readability to low-opacity whites for metadata, ensuring information density doesn't become visual noise.

## Typography

This design system uses a dual-font strategy. **Inter** provides a modern, neutral, and highly legible framework for navigation and settings. **Courier Prime** is used for technical "Values" (ISO, Shutter Speed, Aperture, Coordinates) to provide a monospaced, typewriter-mechanical feel that distinguishes data from UI labels.

- **Wordmark:** Always rendered in `text-primary` at 15px, weight 500, with no accompanying icon.
- **Labels:** Use `label-caps` for section headers or small UI descriptors to maintain a structured, architectural feel.
- **Scale:** Type remains compact to maximize the visible area of the camera's viewfinder.

## Layout & Spacing

The layout philosophy follows a **Fixed Margin** model, prioritizing safe zones for hand-held mobile usage. 

- **Side Margins:** A generous 20px margin ensures that UI elements do not interfere with the natural grip of the phone or the edges of the screen.
- **Vertical Rhythm:** Components are spaced with an 8px base unit. 
- **Viewfinder:** The camera preview should ideally be edge-to-edge or formatted to 4:3 / 16:9 with "dead zones" filled by pure black surfaces.
- **Safe Areas:** Strict adherence to the 34px bottom safe area for gesture navigation, keeping primary shutter controls just above this line.

## Elevation & Depth

This design system eschews soft shadows in favor of **Tonal Layers** and **Glassmorphism**.

- **Surfaces:** Depth is communicated by increasing the lightness of the background. `surface-1` (#141414) is for secondary containers, while `surface-2` (#1C1C1E) is for interactive or floating elements.
- **Glass Overlays:** For elements that sit directly over the camera feed (viewfinder overlays), use a backdrop blur of 24px with a semi-transparent dark fill to maintain legibility without losing the sense of the scene behind the UI.
- **Hairline Borders:** Use 0.5px borders in `grid-line` color to define boundaries. These should be crisp and pixel-perfect to reinforce the "instrument" aesthetic.

## Shapes

The shape language is disciplined and professional. 

- **General UI:** Use "Soft" (0.25rem) roundedness for most interactive containers like cards and buttons to provide a hint of approachability.
- **Thumbnails/Media:** Photography thumbnails and the main viewfinder must have **0px (Sharp)** corners. This "clean cut" aesthetic treats the photo as a raw asset rather than a stylized UI component.
- **Control Dials:** Interactive wheels or sliders should utilize circular shapes for tactile familiarity.

## Components

- **Buttons:** 
  - **Primary CTA:** Solid `accent` background with `text-primary`.
  - **Secondary:** Surface-2 background with a hairline border.
- **Shutter Button:** Large, circular, high-contrast. Use a double-ring design (outer ring stroke, inner solid circle) to mimic physical shutter releases.
- **Input Fields:** Minimalist. No background fill; only a bottom hairline border that turns `accent` color when focused.
- **Chips/Status:** Use `accent-soft` background with `accent` text for active modes (e.g., "RAW", "PRO").
- **Grid Overlay:** When enabled, the viewfinder grid uses 0.5px lines in `grid-line` color.
- **Level Indicator:** A thin horizontal hairline in the center of the screen that turns `level-locked` (Green) when the device is perfectly level.
- **Control Strip:** A horizontal scroll of monospaced values for ISO, WB, and SS, allowing for precise, thumb-driven adjustments.