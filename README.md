# DDrawCompat DelphiX Child-Window Clipping Example

This repository is a minimal Delphi 2007 / VCL repro for a mixed GDI + DirectDraw windowed rendering scenario.

It is designed to test how wrapper `ddraw.dll` implementations behave when:

- `TDXDraw` is hosted as a child HWND.
- Rendering uses an offscreen surface + primary present path.
- Native child controls (`TEdit`, `TButton`, `TMemo`) overlap the render area.
- Presentation runs at high frequency (`Application.OnIdle`) under optional stress.

No private game/client code is required to build or run this repro.

## Current State

The current example intentionally uses a stricter reproduction path:

- Offscreen updates use `Lock/Unlock` memory writes (instead of `Surface.Canvas`).
- Present coordinates use `ClientToScreen(DXDraw.Handle)`.
- Render loop is `Application.OnIdle` (`Done := False`) rather than `TTimer`.
- Runtime toggle: `Use primary HWND clipper`.
- Runtime toggle: `Stress child HWND redraw`.

This setup produces a clearer A/B signal across wrappers than the earlier, milder sample.

## Problem Summary

Under this repro, wrapper behavior differs significantly:

- Some wrappers keep child controls mostly stable.
- Some wrappers show visible flicker/overdraw on overlapping child controls.
- Flicker severity increases in stress mode and in high-frequency idle rendering.

In short: the issue is reproducible in a standalone DelphiX app and is not tied to a specific private project.

## Build

Open `DDrawCompatDelphiXExample.dproj` in Delphi 2007 and build.

The repository includes a local `DelphiX` copy for portability.

`DelphiX\DirectX.pas` contains Delphi 2007 compatibility adjustments:

- `NilGUID` is declared as an initialized constant.
- `PDirectDrawSurface` is set to `Pointer` for compiler compatibility.

## Test Matrix

Place one wrapper set next to the built EXE and compare behavior:

- System DirectDraw (`no local ddraw.dll`)
- DDrawCompat `DDraw.dll`
- dgVoodoo2 `DDraw.dll` (+ optional `dgVoodoo.conf`)

Observe:

- Text visibility in `TEdit`/`TMemo`
- Control edge stability (flicker frequency)
- Overdraw persistence after stress toggles

## Notes

- `bin/` includes ready-to-run wrapper binaries used during validation.
- This repository focuses on rendering behavior only; it intentionally excludes any private product-specific integration.
