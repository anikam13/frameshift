---
name: Boyfriend Camera
colors:
  surface: '#f9f9fb'
  surface-dim: '#d9dadc'
  surface-bright: '#f9f9fb'
  surface-container-lowest: '#ffffff'
  surface-container-low: '#f3f3f5'
  surface-container: '#eeeef0'
  surface-container-high: '#e8e8ea'
  surface-container-highest: '#e2e2e4'
  on-surface: '#1a1c1d'
  on-surface-variant: '#464554'
  inverse-surface: '#2f3132'
  inverse-on-surface: '#f0f0f2'
  outline: '#777585'
  outline-variant: '#c7c4d6'
  surface-tint: '#4f4ccd'
  primary: '#3f3bbd'
  on-primary: '#ffffff'
  primary-container: '#5856d6'
  on-primary-container: '#e7e4ff'
  inverse-primary: '#c2c1ff'
  secondary: '#675d51'
  on-secondary: '#ffffff'
  secondary-container: '#efe0d1'
  on-secondary-container: '#6d6357'
  tertiary: '#7e3e00'
  on-tertiary: '#ffffff'
  tertiary-container: '#a25100'
  on-tertiary-container: '#ffe1cf'
  error: '#ba1a1a'
  on-error: '#ffffff'
  error-container: '#ffdad6'
  on-error-container: '#93000a'
  primary-fixed: '#e2dfff'
  primary-fixed-dim: '#c2c1ff'
  on-primary-fixed: '#0c006a'
  on-primary-fixed-variant: '#3631b4'
  secondary-fixed: '#efe0d1'
  secondary-fixed-dim: '#d2c4b6'
  on-secondary-fixed: '#221a12'
  on-secondary-fixed-variant: '#4f453b'
  tertiary-fixed: '#ffdcc6'
  tertiary-fixed-dim: '#ffb785'
  on-tertiary-fixed: '#301400'
  on-tertiary-fixed-variant: '#713700'
  background: '#f9f9fb'
  on-background: '#1a1c1d'
  surface-variant: '#e2e2e4'
  camera-black: '#000000'
  action-indigo: '#5856D6'
  premium-gold: '#D4AF37'
  interface-gray: '#8E8E93'
typography:
  display-xl:
    fontFamily: Inter
    fontSize: 40px
    fontWeight: '700'
    lineHeight: 48px
    letterSpacing: -0.02em
  headline-lg:
    fontFamily: Inter
    fontSize: 28px
    fontWeight: '600'
    lineHeight: 34px
    letterSpacing: -0.01em
  headline-lg-mobile:
    fontFamily: Inter
    fontSize: 24px
    fontWeight: '600'
    lineHeight: 30px
  body-md:
    fontFamily: Inter
    fontSize: 17px
    fontWeight: '400'
    lineHeight: 24px
  label-caps:
    fontFamily: Inter
    fontSize: 12px
    fontWeight: '600'
    lineHeight: 16px
    letterSpacing: 0.05em
  mono-value:
    fontFamily: courierPrime
    fontSize: 14px
    fontWeight: '400'
    lineHeight: 20px
rounded:
  sm: 0.25rem
  DEFAULT: 0.5rem
  md: 0.75rem
  lg: 1rem
  xl: 1.5rem
  full: 9999px
spacing:
  margin-main: 20px
  gutter: 12px
  control-gap: 8px
  safe-area-bottom: 34px
---

## Brand & Style

The design system is centered on the concept of "The Professional Eye for Everyone." It bridges the gap between high-end photographic tools and the intuitive simplicity of iOS-native interfaces. The brand personality is precise, reliable, and premium, designed for users who want effortless excellence in their photography without the friction of traditional manual cameras.

The visual style is **Minimalist with Glassmorphic accents**. It prioritizes the viewfinder content above all else, using clean lines, generous whitespace (or "dark space" in camera modes), and tactical use of depth to separate controls from the image. The goal is to evoke the feeling of a high-end physical lens—cool to the touch, responsive, and mechanically perfect.

## Colors

This design system utilizes a high-contrast palette optimized for both visibility in bright outdoor settings and discreet use in low-light environments. 

