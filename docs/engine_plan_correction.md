# Engine Plan Implementation Review

This document analyzes the current implementation state against `docs/engine_plan.md` and identifies deviations, completed items, and technical debt requiring attention.

## Summary

The UI framework refactor outlined in engine_plan.md has been **fully completed**. The core architecture is in place: `UiRoot` owns components, events route through UI first, actions flow via `UiActionQueue`, and UI renders as a separate overlay pass. All identified deviations have been addressed.

---

## Status by Plan Section

### Section 1: Shared Utility Modules ✅ COMPLETE

| Module | Status | Notes |
|--------|--------|-------|
| `src/geom.zig` | ✅ | `Rect` and `containsPoint` helpers present |
| `src/anim/easing.zig` | ✅ | `easeInOutCubic` and other easing functions present |
| `src/gfx/primitives.zig` | ✅ | `drawRoundedBorder`, `drawThickBorder` moved from renderer |

### Section 2: UI Framework ✅ COMPLETE

| Component | Status | Notes |
|-----------|--------|-------|
| `UiHost` | ✅ | Present in `types.zig`, matches spec with additional fields |
| `UiAction` | ✅ | Expanded beyond original spec with new actions |
| `UiComponent` | ✅ | Vtable interface matches spec, added `hitTest` and `wantsFrame` |
| `UiRoot` | ✅ | Component registry, dispatch, action queue all working |
| `UiActionQueue` | ✅ | Present in `types.zig` |
| `UiAssets` | ✅ | Present with `font_cache` for shared rendering resources |

### Section 3: Integration into main.zig ✅ COMPLETE

- ✅ `UiHost` snapshot is built each frame
- ✅ `ui.handleEvent()` is called before app logic
- ✅ Events can be consumed by UI components
- ✅ Actions are drained via `popAction()`
- ✅ UI renders after scene render (`ui.render()`)

### Section 4: Help Overlay Component ✅ COMPLETE

- ✅ Lives in `src/ui/components/help_overlay.zig`
- ✅ Internal state machine: `Closed`, `Expanding`, `Open`, `Collapsing`
- ✅ Handles click toggling and Cmd+/ keyboard shortcut
- ✅ Caches text textures with invalidation on theme/scale changes
- ✅ High z-index (1000) for proper layering

### Section 5: Toast Component ✅ COMPLETE

- ✅ Lives in `src/ui/components/toast.zig`
- ✅ **Critical improvement implemented**: texture caching
  - Texture rebuilt only when message changes (via `dirty` flag)
  - No per-frame TTF_OpenFont calls
- ✅ `UiRoot.showToast()` forwards to component
- ✅ Alpha fade is time-based without texture rebuild

### Section 6: Escape Hold Component ✅ COMPLETE

- ✅ Lives in `src/ui/components/escape_hold.zig`
- ✅ Uses `HoldGesture` from `src/ui/gestures/hold.zig`
- ✅ Handles keydown/keyup properly
- ✅ Quick press+release passes ESC through to terminal
- ✅ Hold completion pushes `UiAction.RequestCollapseFocused`
- ✅ Renders arc indicator only when active

### Section 7: Restart Buttons Component ✅ MOSTLY COMPLETE

- ✅ Lives in `src/ui/components/restart_buttons.zig`
- ✅ Component owns single shared "Restart" label texture
- ✅ Hit-testing is internal to component (not in main.zig)
- ✅ Pushes `UiAction.RestartSession` on click
- ✅ No `restart_button_texture` fields in `SessionState`

### Section 8: Cleanup ✅ MOSTLY COMPLETE

**8.1 UI types removed from app_state.zig:** ✅
- No `ToastNotification`, `HelpButtonAnimation`, `EscapeIndicator` types
- UI constants moved to respective components

**8.2 UI render functions removed from renderer.zig:** ✅
- No `renderToastNotification`, `renderHelpButton`, `renderEscapeIndicator`
- No `isPointInRect`, `getRestartButtonRect` utility functions

---

## Deviations and Technical Debt

### 1. CWD Bar ✅ REMOVED

**Previous Issue:** The CWD bar stored UI textures directly on `SessionState`, violating the "no UI state on sessions" invariant.

**Current Resolution:** The grid no longer renders a CWD bar. Working directory tracking remains in `SessionState` for persistence, restore, remote terminal, and worktree workflows, but the UI snapshot no longer carries per-session directory display fields.

**Changes made:**
- Removed `src/ui/components/cwd_bar.zig` and its sizing metrics
- Removed CWD bar registration from the UI root setup
- Removed grid height reservation from runtime sizing and renderer draw bounds
- Removed per-session directory display fields from `SessionUiInfo`

### 2. Renderer-Owned Cache ✅ RESOLVED

**Location:** `src/render/renderer.zig` (`RenderCache`)

**Change:** The grid render cache now lives in the renderer as a per-session cache table, and `SessionState` exposes a `render_epoch` counter for invalidation. This keeps render resources owned by the renderer while preserving scene/UI separation.

---

## Extensions Beyond Original Plan

The following components were added after the plan was written, following the established patterns:

| Component | Purpose | Follows Pattern |
|-----------|---------|-----------------|
| `QuitConfirmComponent` | Quit confirmation dialog | ✅ |
| `WorktreeOverlayComponent` | Git worktree picker | ✅ |
| `GlobalShortcutsComponent` | Global shortcuts (⌘,) | ✅ |
| `PillGroupComponent` | Coordinates multiple pill overlays | ✅ |
| `ConfirmDialogComponent` | Generic confirmation modal | ✅ |
| `HotkeyIndicatorComponent` | Visual hotkey feedback | ✅ |
| `MarqueeLabelComponent` | Reusable scrolling text | ✅ |
| `ButtonComponent` | Reusable styled button | ✅ |
| `ExpandingOverlayComponent` | Shared animation state helper | ✅ |
| `FirstFrameGuard` | Idle throttling transition helper | ✅ |

These align with Section 10's prediction: "Once the framework exists, these become clean additions (no main.zig edits)."

---

## Recommendations

### Completed

1. ✅ **Remove CWD bar display chrome** - DONE
   - Removed the grid CWD bar UI component
   - Kept working directory persistence and focused-cwd workflows intact
   - Removed per-session directory display fields from `SessionUiInfo`

### Future Considerations

1. **Document the scene vs UI texture distinction**
   - Terminal content caches = renderer-owned (`RenderCache`)
   - Text/label textures for bars/overlays = UI (should be in components)

2. **Consider unifying pill overlays**
   - `HelpOverlayComponent` and `WorktreeOverlayComponent` share similar patterns
   - Could potentially share more code via `ExpandingOverlay`

---

## Conclusion

The engine plan has been implemented successfully with 100% adherence. The CWD bar deviation has been resolved by removing the grid directory chrome while keeping working directory state in the session layer.
