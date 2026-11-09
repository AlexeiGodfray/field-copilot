# 3D capture and AR preview

**Status: deferred** (October 27, 2026). None of this is in the app yet. This page records what we
learned and decided, so the work can restart without repeating the research. Licensing and privacy
questions for this feature are tracked in [compliance.md](compliance.md#deferred-3d-capture).

## Goal

Two jobs, both for contractors selling to homeowners:

1. **Capture the equipment already at a home in 3D**, for the job record and to show the homeowner.
2. **Show the product being sold in the homeowner's space**, at true size, before they buy.

The constraint that shapes everything: a contractor takes **1 to 6 photos** and expects to see
something within seconds.

## What we learned

### Apple's Object Capture doesn't fit

Object Capture is photogrammetry: it measures points that appear in many overlapping photos. Apple
recommends 20 to 200 photos, it needs LiDAR to run on an iPhone, and it takes minutes. It's accurate,
but not for a contractor taking a handful of photos.

ARKit is a different thing: it tracks the phone, measures the ground and distances, and places 3D
models in the camera view. It doesn't build models. In the plans below it only records each photo's
position and the unit's real size, and displays the result.

### AI image-to-3D models

These generate a whole object from 1 to a few photos, guessing the sides they can't see.

| Model | Photos | License | Hardware | Speed | Notes |
|---|---|---|---|---|---|
| SAM 3D Objects (Meta) | 1, plus a mask | SAM License (royalty-free; trade-control and other terms; checkpoints gated) | Linux, NVIDIA GPU with 32 GB | About 13 s per object on an A100 | Built for real photos with clutter. A community Mac port runs only at low quality on 24 GB, about 10 minutes per object. |
| MV-SAM3D | Several, plus masks | SAM License, but defaults to Depth Anything 3 Nested Giant-Large, which is **CC BY-NC 4.0 (non-commercial)** | As SAM 3D, plus Depth Anything 3 | Not published | Research code (11 commits). Commercial use needs the depth model replaced, for example with ARKit poses and depth or Depth Anything 3 Small or Base (Apache-2.0). No Mac port. |
| TRELLIS (Microsoft) | Several (tuning-free; "may not give the best results") | MIT | NVIDIA GPU with 16 GB | Not measured | Textured output. No Mac port found. |
| TRELLIS.2 (Microsoft) | 1 | MIT | 24 GB | About 5 minutes on an M4 Pro Mac (community port) | Highest detail of these. |
| TripoSR | 1 | MIT | Core ML port, 800 MB | About 2 s on an M-series Mac's Neural Engine | Fast, but low detail. |
| Hunyuan3D-2mv (Tencent) | Up to 4: front, left, back, right | Tencent Hunyuan Community License: not licensed in the EU, UK, or South Korea; a company whose products had more than 1 million monthly active users at release must ask Tencent | About 5 to 6 GB of GPU memory (1.1B parameters) | Not measured | Best fit for several photos and better detail, but shape only. |

Ruled out: Hunyuan3D 2.1 (same Tencent license), Stable Fast 3D (free only for businesses under $1M
revenue), TriSplat (the paper is CC BY-NC-SA; no code or weights found), and InstantMesh (needs
generated views at fixed angles, not real photos).

Running any of these on the M5 Pro MacBook (24 GB) is possible only through community ports, and
takes minutes per object. That's fine for proving the pipeline, not for the "seconds" experience.

## Recommended direction

1. **Use manufacturer 3D files where they exist.** The app already reads the model number. Many HVAC
   manufacturers publish Revit or BIM files of their units. Where one exists, scan the label, fetch
   the file, and the shape and size are exact with no AI. Check each manufacturer's terms first:
   design files are often licensed for building design, not for redistribution in an app.
2. **Build photo-wrapped templates on the phone.** HVAC equipment is mostly boxes and cylinders:
   - The equipment type (from the classifier being trained, or one tap) picks a template: a box with
     a top fan, a cabinet, or a cylinder.
   - ARKit, plus LiDAR on Pro iPhones, measures width, depth, height, and which way it faces.
   - Each face gets the photo that sees it most head-on, straightened with Core Image's
     `CIPerspectiveCorrection`.
   - RealityKit builds it with `MeshResource.generateBox(width:height:depth:cornerRadius:splitFaces:)`
     (one material per face) and saves it with `Entity.write(to:)` as USDZ.

   It takes under a second, works offline, needs no server, and has no model licenses. It loses fine
   3D detail such as fan-guard depth and pipes.
3. **Train our own small model**, owned by the ML side: predict template parameters (type,
   proportions, fan position, grille, top shape) from the photos. It would be a few MB as Core ML,
   trained on synthetic renders from a parametric Blender model plus field captures. Each field
   capture comes labeled: the label scan gives the exact model number, and the spec sheet gives the
   true dimensions. Training a general photo-to-3D model from scratch isn't worth it.
4. **Later, optionally:** fine-tune TRELLIS (MIT) on collected data, as a server path for units the
   templates can't describe.
5. **For product previews,** use manufacturer models scaled to spec-sheet dimensions. No contractor
   photos are needed.

## Capture flow on the iPhone

ARKit doesn't run in the Simulator, so this needs a real iPhone on iOS 27. LiDAR (Pro models) gives
exact size; other iPhones estimate it from the ground plane.

1. **Tap the unit.** The app pins the unit's position on the ground. Vision's
   `GenerateForegroundInstanceMaskRequest` outlines the unit, and the outline plus depth gives its size.
2. **Photo 1 is taken automatically** from where the contractor stands, ideally a front corner about
   45° off the front and a little above. One photo is enough for a model.
3. **Photos 2 to 4** are the other corners. A ring with four slots appears on the ground. The app takes
   each photo itself when the phone reaches a slot and the frame is sharp, using the existing
   `PhotoQuality` check. Spoken prompts guide the walk. For Hunyuan3D-2mv, the slots would be the four
   sides instead.
4. **Photos 5 and 6** are optional: from above, or close-ups of details.
5. **Done.** The contractor can stop after any photo.

## Capture bundle format

Every capture is saved in a layout MV-SAM3D reads directly (`images/`, plus a folder named after the
object holding RGBA masks), with ARKit's measurements alongside. The same bundle works for any of the
models above, and as training data.

```
<capture>/
  images/0.png, 1.png, …   portrait, upright, 1440 × 1920
  unit/0.png, 1.png, …     RGBA; alpha marks the unit (MV-SAM3D: --mask_prompt unit)
  depth/0.bin, …           LiDAR depth, float32 meters, portrait 192 × 256 (Pro iPhones only)
  capture.json
```

`capture.json` holds:

- `views[]`: for each photo, the image and mask paths, the size, the intrinsics `[[fx, 0, cx],
  [0, fy, cy], [0, 0, 1]]` for the portrait image, and the camera-to-world transform as 16 floats in
  column-major order.
- `unit`: center position, approximate width, depth, and height in meters, and equipment type.
- `label`: brand, model, and serial from the scan, so the capture is labeled for training.
- `convention`: ARKit's. The world is in meters with y up. The camera's x points right and y points
  up, and it looks along −z. Image pixels have the origin at the top left.

ARKit's camera image is in the sensor's landscape orientation. When it's rotated 90° clockwise to
portrait, the intrinsics become `fx' = fy`, `fy' = fx`, `cx' = 1440 − cy`, `cy' = cx`. The
camera-to-world transform becomes `T · M`, where `M` has columns `(0, 1, 0)`, `(−1, 0, 0)`,
`(0, 0, 1)`.

## Open questions

- Which of our main brands publish 3D files, and on what terms?
- If a server is used, who runs it and where? Sending customers' home photos to a third-party AI
  service needs explicit consent (App Store guideline 5.1.2(i)) and a privacy review.
- Legal sign-off on any model license before use: SAM License, Tencent Hunyuan, Depth Anything 3.
- Test devices: an iPhone on iOS 27, ideally a Pro model with LiDAR.

## Sources

- SAM 3D Objects: [paper](https://arxiv.org/pdf/2511.16624), [repo and SAM License](https://github.com/facebookresearch/sam-3d-objects),
  [speed on A100](https://arxiv.org/pdf/2604.27106), [Mac port](https://github.com/doublesharp/sam3d-objects-mac)
- MV-SAM3D: [paper](https://arxiv.org/abs/2603.11633), [repo](https://github.com/devinli123/MV-SAM3D),
  [Depth Anything 3 licenses](https://github.com/ByteDance-Seed/Depth-Anything-3)
- TRELLIS: [repo](https://github.com/microsoft/TRELLIS); TRELLIS.2: [model card](https://huggingface.co/microsoft/TRELLIS.2-4B),
  [Mac port](https://github.com/shivampkumar/trellis-mac)
- TripoSR: [model card](https://huggingface.co/stabilityai/TripoSR), [Core ML port](https://huggingface.co/mickeyvanolst/triposr-coreml)
- Hunyuan3D-2mv: [model card and license](https://huggingface.co/tencent/Hunyuan3D-2mv)
- Object Capture: [WWDC21 session](https://developer.apple.com/wwdc21/10076/),
  [LiDAR requirement](https://developer.apple.com/forums/thread/769221)
