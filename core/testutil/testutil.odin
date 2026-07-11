package testutil

// SKIP_WINDOWS_ASSERT_BUG centralizes the reason behind a `when
// testutil.SKIP_WINDOWS_ASSERT_BUG { return }` guard atop tests that rely on
// testing.expect_assert: that call crashes the whole test process on this
// toolchain instead of recovering (see #35). Skip until resolved.
SKIP_WINDOWS_ASSERT_BUG :: ODIN_OS == .Windows
