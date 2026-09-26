# Claude Code account switch: the fish port of claude() in ~/.zshrc -- keep the
# two in step. --own/--fna pick the account; otherwise the project directory
# does (.../ActiveProjects/OWN or .../FNA), and anywhere else a one-key prompt
# asks, FNA by default. Each account keeps its login, settings and history in
# its own CLAUDE_CONFIG_DIR (~/.claude-own, ~/.claude-fna).
function claude --description 'Claude Code, account chosen by flag, project directory or prompt'
    set -l account
    set -l args
    for arg in $argv
        switch $arg
            case --own
                set account own
            case --fna
                set account fna
            case '*'
                set -a args $arg
        end
    end

    if test -z "$account"
        if string match -q -- '*/Projects/ActiveProjects/OWN' $PWD; or string match -q -- '*/Projects/ActiveProjects/OWN/*' $PWD
            set account own
        else if string match -q -- '*/Projects/ActiveProjects/FNA' $PWD; or string match -q -- '*/Projects/ActiveProjects/FNA/*' $PWD
            set account fna
        end
    end

    if test -n "$account"
        echo "Claude: using "(string upper $account)" account"
    else
        echo "Account: [1] FNA (default)  [2] OWN"
        read --local --nchars 1 --prompt-str '' choice
        if test "$choice" = 2
            set account own
        else
            set account fna
        end
    end

    CLAUDE_CONFIG_DIR=$HOME/.claude-$account command claude --dangerously-skip-permissions $args
end
