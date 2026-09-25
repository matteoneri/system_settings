# shellcheck shell=bash
# lib/projects-root.sh — the per-machine projects root (PROJECTS_ROOT) and the
# @PROJECTS_ROOT@ placeholder that stands for it in repo copies of files that
# cannot read variables. Source it; sourcing only defines the functions below
# and PROJECTS_ROOT_PLACEHOLDER, and changes no shell option or file.
# Needs bash 4.4+, perl and GNU coreutils (realpath, stat, chmod --reference).
#
# Public functions (status 2 always means bad input or an I/O error):
#   projects_root_declaration_file   print the declaration file path, under $HOME
#   projects_root_resolve            print the normalised root: a non-empty
#                                    PROJECTS_ROOT wins, else the last
#                                    PROJECTS_ROOT= line of the declaration file.
#                                    On failure print one ERROR line to stderr
#                                    and return 1; the caller decides to exit.
#   projects_root_fill ROOT SRC DEST replace every @PROJECTS_ROOT@ in SRC with
#                                    ROOT, written to DEST ("-" for stdout)
#   projects_root_swap ROOT SRC DEST replace every spelling of ROOT in SRC with
#                                    @PROJECTS_ROOT@, written to DEST ("-" for
#                                    stdout; DEST may be SRC)
#   projects_root_scan ROOT FILE     return 0 when FILE holds no spelling of
#                                    ROOT; else print "LINE:text" per hit, return 1
#   projects_root_scan_placeholder FILE
#                                    return 0 when FILE holds no @PROJECTS_ROOT@;
#                                    else print "LINE:text" per hit, return 1
#
# ROOT is what projects_root_resolve printed. A file DEST is replaced only once
# complete (temp file beside it, then rename), keeps the mode cp would leave,
# and is written through a symlink. Scans fail closed: an unreadable file is
# status 2, never "clean".
#
# Spellings of ROOT (swap and scan): the absolute form, the ~/ form when ROOT is
# below $HOME, and the symlink-resolved form when it differs; scan adds the
# $HOME/ and ${HOME}/ forms. The longest spelling matches first, and only on a
# path boundary: a hit counts unless it is followed by a letter, a digit or a
# non-ASCII byte, optionally after a run of . _ - characters. So /r/WorkOld,
# /r/Work2 and /r/Work.bak never match /r/Work, while "/r/Work", /r/Work/x,
# /r/Work: and a sentence ending in /r/Work. do.

PROJECTS_ROOT_PLACEHOLDER='@PROJECTS_ROOT@'
_PROJECTS_ROOT_BOUNDARY='(?![._-]*[A-Za-z0-9\x80-\xff])'

projects_root_declaration_file() {
    printf '%s\n' "${HOME-}/.config/environment.d/50-projects-root.conf"
}

projects_root_resolve() {
    local value origin
    if [[ -n "${PROJECTS_ROOT-}" ]]; then
        value="$PROJECTS_ROOT"
        origin="exported"
    elif value="$(_projects_root_declared)"; then
        origin="declared"
    else
        _projects_root_fail "PROJECTS_ROOT is not set (neither exported nor declared)"
        return 1
    fi
    _projects_root_normalise "$(_projects_root_expand "$value")" "$origin"
}

projects_root_fill() {
    _projects_root_arity 3 $# "projects_root_fill ROOT SRC DEST" || return 2
    _projects_root_check_root "$1" || return 2
    _projects_root_emit "$2" "$3" \
        _projects_root_replace "$2" "$1" "" "$PROJECTS_ROOT_PLACEHOLDER"
}

projects_root_swap() {
    local spellings=()
    _projects_root_arity 3 $# "projects_root_swap ROOT SRC DEST" || return 2
    _projects_root_check_root "$1" || return 2
    mapfile -d '' -t spellings < <(_projects_root_spellings "$1" swap)
    _projects_root_emit "$2" "$3" \
        _projects_root_replace "$2" "$PROJECTS_ROOT_PLACEHOLDER" "$_PROJECTS_ROOT_BOUNDARY" "${spellings[@]}"
}

