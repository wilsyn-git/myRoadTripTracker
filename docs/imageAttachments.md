# Image Attachments for Observations

## Summary

Allow users to attach photos to observation entries during road trips. Currently observations are text-only. This feature would let users capture what they're seeing alongside their notes.

## Current State

- `ObservationEntry` model: `category`, `authorName`, `text`, `createdDate`, relationship to `Trip`
- Compose UI: text field + submit button
- Data syncs via CloudKit (Core Data + NSPersistentCloudKitContainer)
- Only `PlateSighting` captures location (lat/long). `ObservationEntry` does not.

## Proposed Approach

Add optional `Binary Data` attributes to `ObservationEntry`:
- `imageData` — full image (1024px wide, JPEG 0.8), with "Allows External Storage" enabled
- `thumbnailData` — smaller thumbnail for fast list rendering

CloudKit handles syncing large binary attributes as `CKAsset` automatically. At 1024px / JPEG 0.8, images will be ~200-500KB each, well under the 50MB CKAsset limit.

Lightweight Core Data migration (adding optional attributes — should be automatic).

## Decided

### Limits & Constraints
- **Max image size**: resize to 1024px wide before storing (minimizes file size)
- **Images per entry**: 1 (users can make multiple posts if they want multiple images)
- **Compression**: JPEG at 0.8
- **CloudKit**: each image = 1 CKAsset, ~200-500KB each, no concerns

### UX
- **Source**: both camera and photo library (via PhotosPicker)
- **Editing**: users can remove their own image, but not replace (post again instead)
- **Display**: thumbnails visible inline in the list (e.g., "sam posted: <thumbnail>")
- **Closed trips**: images remain visible, always
- **Sync placeholder**: `photo.badge.arrow.down` SF Symbol while CloudKit syncs

### Technical
- **Thumbnail attribute**: yes, separate `thumbnailData` field for fast list rendering
- **EXIF metadata**: strip it. No location data on observations for now — can revisit later if valuable.
- **CloudKit sharing**: images sync automatically to shared trip participants via CKAsset — no extra work
- **Schema promotion**: after adding new attributes, promote development schema to production in CloudKit Dashboard before App Store release — document this step

## Implementation Checklist

- [ ] Add `imageData` (Binary Data, external storage) and `thumbnailData` (Binary Data) to `ObservationEntry` in the data model
- [ ] Update `ObservationEntry+CoreDataProperties.swift` with new attributes
- [ ] Build image resize/compress utility (1024px wide, JPEG 0.8, strip EXIF)
- [ ] Build thumbnail generator
- [ ] Add PhotosPicker + camera to `ComposeEntryRow`
- [ ] Update `ObservationEntryRow` to show thumbnail inline
- [ ] Add tap-to-view-full-image presentation
- [ ] Add delete-own-image support
- [ ] Add sync placeholder (photo.badge.arrow.down) for images not yet downloaded
- [ ] Test lightweight Core Data migration from current schema
- [ ] Document CloudKit Dashboard schema promotion steps
