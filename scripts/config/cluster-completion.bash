#!/bin/bash
# Bash completion for cluster.sh script

_cluster_completion() {
    local cur prev opts main_commands controller_subcommands chainlet_subcommands chainlets_subcommands validator_subcommands
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"

    # Available main commands
    main_commands="controller chainlet chainlets ssc validator install-completion"
    
    # Controller subcommands
    controller_subcommands="down up restart"
    
    # Chainlet subcommands
    chainlet_subcommands="restart redeploy wipe logs status height expand-pvc"
    
    # Chainlets subcommands
    chainlets_subcommands="status redeploy"

    # SSC subcommands
    ssc_subcommands="status"

    # Validator subcommands
    validator_subcommands="unjail status"
    
    # Available options
    opts="--kubeconfig -h --help"

    # Handle --kubeconfig argument completion
    if [[ ${prev} == "--kubeconfig" ]]; then
        # Complete with files (kubeconfig files)
        COMPREPLY=($(compgen -f "${cur}"))
        return 0
    fi

    # Find the main command in the current command line
    local main_cmd=""
    local main_cmd_index=0
    for ((i=1; i<${#COMP_WORDS[@]}; i++)); do
        if [[ " ${main_commands} " =~ " ${COMP_WORDS[i]} " ]]; then
            main_cmd="${COMP_WORDS[i]}"
            main_cmd_index=$i
            break
        fi
    done

    # Handle command-specific completions based on context
    case "${main_cmd}" in
        controller)
            # If we're right after 'controller', suggest subcommands
            if [[ ${COMP_CWORD} -eq $((main_cmd_index + 1)) ]]; then
                COMPREPLY=($(compgen -W "${controller_subcommands} -h --help help" -- "${cur}"))
                return 0
            fi
            ;;
        chainlet)
            # If we're right after 'chainlet', suggest subcommands
            if [[ ${COMP_CWORD} -eq $((main_cmd_index + 1)) ]]; then
                COMPREPLY=($(compgen -W "${chainlet_subcommands} -h --help help" -- "${cur}"))
                return 0
            fi
            
            # Handle chainlet subcommand argument completion
            local chainlet_subcmd="${COMP_WORDS[$((main_cmd_index + 1))]}"
            case "${chainlet_subcmd}" in
                restart|redeploy|wipe|logs|status|height|expand-pvc)
                    # For chainlet commands that need identifiers, complete with both namespaces and chainids
                    if [[ ${COMP_CWORD} -eq $((main_cmd_index + 2)) ]]; then
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
                    fi
                    ;;
            esac
            ;;
        chainlets)
            # If we're right after 'chainlets', suggest subcommands
            if [[ ${COMP_CWORD} -eq $((main_cmd_index + 1)) ]]; then
                COMPREPLY=($(compgen -W "${chainlets_subcommands} -h --help help" -- "${cur}"))
                return 0
            fi
            ;;
        ssc)
            # If we're right after 'ssc', suggest subcommands
            if [[ ${COMP_CWORD} -eq $((main_cmd_index + 1)) ]]; then
                COMPREPLY=($(compgen -W "${ssc_subcommands} -h --help help" -- "${cur}"))
                return 0
            fi
            ;;
        validator)
            # If we're right after 'validator', suggest subcommands
            if [[ ${COMP_CWORD} -eq $((main_cmd_index + 1)) ]]; then
                COMPREPLY=($(compgen -W "${validator_subcommands} -h --help help" -- "${cur}"))
                return 0
            fi

            # Handle validator subcommand argument completion
            local validator_subcmd="${COMP_WORDS[$((main_cmd_index + 1))]}"
            case "${validator_subcmd}" in
                unjail)
                    # For validator commands that need identifiers, complete with both namespaces and chainids
                    if [[ ${COMP_CWORD} -eq $((main_cmd_index + 2)) ]]; then
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
                    fi
                    ;;
            esac
            ;;
    esac

    # If we're completing the first argument (after script name and options)
    if [[ ${COMP_CWORD} -eq 1 ]] || [[ -z "${main_cmd}" ]]; then
        # Complete with options and main commands
        COMPREPLY=($(compgen -W "${opts} ${main_commands}" -- "${cur}"))
        return 0
    fi

    return 0
}

# Register the completion function
complete -F _cluster_completion cluster.sh

# Also register for common ways the script might be called
complete -F _cluster_completion ./cluster.sh
complete -F _cluster_completion scripts/cluster.sh
complete -F _cluster_completion ./scripts/cluster.sh