projects_root_scan() {
    local spellings=()
    _projects_root_arity 2 $# "projects_root_scan ROOT FILE" || return 2
    _projects_root_check_root "$1" || return 2
    _projects_root_readable "$2" || return 2
    mapfile -d '' -t spellings < <(_projects_root_spellings "$1" scan)
    _projects_root_find "$2" "$_PROJECTS_ROOT_BOUNDARY" "${spellings[@]}"
}

projects_root_scan_placeholder() {
    _projects_root_arity 1 $# "projects_root_scan_placeholder FILE" || return 2
    _projects_root_readable "$1" || return 2
    _projects_root_find "$1" "" "$PROJECTS_ROOT_PLACEHOLDER"
}

# ── resolution helpers ───────────────────────────────────────────

# One ERROR line: the problem, the declaration file and a neutral example
# (never a real machine's root, which would trip that machine's leak scan).
_projects_root_fail() {
    printf 'ERROR: %s. Declare it in %s with a line like PROJECTS_ROOT=${HOME}/path/to/projects (an exported PROJECTS_ROOT takes precedence over the file).\n' \
        "$1" "$(projects_root_declaration_file)" >&2
}

# Print the value of the file's last PROJECTS_ROOT= line, with surrounding
# whitespace and one pair of quotes stripped as systemd's environment.d does.
# Comment lines (# or ;) never match. Return 1 when there is no such line.
_projects_root_declared() {
    local file line value found=1
    file="$(projects_root_declaration_file)"
    [[ -r "$file" ]] || return 1
    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" =~ ^[[:space:]]*PROJECTS_ROOT[[:space:]]*=(.*)$ ]]; then
            value="${BASH_REMATCH[1]}"
            found=0
        fi
    done < "$file"
    (( found == 0 )) || return 1
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    if [[ "$value" =~ ^\"(.*)\"$ || "$value" =~ ^\'(.*)\'$ ]]; then
        value="${BASH_REMATCH[1]}"
    fi
    printf '%s\n' "$value"
}

# Expand a leading ~, $HOME or ${HOME}; ~user and $HOMEDIR stay as they are.
_projects_root_expand() {
    local value="$1" home="${HOME-}"
    case "$value" in
        '~' | '~/'*)             value="$home${value:1}" ;;
        '$HOME' | '$HOME/'*)     value="$home${value:5}" ;;
        '${HOME}' | '${HOME}/'*) value="$home${value:7}" ;;
    esac
    printf '%s\n' "$value"
}

# Print VALUE in canonical form (no trailing, doubled or dot segments; symlinks
# kept), or fail when it is relative, the filesystem root, or not a directory.
_projects_root_normalise() {
    local value="$1" origin="$2" root
    if [[ "$value" != /* ]]; then
        _projects_root_fail "PROJECTS_ROOT='$value' ($origin) is not an absolute path"
        return 1
    fi
    root="$(realpath -s -m -- "$value" 2>/dev/null)"
    if [[ -z "$root" || "$root" == / ]]; then
        _projects_root_fail "PROJECTS_ROOT='$value' ($origin) does not name a projects folder"
        return 1
    fi
    if [[ ! -d "$root" ]]; then
        _projects_root_fail "PROJECTS_ROOT='$root' ($origin) is not an existing directory"
        return 1
    fi
    printf '%s\n' "$root"
}

# ── fill, swap and scan helpers ──────────────────────────────────

_projects_root_arity() {  # <wanted> <got> <usage>
    (( $1 == $2 )) && return 0
    echo "ERROR: usage: $3" >&2
    return 2
}

# Refuse an empty, relative, trailing-slash or / root: an empty spelling would
# match at every position and wreck the file.
_projects_root_check_root() {
    [[ "$1" == /?* && "$1" != */ ]] && return 0
    echo "ERROR: projects-root: refusing root '$1'; pass the root projects_root_resolve printed" >&2
    return 2
}

_projects_root_readable() {
    [[ -f "$1" && -r "$1" ]] && return 0
    echo "ERROR: projects-root: cannot read '$1'" >&2
    return 2
}

