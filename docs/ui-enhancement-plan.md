# UI Enhancement Plan for Worth

Based on analysis of current Worth UI implementation against TermUI best practices.

## Current State Assessment

**Strengths:**
- ✅ Proper Elm Architecture implementation
- ✅ Good modular component structure  
- ✅ Correct event handling for basic interactions
- ✅ Efficient rendering approach

**Improvement Opportunities:**
- ❌ Underutilizing TermUI widget library
- ❌ Limited styling and theming capabilities
- ❌ Async operations using raw processes instead of Commands
- ❌ Missing form validation and user feedback
- ❌ Limited accessibility features
- ❌ No automated test coverage for UI

## Enhancement Goals

1. **Leverage TermUI Widgets** - Replace custom implementations with built-in widgets where appropriate
2. **Enhance Styling & Theming** - Use TermUI's full styling capabilities
3. **Implement Command Pattern** - Replace polling with TermUI Commands for async operations
4. **Improve User Feedback** - Add loading states, validation, and notifications
5. **Increase Accessibility** - Better focus management and keyboard navigation
6. **Add Test Coverage** - Unit and integration tests for UI components

## Progress Tracking

| Task | Description | Status | Priority |
|------|-------------|--------|----------|
| 1. Replace Sidebar Tabs with TermUI Tabs Widget | Convert custom tab implementation to use TermUI's Tabs widget for better keyboard navigation and styling | ⏳ Pending | High |
| 2. Enhance Status Indicators with Semantic Colors | Use TermUI's semantic colors (success/error/warning/info) for status indicators | ⏳ Pending | Medium |
| 3. Implement Command Pattern for Async Operations | Replace Process.send_after polling with TermUI Commands for model checking and event draining | ⏳ Pending | High |
| 4. Add Loading States for LLM Operations | Show spinner/progress during AI processing and data fetching | ⏳ Pending | High |
| 5. Implement Input Validation and Error States | Add validation for command input with inline error feedback | ⏳ Pending | Medium |
| 6. Add Confirmation Dialogs for Destructive Actions | Use TermUI Dialog widgets for clear history, reset workspace, etc. | ⏳ Pending | Medium |
| 7. Improve Focus Management and Visual Indicators | Enhance keyboard navigation with better focus visibility | ⏳ Pending | Medium |
| 8. Add Toast Notifications for Non-blocking Feedback | Implement temporary notifications for success/error messages | ⏳ Pending | Low |
| 9. Create Unit Tests for Event Handling | Test event_to_msg functions for all UI components | ⏳ Pending | High |
| 10. Create Integration Tests for User Flows | Test complete user interactions (sending messages, switching modes, etc.) | ⏳ Pending | High |

## Detailed Implementation Plan

### Task 1: Replace Sidebar Tabs with TermUI Tabs Widget

**Current Implementation:**
- Custom tab handling in Worth.UI.Root with manual visibility toggling
- Keyboard shortcuts (1-5) to switch tabs
- Manual sidebar rendering based on state

**Enhanced Implementation:**
- Use TermUI.Tabs widget with labeled tabs
- Automatic keyboard navigation (left/right arrows)
- Better visual styling with TermUI theming
- Reduced custom state management

**Files to Modify:**
- lib/worth/ui/root.ex (remove custom tab handling, add Tabs widget)
- Create new sidebar tab components or enhance existing ones

### Task 2: Enhance Status Indicators

**Current Implementation:**
- Basic text styling in Worth.UI.Header
- Limited color usage through Theme.style_for

**Enhanced Implementation:**
- Use semantic colors: green for idle, yellow for processing, red for error
- Add subtle animations or pulsating effects for active states
- Consider using Gauge widget for cost/turn progress visualization

**Files to Modify:**
- lib/worth/ui/header.ex
- lib/worth/ui/theme.ex

### Task 3: Implement Command Pattern

**Current Implementation:**
- Process.send_after for periodic checking (:check_events, :refresh_model)
- Manual process management

**Enhanced Implementation:**
- Use TermUI.Commands for timer-based operations
- Command.timer(0, :do_work) pattern for immediate async tasks
- Better integration with Elm architecture update cycle

**Files to Modify:**
- lib/worth/ui/root.ex (replace send_after with Commands)
- Update update/2 to handle Command messages

### Task 4: Add Loading States

**Current Implementation:**
- No visual indication during LLM processing
- Status text only changes (:idle, :running)

**Enhanced Implementation:**
- Spinner animation during AI processing
- Progress bars for long-running operations
- Skeleton loading states for chat messages

**Files to Modify:**
- lib/worth/ui/root.ex (add loading state tracking)
- lib/worth/ui/chat.ex (add loading message rendering)
- lib/worth/ui/header.ex (enhance status indicator)

### Task 5: Implement Input Validation

**Current Implementation:**
- Basic input handling without validation
- Commands parsed without client-side validation

**Enhanced Implementation:**
- Real-time validation as user types
- Inline error messages for invalid commands
- Autocomplete suggestions for known commands
- Visual feedback for valid/invalid input

**Files to Modify:**
- lib/worth/ui/input.ex
- lib/worth/ui/commands.ex (add validation helpers)

### Task 6: Add Confirmation Dialogs

**Current Implementation:**
- Direct execution of destructive actions
- No confirmation prompts

**Enhanced Implementation:**
- TermUI.Dialog or AlertDialog for confirmation
- Clear action labeling (Cancel/Confirm)
- Keyboard navigation (Enter to confirm, Escape to cancel)

**Files to Modify:**
- lib/worth/ui/root.ex (add confirmation state)
- Create dialog components or use existing ones

## Success Criteria

1. All TermUI widgets used appropriately (Tabs, TextInput, Dialog, Toast, Gauge, etc.)
2. Consistent styling using TermUI's theming system
3. Async operations handled through Commands pattern
4. Clear user feedback for all operations (loading, success, error)
5. Full keyboard navigation with visible focus indicators
6. Automated test coverage for event handling and state transitions
7. Maintained or improved performance characteristics

## Next Steps

Begin with Task 1 (Sidebar Tabs enhancement) as it provides immediate visual improvement and demonstrates TermUI widget integration.

Each task should be implemented as a separate commit with corresponding tests where applicable.