- **Action Indigo:** The primary functional color, used for active states, shutter confirmations, and primary CTA buttons. It provides a modern, high-energy contrast to the monochromatic base.
- **Pure Black/White:** The UI leverages absolute #000000 for the camera chrome to ensure the OLED display blends seamlessly with the hardware bezels, while #FFFFFF is used for high-readability text and icons.
- **Premium Gold:** Reserved strictly for "Pro" features, advanced filters, and subscription-tier indicators, adding a touch of luxury without cluttering the utility.
- **Neutral Grays:** Derived from iOS standards, these handle secondary information and disabled states.

## Typography

The typography system uses **Inter** (as the closest web-available equivalent to SF Pro) to maintain a native iOS feel while ensuring maximum legibility. 

- **Headlines:** Use Bold weights with tight letter-spacing for a modern, impactful look in gallery views and settings headers.
- **Labels:** Small caps with increased letter-spacing are used for camera technical data (ISO, Shutter Speed, Aperture) to mimic the aesthetic of professional DSLR readouts.
- **Values:** Technical readouts and metadata use a monospaced variant to prevent layout shifting during real-time data updates in the viewfinder.
- **Scale:** The system prioritizes a 17px body size to align with iOS Human Interface Guidelines for accessibility and comfort.

## Layout & Spacing

The layout follows a **Fixed Grid** philosophy tailored for mobile ergonomics. 

- **Viewfinder-First:** The central 4:3 or 16:9 area is protected from UI overlap. Controls are clustered in the "Thumb Zone" (the bottom 35% of the screen).
- **Control Bar:** A 12-column grid is used for the bottom utility bar, where icons are centered within 44x44pt hit targets.
- **Margins:** Standard 20px side margins ensure UI elements do not interfere with the grip of the phone.
- **Adaptivity:** On iPad or horizontal orientation, the control bar reflows into a vertical sidebar on the right-hand side, mimicking the grip of a traditional camera body.

## Elevation & Depth

Hierarchy is established primarily through **Glassmorphism** and **Tonal Layers** rather than traditional shadows.

- **Floating Overlays:** Use a "Heavy" backdrop blur (30px+) with a 20% white or black tint. This allows the colors of the live camera feed to bleed through while maintaining text contrast.
- **Surface Tiers:** The base layer is the camera feed. Level 1 is the control chrome. Level 2 consists of modal sheets and pop-over settings.
- **Outlines:** Buttons and active states use a 0.5pt inner stroke to give a "etched" look, suggesting precision manufacturing.
- **Shadows:** Minimal, soft ambient shadows (8% opacity) are used only for floating action buttons to lift them off the viewfinder.

## Shapes

The shape language is defined by "Squircle" geometry, consistent with iOS's refined aesthetic. 

- **Primary Containers:** 16px (rounded-lg) is the standard for cards and sheets. 
- **Interactive Elements:** Buttons and input fields use a consistent 12px radius to feel substantial yet modern.
- **The Shutter:** A perfect circle, utilizing a double-ring design—an outer 2pt stroke ring and an inner solid Indigo circle—to create a distinct focal point.
- **Icons:** Thin-stroke (1.5pt) icons with rounded caps and joins to match the soft edges of the UI.

## Components

- **Action Buttons:** High-contrast Indigo backgrounds with white icons. On press, they should subtly scale down (95%) to provide tactile haptic-ready feedback.
- **Glass Chips:** Used for camera mode switching (e.g., Portrait, Night, Pro). Semi-transparent background with a subtle white border when active.
- **Dial Controls:** For exposure and focus, use a horizontal scrollable dial with haptic feedback at every major increment.
- **Information Cards:** Minimalist, with no background color, using only thin dividers (0.5pt) to separate content sections.
- **Checkboxes & Radios:** Replaced by toggle switches for a more "hardware-switch" feel, using the Action Indigo for the 'on' state.
- **Input Fields:** Bottom-aligned with a simple underline or a very subtle glass fill; no heavy boxes.
- **The "Focus Square":** A distinctive 1pt Indigo frame that appears on the viewfinder, pulsing slightly when focus is locked.