# Print ROOT's spellings, each ending in NUL: absolute, ~/ form (ROOT strictly
# below HOME), symlink-resolved form (when it differs). MODE "scan" adds the
# $HOME/ and ${HOME}/ forms.
_projects_root_spellings() {
    local root="$1" mode="$2" home="${HOME-}" rel resolved
    home="${home%/}"
    printf '%s\0' "$root"
    if [[ -n "$home" && "$root" == "$home"/?* ]]; then
        rel="${root#"$home"/}"
        printf '%s\0' "~/$rel"
        if [[ "$mode" == scan ]]; then printf '%s\0' "\$HOME/$rel" "\${HOME}/$rel"; fi
    fi
    if resolved="$(realpath -e -- "$root" 2>/dev/null)" && [[ "$resolved" != "$root" ]]; then
        printf '%s\0' "$resolved"
    fi
}

# Print SRC with every NEEDLE followed by BOUNDARY replaced by REPLACEMENT.
# Needles are quoted with quotemeta and the replacement is inserted as is, so
# no value is ever read as regex or shell syntax.
_projects_root_replace() {  # <src> <replacement> <boundary regex> <needle>...
    perl -e '
        my ($src, $replacement, $boundary, @needles) = @ARGV;
        my $alt = join "|", map { quotemeta } sort { length($b) <=> length($a) } @needles;
        open(my $in, "<:raw", $src) or do { print STDERR "ERROR: projects-root: cannot read $src: $!\n"; exit 2 };
        my $text = do { local $/; <$in> } // "";
        $text =~ s/(?:$alt)$boundary/$replacement/g;
        binmode STDOUT;
        (print STDOUT $text and close STDOUT) or do { print STDERR "ERROR: projects-root: cannot write $src rewritten: $!\n"; exit 2 };
    ' -- "$@"
}

# Print "LINE:text" for each line of FILE holding a NEEDLE followed by
# BOUNDARY. Return 0 when none does, 1 when one does, 2 when FILE is unreadable.
_projects_root_find() {  # <file> <boundary regex> <needle>...
    perl -e '
        my ($file, $boundary, @needles) = @ARGV;
        my $alt = join "|", map { quotemeta } sort { length($b) <=> length($a) } @needles;
        my $re = qr/(?:$alt)$boundary/;
        open(my $in, "<:raw", $file) or do { print STDERR "ERROR: projects-root: cannot read $file: $!\n"; exit 2 };
        my $found = 0;
        while (my $line = <$in>) {
            next unless $line =~ $re;
            $line =~ s/\r?\n\z//;
            print "$.:$line\n";
            $found = 1;
        }
        exit($found ? 1 : 0);
    ' -- "$@"
}

# Run CMD... (which prints the new content of SRC) into DEST: "-" is stdout;
# otherwise a temp file beside DEST replaces it only when complete, so a
# failure leaves DEST as it was.
_projects_root_emit() {  # <src> <dest> <cmd>...
    local src="$1" dest="$2" tmp
    shift 2
    _projects_root_readable "$src" || return 2
    if [[ "$dest" == - ]]; then
        "$@"
        return
    fi
    if [[ -L "$dest" ]]; then
        dest="$(readlink -f -- "$dest")" || return 2
    fi
    tmp="$(mktemp -- "$(dirname -- "$dest")/.$(basename -- "$dest").XXXXXX")" || return 2
    if "$@" > "$tmp" && _projects_root_copy_mode "$tmp" "$src" "$dest" && mv -f -- "$tmp" "$dest"; then
        return 0
    fi
    rm -f -- "$tmp"
    echo "ERROR: projects-root: could not write $dest from $src; $dest is unchanged" >&2
    return 2
}

# Give TMP the mode cp would leave: DEST's own when it exists, else SRC's
# minus the umask.
_projects_root_copy_mode() {  # <tmp> <src> <dest>
    local tmp="$1" src="$2" dest="$3" mode mask
    if [[ -e "$dest" ]]; then
        chmod --reference="$dest" -- "$tmp"
        return
    fi
    mode="$(stat -c '%a' -- "$src")" || return 1
    mask="$(umask)"
    chmod "$(printf '%o' $(( 8#$mode & ~8#$mask )))" -- "$tmp"
}
