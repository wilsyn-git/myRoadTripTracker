# Image Attachments for Observations

## Summary

Allow users to attach photos to observation entries during road trips. Currently observations are text-only. This feature would let users capture what they're seeing alongside their notes.

## Current State

- `ObservationEntry` model: `category`, `authorName`, `text`, `createdDate`, relationship to `Trip`
- Compose UI: text field + submit button
- Data syncs via CloudKit (Core Data + NSPersistentCloudKitContainer)

## Proposed Approach

Add an optional `Binary Data` attribute (`imageData`) to `ObservationEntry` with "Allows External Storage" enabled. CloudKit handles syncing large binary attributes as `CKAsset` automatically.

- Lightweight Core Data migration (adding an optional attribute)
- SwiftUI `PhotosPicker` for image selection
- Display inline thumbnail in observation rows

## Open Questions

### Limits & Constraints
- [ ] Max image size? (e.g., resize to 1024px wide before storing?)
- [ ] Max number of images per entry? (1 to start, or multiple?)
- [ ] Compression quality? (e.g., JPEG at 0.7?)
- [ ] CloudKit storage limits to be aware of? (CKAsset max is 50MB per asset)

### UX Decisions
- [ ] Camera capture, photo library, or both?
- [ ] Can users remove/replace an image after posting?
- [ ] Show images as thumbnails in the list, or tap-to-expand only?
- [ ] Should images be visible in the closed/archived trip view?
- [ ] Any placeholder or loading state while CloudKit syncs the image?

### Technical Considerations
- [ ] Generate a separate thumbnail `Data` attribute for fast list rendering?
- [ ] Strip EXIF/location metadata from photos, or preserve it?
- [ ] How does this interact with the share sheet / CloudKit sharing?
- [ ] Test lightweight migration path from current schema
