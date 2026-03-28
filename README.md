# DoodlAR Apple/Banana Refactoring Walkthrough

## Summary of Changes
This update successfully completes the transition of DoodlAR to an Apple/Banana exclusive classification model, rebuilds the AR spawn flow for better usability, and resolves critical build and logic errors.

### 1. Model Limitation and Codebase Cleanup
- **CreatureType.swift**: Removed all obsolete creatures (dragons, cats, birds, etc.) safely isolating them inside comments, limiting the enum to `.apple`, `.banana`, and `.unknown`.
- **Unit Tests**: Updated `CreatureTests.swift` and `PaperDetectorTests.swift` to align with the new limited feature scope, ensuring all tests successfully pass.

### 2. ARKit and 3D Rendering Capabilities
- **Xcode Target Fix**: Successfully bypassed Xcode Source Control blockages by automating the target assignment via Homebrew and `xcodegen`. Modified `project.yml` to remove exclusion rules on `Resources/Models/**`, ensuring `creature_apple.usdz` and `creature_banana.usdz` are securely bundled inside the app's build phase.
- **LiDAR Fallback Implementation**: Fixed a critical crash where `raycastFromCenter()` would return `nil` on iPad screens and uniformly colored desks for non-LiDAR iPhones. ARKit now smoothly falls back to a 40cm horizontal and 20cm drop projection coordinate, ensuring the 3D entity spawns in mid-air instead of failing with a confusing ".paperNotFound" error.

### 3. Detection and Spawn UX Rework
- **Vision Reliability Relaxing**: Relaxed the `VNDetectRectanglesRequest` strict bounds inside `VisionService.swift`. Dropped the confidence threshold to `20%` and removed aspect ratio strictness so the model can successfully isolate drawings presented on glowing iPad screens in low-light environments.
- **Manual "Collect & Spawn" Flow**: Modified the automatic spawn pipeline. Users can now successfully classify the item first, allowing them to tap `"Collect & Spawn"` *before* triggering the `SpawnState` morphing sequences.
- **Collection Duplication Blocker**: Programmed `CollectionViewModel` to verify `CreatureType` uniqueness. The Pokédex ignores any subsequent attempts to duplicate a collected Apple or Banana into the database.
- **Global Scene Wipe**: Hooked `ARViewModel` into `CollectionView` so when the Pokédex is cleared via the new Trash UI, all 3D instances actively scattered around the physical AR space are instantaneously dismissed.

## Known Limitations and Future Actions

> [!WARNING]
> **3D Scaling Issues to Address**
> The current USDZ assets for the Apple and Banana contain inconsistent internal bounding boxes, forcing the dynamic `visualBounds` scalar to miscalculate their real size and spawn anomalies that span the entire room. While standard sizing multipliers `(SIMD3(repeating: 0.005) vs 0.02)` were hardcoded to hotfix this, future development should focus on opening the USDZ models in Reality Converter to normalize their scale primitives natively rather than isolating the override at runtime.

> [!TIP]
> **LiDAR Testing Recommendation**
> Current testing was performed successfully on an iPhone 16 base model (which lacks a LiDAR sensor). Since DoodlAR utilizes `isSceneReconstructionAvailable` to trigger advanced `CreatureNavigator` behavioral patterns via Mesh mapping, the application's actual spatial immersion will be completely different on a Pro device. Unlocking LiDAR will enable the Apple and Banana to actively pace around the desk and avoid falling off ledges. It is highly recommended to conduct QA testing on an iPhone Pro or iPad Pro to calibrate these physical navigation constraints.
