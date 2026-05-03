---
name: Kitchen Harmony
colors:
  surface: '#f8f9fa'
  surface-dim: '#d9dadb'
  surface-bright: '#f8f9fa'
  surface-container-lowest: '#ffffff'
  surface-container-low: '#f3f4f5'
  surface-container: '#edeeef'
  surface-container-high: '#e7e8e9'
  surface-container-highest: '#e1e3e4'
  on-surface: '#191c1d'
  on-surface-variant: '#404943'
  inverse-surface: '#2e3132'
  inverse-on-surface: '#f0f1f2'
  outline: '#707973'
  outline-variant: '#bfc9c1'
  surface-tint: '#2c694e'
  primary: '#0f5238'
  on-primary: '#ffffff'
  primary-container: '#2d6a4f'
  on-primary-container: '#a8e7c5'
  inverse-primary: '#95d4b3'
  secondary: '#895100'
  on-secondary: '#ffffff'
  secondary-container: '#fd9d1a'
  on-secondary-container: '#663b00'
  tertiary: '#404a38'
  on-tertiary: '#ffffff'
  tertiary-container: '#57624e'
  on-tertiary-container: '#d1ddc4'
  error: '#ba1a1a'
  on-error: '#ffffff'
  error-container: '#ffdad6'
  on-error-container: '#93000a'
  primary-fixed: '#b1f0ce'
  primary-fixed-dim: '#95d4b3'
  on-primary-fixed: '#002114'
  on-primary-fixed-variant: '#0e5138'
  secondary-fixed: '#ffdcbc'
  secondary-fixed-dim: '#ffb86b'
  on-secondary-fixed: '#2c1700'
  on-secondary-fixed-variant: '#683d00'
  tertiary-fixed: '#dbe7cd'
  tertiary-fixed-dim: '#bfcab2'
  on-tertiary-fixed: '#151e0f'
  on-tertiary-fixed-variant: '#3f4a37'
  background: '#f8f9fa'
  on-background: '#191c1d'
  surface-variant: '#e1e3e4'
typography:
  h1:
    fontFamily: Plus Jakarta Sans
    fontSize: 32px
    fontWeight: '700'
    lineHeight: '1.2'
  h2:
    fontFamily: Plus Jakarta Sans
    fontSize: 24px
    fontWeight: '600'
    lineHeight: '1.3'
  body-lg:
    fontFamily: Be Vietnam Pro
    fontSize: 18px
    fontWeight: '400'
    lineHeight: '1.6'
  body-md:
    fontFamily: Be Vietnam Pro
    fontSize: 16px
    fontWeight: '400'
    lineHeight: '1.5'
  label-sm:
    fontFamily: Be Vietnam Pro
    fontSize: 13px
    fontWeight: '600'
    lineHeight: '1.2'
    letterSpacing: 0.02em
rounded:
  sm: 0.25rem
  DEFAULT: 0.5rem
  md: 0.75rem
  lg: 1rem
  xl: 1.5rem
  full: 9999px
spacing:
  unit: 4px
  xs: 4px
  sm: 8px
  md: 16px
  lg: 24px
  xl: 40px
  container-margin: 20px
  gutter: 16px
---

## Brand & Style

This design system centers on a "Fresh Minimalism" aesthetic, designed to reduce the mental load of household management. The brand personality is dependable yet vibrant, evoking the feeling of a sun-drenched kitchen and a well-organized pantry. 

The target audience consists of busy families and health-conscious individuals who require high efficiency without sacrificing the sensory joy of food. To achieve this, the UI utilizes generous whitespace, soft-touch interactions, and a layout that prioritizes high-contrast legibility. The goal is to evoke a sense of calm, abundance, and nutritional wellness.

## Colors

The palette is rooted in the natural world to ensure an appetizing experience. 

- **Primary (Leafy Green):** Used for key actions, success states, and brand markers. It represents freshness and health.
- **Secondary (Soft Orange):** Reserved for highlights, notifications, and seasonal meal tags. It adds warmth and stimulates the appetite.
- **Tertiary (Sprout):** A very soft green used for large surface areas, subtle card backgrounds, and category grouping to differentiate sections without using heavy lines.
- **Neutral:** A range of clean whites and cool grays ensures the colorful food photography remains the focal point. Surfaces use a "Paper White" (#FFFFFF) while the background uses a "Mist" (#F8F9FA) to provide subtle depth.

## Typography

The typographic system balances the geometric friendliness of **Plus Jakarta Sans** for headings with the high readability and warmth of **Be Vietnam Pro** for functional text. 

Headlines are set with tight tracking and ample line height to create a modern, editorial feel. Body text is prioritized for quick scanning—essential for grocery store aisles or busy cooking environments. Labels use a slightly heavier weight and increased tracking to ensure they remain legible at small sizes on ingredient tags or nutritional badges.

## Layout & Spacing

The design system utilizes a **Fluid Grid** model based on an 8px rhythmic scale. For mobile views, a 4-column grid is standard, while tablet and desktop views scale to 12 columns. 

- **Lists:** Grocery items and recipe steps use a 16px vertical rhythm to ensure touch targets are accessible for all family members.
- **Grids:** Recipe discovery cards use a 16px gutter. 
- **Safe Areas:** A 20px horizontal margin is maintained across all screens to prevent content from feeling "cramped" against the device edges, reinforcing the airy, organized brand feel.

## Elevation & Depth

This design system avoids heavy shadows in favor of **Tonal Layers** and **Ambient Depth**. 

Hierarchy is established by stacking surfaces: 
1. **Level 0 (Background):** The base canvas in neutral Mist.
2. **Level 1 (Cards/Lists):** Pure white surfaces with a very soft, 10% opacity primary-tinted shadow (4px blur, 2px offset).
3. **Level 2 (Modals/Overlays):** Elevated surfaces with a more pronounced 15% opacity shadow to indicate temporary focus.

Low-contrast outlines (1px solid #E9ECEF) are used instead of shadows for secondary elements like input fields and inactive chips to keep the UI feeling "flat" and lightweight.

## Shapes

The shape language is defined by a "Medium Rounded" philosophy. This softens the technical nature of a utility app and makes it feel more approachable for a family setting. 

Standard components (buttons, input fields) use a 0.5rem radius. Large containers like recipe cards or meal plan buckets use a 1rem radius (rounded-lg) to create a friendly, "bento-box" style organization. Interactive elements that require high visibility, such as "Add to Cart" or "Start Cooking," may utilize pill-shaped (rounded-full) corners to distinguish them from static content.

## Components

- **Buttons:** Primary buttons are solid green with white text. Secondary buttons use a sprout-green tint with primary-green text. All buttons have a minimum height of 48px for easy tapping.
- **Chips:** Used for dietary preferences (e.g., "Vegan," "Nut-Free"). These use a 1px border and a light background tint matching the category color.
- **Grocery Lists:** Features a custom checkbox design—when checked, the item text should strike through and dim to 50% opacity, while the checkbox fills with the primary green.
- **Cards:** Recipe cards must include a high-quality image with a subtle gradient overlay at the bottom to ensure white text (recipe name) remains legible over the photo.
- **Input Fields:** Use a subtle "Mist" background with no border in their default state, gaining a 2px primary green border on focus.
- **Quantity Pickers:** A specialized component for the grocery list that allows users to tap "+" or "-" buttons; these are styled as small, high-contrast circles to ensure precision.