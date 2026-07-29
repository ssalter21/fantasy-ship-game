package presentation

import "core:fmt"
import "core:os"
import "core:strings"

// Where a capture run's shots land, and what it does with the ones already there.
//
// A shot's filename is fixed by its screen, so without scoping every capture writes over
// whatever the last one left — including the frame a change is being measured against. Two
// rules keep that from happening, and between them a capture destroys nothing:
//
//   - Shots are scoped by the branch the working tree is on, so a capture on one branch
//     cannot touch what another branch captured. Two checkouts of this repo captured at
//     once land in different directories without either knowing about the other.
//   - Inside a scope, a shot about to be overwritten is moved into CAPTURE_PREV first. The
//     before-shot survives the run that produces the after-shot, in the shots directory,
//     with no copying out of it.
//
// `scripts/shot.py` derives the same scope from the same file and resolves bare shot names
// against it, so a name means the same screen to the tool and to the game.

@(private)
CAPTURE_ROOT :: "docs/ui/shots"

// Inside a scope: the version each shot had before the current run replaced it. One
// generation deep — the question this answers is "what did this run change", and a second
// generation would answer a question nobody asks of a regenerable file.
@(private)
CAPTURE_PREV :: "prev"

// The scope for a tree whose HEAD cannot be read. A capture outside a checkout is still
// worth taking; it simply carries no branch's name.
@(private)
CAPTURE_SCOPE_UNSCOPED :: "no-git"

@(private)
CAPTURE_HEAD_REF_PREFIX :: "ref: refs/heads/"

// A git object name is 40 lowercase hex characters (64 under SHA-256), and the shortest
// prefix git itself defaults to showing is 7.
@(private)
CAPTURE_OBJECT_NAME_MIN :: 40
@(private)
CAPTURE_OBJECT_NAME_SHORT :: 7

@(private)
capture_dir_path: string

// capture_dir is the directory this process's shots land in. Resolved on the first call and
// held for the run — capture_dir_release frees it, and capture_close is what calls that.
@(private)
capture_dir :: proc() -> string {
	if capture_dir_path == "" {
		scope := capture_scope(context.temp_allocator)
		capture_dir_path = strings.concatenate({CAPTURE_ROOT, "/", scope})
	}
	return capture_dir_path
}

@(private)
capture_dir_release :: proc() {
	delete(capture_dir_path)
	capture_dir_path = ""
}

// capture_dir_prepare makes the scope and its CAPTURE_PREV subdirectory. Reports whether
// both are there — a caller that cannot make them writes no shots, but is still worth
// letting run: raylib reports its own failure per shot, and watching the walk is half of
// what a capture run is for.
@(private)
capture_dir_prepare :: proc() -> bool {
	prev := fmt.tprintf("%s/%s", capture_dir(), CAPTURE_PREV)
	if err := os.make_directory_all(prev); err != nil {
		fmt.eprintfln("capture: could not create %s (%v)", prev, err)
		return false
	}
	return true
}

// capture_keep_previous moves the shot already at `dest` into CAPTURE_PREV, so writing over
// it does not lose it. Absent means there is nothing to keep, which is the ordinary case on
// a first capture and not a failure.
//
// The move is best-effort: a shot that cannot be set aside is reported and then overwritten,
// because refusing to capture would cost the run for the sake of a regenerable file.
@(private)
capture_keep_previous :: proc(dest: string) {
	if !os.is_file(dest) {
		return
	}
	kept := fmt.tprintf("%s/%s/%s", capture_dir(), CAPTURE_PREV, capture_base_name(dest))
	if os.is_file(kept) {
		// os.rename will not replace an existing file on Windows, and the file being
		// replaced is the generation before this one, which nothing is comparing against.
		if err := os.remove(kept); err != nil {
			fmt.eprintfln("capture: could not replace %s (%v)", kept, err)
			return
		}
	}
	if err := os.rename(dest, kept); err != nil {
		fmt.eprintfln("capture: could not keep %s as %s (%v)", dest, kept, err)
	}
}

