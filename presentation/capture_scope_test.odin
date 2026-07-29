package presentation

import "core:strings"
import "core:testing"

// The naming rule that decides which directory a capture writes into. It is the half of
// scoping that can be tested without a window or a checkout: reading HEAD needs a working
// tree, and the shots need a framebuffer, but turning HEAD's text into a directory name is
// a pure function of a string.
//
// `scripts/shot.py` implements the same rule so it can resolve a bare shot name against the
// current scope. These cases are the contract the two share.

@(test)
capture_scope_names_the_branch :: proc(t: ^testing.T) {
	scope := capture_scope_from_head("ref: refs/heads/main\n")
	defer delete(scope)
	testing.expectf(t, scope == "main", "expected main, got %q", scope)
}

@(test)
capture_scope_flattens_a_branch_with_a_path_in_it :: proc(t: ^testing.T) {
	scope := capture_scope_from_head("ref: refs/heads/effort/design-loop\n")
	defer delete(scope)
	testing.expectf(t, scope == "effort-design-loop", "expected effort-design-loop, got %q", scope)
}

// One path segment, whatever the branch is called: a scope that split into directories
// would put a shot somewhere `shot.py` does not look for it.
@(test)
capture_scope_is_always_one_path_segment :: proc(t: ^testing.T) {
	for branch in ([?]string {
			"feature/deep/nested/name",
			"fix\\windows-style",
			"release 1.0",
			"weird:name*with?chars",
		}) {
		head := strings.concatenate({"ref: refs/heads/", branch})
		defer delete(head)
		scope := capture_scope_from_head(head)
		defer delete(scope)

		testing.expectf(t, scope != "", "%s should scope to something", branch)
		testing.expectf(t, !strings.contains(scope, "/"), "%s scoped to %q, which is two directories", branch, scope)
		testing.expectf(t, !strings.contains(scope, "\\"), "%s scoped to %q, which is two directories", branch, scope)
		testing.expectf(t, len(scope) == len(branch), "%s scoped to %q, a different length", branch, scope)
	}
}

// Two branches must not share a directory, or a capture on one still overwrites the other's
// shots — which is the whole thing scoping exists to prevent.
@(test)
capture_scope_keeps_different_branches_apart :: proc(t: ^testing.T) {
	seen: map[string]string
	defer delete(seen)

	for branch in ([?]string{"main", "effort/design-loop", "effort/model-leverage", "design-loop"}) {
		head := strings.concatenate({"ref: refs/heads/", branch})
		defer delete(head)
		scope := capture_scope_from_head(head)

		other, clash := seen[scope]
		testing.expectf(t, !clash, "%s and %s both scope to %q", branch, other, scope)
		seen[scope] = branch
	}

	for scope in seen {
		delete(scope)
	}
}

@(test)
capture_scope_names_a_detached_head_by_its_commit :: proc(t: ^testing.T) {
	scope := capture_scope_from_head("06a2cf8f0a0ebff80faf9cc281eb70c2bc2e6dd2\n")
	defer delete(scope)
	testing.expectf(t, scope == "detached-06a2cf8", "expected detached-06a2cf8, got %q", scope)
}

// A HEAD that is neither a branch ref nor an object name still has to scope to something a
// capture can be written into, or the run fails for a reason that has nothing to do with
// the screens.
@(test)
capture_scope_falls_back_when_head_is_unreadable :: proc(t: ^testing.T) {
	for head in ([?]string{"", "\n", "ref: refs/heads/", "ref: refs/tags/v1", "not a head at all", "06a2cf8"}) {
		scope := capture_scope_from_head(head)
		defer delete(scope)
		testing.expectf(t, scope == CAPTURE_SCOPE_UNSCOPED, "%q should scope to %s, got %q", head, CAPTURE_SCOPE_UNSCOPED, scope)
	}
}

// The kept copy lands beside the shot it is a previous version of, so a shot and its
// before-shot differ only by the CAPTURE_PREV segment.
@(test)
capture_base_name_takes_the_file_off_either_separator :: proc(t: ^testing.T) {
	for path in ([?]string{"docs/ui/shots/main/05-build.png", "docs\\ui\\shots\\main\\05-build.png", "05-build.png"}) {
		base := capture_base_name(path)
		testing.expectf(t, base == "05-build.png", "%s named %q", path, base)
	}
}
