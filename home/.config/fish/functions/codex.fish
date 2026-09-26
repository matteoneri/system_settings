# Codex CLI account switch: the fish port of codex() in ~/.zshrc -- keep the
# two in step, and in step with claude.fish. codex keeps account, history,
# config and sessions under $CODEX_HOME (~/.codex-own vs ~/.codex-fna);
# ~/.codex is a symlink to the OWN home for a codex started outside this
# function.
function codex --description 'Codex CLI, account chosen by flag, project directory or prompt'
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
        echo "Codex: using "(string upper $account)" account"
    else
        echo "Account: [1] FNA (default)  [2] OWN"
        read --local --nchars 1 --prompt-str '' choice
        if test "$choice" = 2
            set account own
        else
            set account fna
        end
    end

    CODEX_HOME=$HOME/.codex-$account command codex $args
end
