# DDrawCompat DelphiX Child-Window Clipping Example

This is a minimal Delphi 2007 / VCL repro for DirectDraw primary-surface presentation over native child windows.

The sample mirrors the real Mir client's windowed rendering path as closely as possible:

- A `TDXDraw` control is created as a child window of the main VCL form.
- DelphiX runs in windowed blit mode, not exclusive fullscreen flip mode.
- DelphiX creates a DirectDraw primary surface.
- DelphiX attaches an HWND clipper to the `TDXDraw.Handle`.
- **Offscreen surface drawing uses Lock/Unlock pixel copy** (matching `DrawSurface16Local` in `mClient.DLL`), not `Surface.Canvas` (which uses GDI `GetDC/ReleaseDC` that DDrawCompat's GDI interop can hook).
- **Primary.Draw uses `ClientToScreen(DXDraw1.Handle)`** for screen coordinates (matching `CalcMainClientScreenPos` in `mClient.DLL`), not the main form's `ClientRect`.
- **Rendering runs in `Application.OnIdle`** with `Done := False`, not `TTimer.Interval = 16`. This matches the real client's idle-loop rendering and produces a much higher frame rate than WM_TIMER.
- Native sibling child HWNDs (`TEdit`, `TButton`, `TMemo`) overlap the `TDXDraw` child window.
- Stress mode invalidates sibling child HWNDs every frame and updates `TEdit` text every 30 frames.
- The parent form has `WS_CLIPCHILDREN | WS_CLIPSIBLINGS`.
- The `TDXDraw` child window has `WS_CLIPSIBLINGS`.

## Why the Previous Example Could Not Reproduce the Problem

The previous version of this example used three rendering patterns that differ significantly from the real Mir client:

### 1. Surface.Canvas (GDI path) vs Lock/Unlock (pure DirectDraw path)

Previous version drew to the offscreen surface using `Surface.Canvas`, which internally calls `IDirectDrawSurface::GetDC` / `ReleaseDC`. DDrawCompat's `GdiInterops` hooks intercept these GDI calls and can coordinate with its presentation pipeline.

The real client uses `DrawSurface16Local` (in `mClient.DLL/mModule.pas`), which is pure `Lock` → pixel-by-pixel copy → `Unlock`. DDrawCompat sees the `Lock`/`Unlock` calls but has no visibility into the actual pixel content being composed—it's just raw memory access.

This matters because DDrawCompat's `RealPrimarySurface::updatePresentation` decides when and how to present based on surface change notifications. When the offscreen surface is modified via `Lock`/`Unlock` (no GDI involvement), DDrawCompat has fewer synchronization points to coordinate with GDI child window repainting.

### 2. ClientToScreen(Handle) vs ClientToScreen(DXDraw.Handle)

Previous version used `ClientToScreen(Handle, ...)` on the main form, making `Primary.Draw` target the entire form client area. The real client uses `CalcMainClientScreenPos` which calls `ClientToScreen(DXDraw1.Handle)`, targeting just the DXDraw viewport area.

When `Primary.Draw` uses the DXDraw HWND's screen coordinates, the clipper attached to that HWND determines which pixels the DirectDraw blit can actually write. The main form's client area is larger than the DXDraw viewport, so using the form's coordinates changes the clipping behavior.

### 3. TTimer (WM_TIMER) vs Application.OnIdle

Previous version used `TTimer.Interval = 16` for rendering. `WM_TIMER` is a low-priority message that coalesces and rarely achieves 60fps. The real client renders in `Application.OnIdle` with no frame cap—each frame begins as soon as the message queue is empty.

Higher frame rates mean more frequent `Primary.Draw` calls, which means more frequent overwrites of GDI child window pixels. DDrawCompat's `PresentDelay` can delay presentation to reduce flicker at lower frame rates, but at idle-loop frame rates (potentially hundreds of fps), the delay window becomes proportionally less effective.

### 4. Surface.Canvas Release Synchronization

When using `Surface.Canvas.Release` (which calls `IDirectDrawSurface::ReleaseDC`), DDrawCompat receives a GDI synchronization point before the subsequent `Primary.Draw`. This gives its GDI interop pipeline more information about when the offscreen surface content is ready.

With Lock/Unlock, there is no such GDI synchronization point between the surface content preparation and the primary blit. DDrawCompat sees a `Lock` → `Unlock` → `Blt` sequence on the offscreen surface, followed by a `Blt` on the primary surface, with no GDI interop hooks in between.

## Build

Open `DDrawCompatDelphiXExample.dproj` in Delphi 2007 and build.

The project includes a local DelphiX copy under:

```text
DelphiX
```

`DelphiX\DirectX.pas` contains a small Delphi 2007 compatibility adjustment:

- `NilGUID` is declared as an initialized constant instead of using the old `absolute 0` compatibility expression.
- `PDirectDrawSurface` is fixed to `Pointer`, matching the old DelphiX workaround for compilers that reject interface types inside variant records.

## Test Matrix

Build the EXE, then test by placing one of these next to the built executable:

- no wrapper, using the system `ddraw.dll`
- DDrawCompat `DDraw.dll`
- dgVoodoo2 `DDraw.dll` plus `dgVoodoo.conf`

Expected good behavior:

- The overlapping `TEdit`, `TButton`, and `TMemo` remain visible and stable.
- DirectDraw animation continues behind them without covering or flickering through the child controls.
- With stress mode enabled, child controls should still remain stable.

Problem behavior:

- The native child windows flicker.
- Child controls disappear intermittently.
- DirectDraw primary blits cover the child controls.

The `Stress child HWND redraw` checkbox can be disabled at runtime to compare the same primary-draw path without child-window invalidation pressure.

## Current Observation

With the Lock/Unlock + OnIdle + DXDraw.Handle path, DDrawCompat flickers more heavily and more consistently than with the previous Canvas + Timer + Form.Handle path. This confirms that the rendering path differences listed above are significant factors in reproducing the real client's problem behavior.

## Relevant Real Client Code

The real client's windowed rendering path (`mClient.DLL`):

```pascal
// mMain.pas CalcMainClientScreenPos:
// Uses ClientToScreen(DXDraw1.Handle) to compute screen coordinates

// mModule.pas TDirectDrawSurface_Draw:
// Routes all Surface.Draw to DrawSurface16Local (Lock/Unlock pixel copy)
// Falls back to original IDirectDrawSurface::Blt only in fullscreen mode

// mPatch.pas TfrmMain_DrawPrimaryPatch:
// Per-frame: releases JSY canvas → CalcMainClientScreenPos → Primary.Draw
```

The DelphiX clipper setup (`DXDraws.pas`):

```pascal
FDXDraw.FClipper := TDirectDrawClipper.Create(FDXDraw.FDDraw);
FDXDraw.FClipper.Handle := FDXDraw.Handle;
FDXDraw.FPrimary.Clipper := FDXDraw.FClipper;
```

And the blt driver (`TDXDrawDriverBlt.Flip`):

```pascal
pt := FDXDraw.ClientToScreen(Point(0, 0));
Dest := Bounds(pt.x, pt.y, FDXDraw.FSurface.Width, FDXDraw.FSurface.Height);
FDXDraw.FPrimary.Blt(Dest, FDXDraw.FSurface.ClientRect, DDBLT_WAIT, df, FDXDraw.FSurface);
```