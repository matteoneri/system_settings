# Projects root: the fish port of _projects_root_load in ~/.zshrc -- keep the
# two in step. PROJECTS_ROOT is this machine's projects folder, the one that
# holds ActiveProjects/ and system_settings/. An exported value wins; otherwise
# the last PROJECTS_ROOT= line of ~/.config/environment.d/50-projects-root.conf,
# the file the systemd user session reads too. Surrounding whitespace and one
# pair of quotes are stripped as systemd does, a leading ~, $HOME or ${HOME}
# expands, the path is normalised, and a relative path, / or a missing
# directory is refused. Unresolved, PROJECTS_ROOT is erased and an interactive
# fish gets one warning line; nothing prints anywhere else.

# Print the value of FILE's last PROJECTS_ROOT= line; 1 when it has none.
function _projects_root_declared --argument-names file
    test -r "$file"; or return 1
    set -l values (string replace -rf -- '^\s*PROJECTS_ROOT\s*=' '' <$file)
    set -q values[1]; or return 1
    set -l value (string trim -- $values[-1])
    if string match -qr -- '^(".*"|\'.*\')$' "$value"
        set value (string sub -s 2 -e -2 -- $value)
    end
    printf '%s\n' "$value"
end

# Print VALUE expanded and normalised, or print why it is refused and return 1.
# ORIGIN (exported or declared) goes into that message.
function _projects_root_normalise --argument-names value origin
    # The case pattern guarantees the prefix is the first occurrence, so a
    # literal (non-regex) replace of that first occurrence expands just it.
    switch "$value"
        case '~' '~/*'
            set value (string replace -- '~' $HOME $value)
        case '$HOME' '$HOME/*'
            set value (string replace -- '$HOME' $HOME $value)
        case '${HOME}' '${HOME}/*'
            set value (string replace -- '${HOME}' $HOME $value)
    end
    if not string match -q -- '/*' "$value"
        printf '%s\n' "PROJECTS_ROOT='$value' ($origin) is not an absolute path"
        return 1
    end
    set -l root (command realpath -s -m -- $value 2>/dev/null)
    if test -z "$root"; or test "$root" = /
        printf '%s\n' "PROJECTS_ROOT='$value' ($origin) does not name a projects folder"
        return 1
    end
    if not test -d "$root"
        printf '%s\n' "PROJECTS_ROOT='$root' ($origin) is not an existing directory"
        return 1
    end
    printf '%s\n' $root
end

function _projects_root_load --description 'Export PROJECTS_ROOT from the environment or its declaration file'
    set -l file $HOME/.config/environment.d/50-projects-root.conf
    set -l value
    set -l origin
    if test -n "$PROJECTS_ROOT"
        set value "$PROJECTS_ROOT"
        set origin exported
    else if set value (_projects_root_declared $file)
        set origin declared
    end
    set -l result 'PROJECTS_ROOT is not set (neither exported nor declared)'
    if test -n "$origin"; and set result (_projects_root_normalise "$value" $origin)
        set -gx PROJECTS_ROOT $result
        return 0
    end
    # Global scope only: the inherited value lives there, and a loader must
    # never erase a universal variable, which would outlive this session.
    set -qg PROJECTS_ROOT; and set -eg PROJECTS_ROOT
    status is-interactive; or return 0
    # Held in variables and quoted: set_color prints nothing on a dumb
    # terminal, and a bare empty substitution would shift printf's arguments.
    set -l tag_on (set_color -o yellow)
    set -l tag_off (set_color normal)
    printf '%s[projects-root]%s %s. Declare it in %s with a line like PROJECTS_ROOT=${HOME}/path/to/projects (an exported PROJECTS_ROOT takes precedence over the file).\n' \
        "$tag_on" "$tag_off" "$result" "$file" >&2
end

_projects_root_load
