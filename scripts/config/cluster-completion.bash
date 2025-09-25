#!/bin/bash
# Bash completion for cluster.sh script

_cluster_completion() {
    local cur prev opts commands
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"

    # Available commands
    commands="scale-down-controller scale-up-controller restart-controller restart-chainlet redeploy-chainlet redeploy-all-chainlets logs chainlet-status expand-pvc chainlets-status install-completion"
    
    # Available options
    opts="--kubeconfig -h --help"

    # Handle --kubeconfig argument completion
    if [[ ${prev} == "--kubeconfig" ]]; then
        # Complete with files (kubeconfig files)
        COMPREPLY=($(compgen -f "${cur}"))
        return 0
    fi

    # Handle command-specific completions
    case "${prev}" in
        restart-chainlet|redeploy-chainlet|logs|chainlet-status|expand-pvc)
            # For chainlet commands, complete with both namespaces and chainids
            if command -v kubectl >/dev/null 2>&1; then
                # Get saga-* namespaces (full namespace names)
                local namespaces=$(kubectl get namespaces -o name 2>/dev/null | grep "namespace/saga-" | cut -d/ -f2 2>/dev/null)
                
                # Convert namespaces to chainids (remove saga- prefix and convert - to _)
                local chainids=""
                for ns in $namespaces; do
                    if [[ $ns == saga-* ]]; then
                        # Remove saga- prefix and convert - to _
                        local chainid="${ns#saga-}"
                        chainid="${chainid//-/_}"
                        chainids="$chainids $chainid"
                    fi
                done
                
                # Combine both namespace and chainid completions
                local all_completions="$namespaces $chainids"
                COMPREPLY=($(compgen -W "${all_completions}" -- "${cur}"))
            fi
            return 0
            ;;
    esac

    # If we're completing the first argument (after script name)
    if [[ ${COMP_CWORD} -eq 1 ]]; then
        # Complete with options and commands
        COMPREPLY=($(compgen -W "${opts} ${commands}" -- "${cur}"))
        return 0
    fi

    # If we have an option flag, complete with commands
    local has_command=false
    for word in "${COMP_WORDS[@]:1}"; do
        if [[ " ${commands} " =~ " ${word} " ]]; then
            has_command=true
            break
        fi
    done

    if [[ ${has_command} == false ]]; then
        # No command found yet, suggest commands
        COMPREPLY=($(compgen -W "${commands}" -- "${cur}"))
    fi

    return 0
}

# Register the completion function
complete -F _cluster_completion cluster.sh

# Also register for common ways the script might be called
complete -F _cluster_completion ./cluster.sh
complete -F _cluster_completion scripts/cluster.sh
complete -F _cluster_completion ./scripts/cluster.sh