// capture_base_name is the filename at the end of a path, for either separator — the shots
// are addressed with '/' and Windows hands back '\\'.
@(private)
capture_base_name :: proc(path: string) -> string {
	cut := max(strings.last_index_byte(path, '/'), strings.last_index_byte(path, '\\'))
	return path[cut + 1:]
}

// capture_scope names the directory this working tree captures into: its branch, with
// anything a path segment cannot carry replaced.
@(private)
capture_scope :: proc(allocator := context.allocator) -> string {
	head, readable := capture_git_head(context.temp_allocator)
	if !readable {
		return strings.clone(CAPTURE_SCOPE_UNSCOPED, allocator)
	}
	return capture_scope_from_head(head, allocator)
}

// capture_scope_from_head is the naming rule on its own, over the text of a git HEAD file:
// a symbolic ref scopes by its branch, a bare object name by its short form, and anything
// else is unreadable and scopes by CAPTURE_SCOPE_UNSCOPED.
@(private)
capture_scope_from_head :: proc(head: string, allocator := context.allocator) -> string {
	trimmed := strings.trim_space(head)
	if strings.has_prefix(trimmed, CAPTURE_HEAD_REF_PREFIX) {
		if branch := trimmed[len(CAPTURE_HEAD_REF_PREFIX):]; branch != "" {
			return capture_scope_slug(branch, allocator)
		}
	}
	if capture_object_name(trimmed) {
		return strings.concatenate({"detached-", trimmed[:CAPTURE_OBJECT_NAME_SHORT]}, allocator)
	}
	return strings.clone(CAPTURE_SCOPE_UNSCOPED, allocator)
}

// capture_scope_slug makes a branch name usable as one path segment: every byte outside the
// unreserved set becomes '-', so `effort/design-loop` scopes as `effort-design-loop`.
@(private)
capture_scope_slug :: proc(branch: string, allocator := context.allocator) -> string {
	slug := make([]byte, len(branch), allocator)
	for i in 0 ..< len(branch) {
		c := branch[i]
		switch {
		case c >= 'a' && c <= 'z', c >= 'A' && c <= 'Z', c >= '0' && c <= '9', c == '.', c == '_', c == '-':
			slug[i] = c
		case:
			slug[i] = '-'
		}
	}
	return string(slug)
}

// capture_object_name reports whether a line is a full git object name — what a detached
// HEAD holds in place of a ref.
@(private)
capture_object_name :: proc(line: string) -> bool {
	if len(line) < CAPTURE_OBJECT_NAME_MIN {
		return false
	}
	for i in 0 ..< len(line) {
		c := line[i]
		if !((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f')) {
			return false
		}
	}
	return true
}

// capture_git_head reads the working tree's HEAD, relative to the process's directory — the
// same place CAPTURE_ROOT is relative to, so the scope and the shots agree on which tree
// they belong to.
//
// `.git` is a directory in an ordinary checkout and a file naming the real git directory in
// a linked worktree. Both are followed, so a capture taken in a worktree scopes by that
// worktree's branch rather than by the main checkout's.
@(private)
capture_git_head :: proc(allocator := context.temp_allocator) -> (head: string, readable: bool) {
	GIT :: ".git"
	GITDIR_PREFIX :: "gitdir: "

	git_dir := GIT
	if os.is_file(GIT) {
		link, err := os.read_entire_file_from_path(GIT, allocator)
		if err != nil {
			return "", false
		}
		pointer := strings.trim_space(string(link))
		if !strings.has_prefix(pointer, GITDIR_PREFIX) {
			return "", false
		}
		git_dir = strings.trim_space(pointer[len(GITDIR_PREFIX):])
	}

	contents, err := os.read_entire_file_from_path(
		fmt.tprintf("%s/HEAD", git_dir),
		allocator,
	)
	if err != nil {
		return "", false
	}
	return string(contents), true
}
