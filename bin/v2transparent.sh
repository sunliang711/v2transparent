#!/bin/bash
rpath="$(readlink ${BASH_SOURCE})"
if [ -z "$rpath" ];then
    rpath=${BASH_SOURCE}
fi
this="$(cd $(dirname $rpath) && pwd)"
cd "$this"
export PATH=$PATH:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

user="${SUDO_USER:-$(whoami)}"
home="$(eval echo ~$user)"

# export TERM=xterm-256color

# Use colors, but only if connected to a terminal, and that terminal
# supports them.
if which tput >/dev/null 2>&1; then
  ncolors=$(tput colors 2>/dev/null)
fi
if [ -t 1 ] && [ -n "$ncolors" ] && [ "$ncolors" -ge 8 ]; then
    RED="$(tput setaf 1)"
    GREEN="$(tput setaf 2)"
    YELLOW="$(tput setaf 3)"
    BLUE="$(tput setaf 4)"
            CYAN="$(tput setaf 5)"
    BOLD="$(tput bold)"
    NORMAL="$(tput sgr0)"
else
    RED=""
    GREEN=""
    YELLOW=""
            CYAN=""
    BLUE=""
    BOLD=""
    NORMAL=""
fi
_err(){
    echo "$*" >&2
}

function _runAsRoot(){
    verbose=0
    while getopts ":v" opt;do
        case "$opt" in
            v)
                verbose=1
                ;;
            \?)
                echo "Unknown option: \"$OPTARG\""
                exit 1
                ;;
        esac
    done
    shift $((OPTIND-1))
    cmd="$@"
    if [ -z "$cmd" ];then
        echo "${red}Need cmd${reset}"
        exit 1
    fi

    if [ "$verbose" -eq 1 ];then
        echo "run cmd:\"${red}$cmd${reset}\" as root."
    fi

    if (($EUID==0));then
        sh -c "$cmd"
    else
        if ! command -v sudo >/dev/null 2>&1;then
            echo "Need sudo cmd"
            exit 1
        fi
        sudo sh -c "$cmd"
    fi
}

rootID=0
function _root(){
    if [ ${EUID} -ne ${rootID} ];then
        echo "Need run as root!"
        exit 1
    fi
}

editor=vi
if command -v vim >/dev/null 2>&1;then
    editor=vim
fi
if command -v nvim >/dev/null 2>&1;then
    editor=nvim
fi
###############################################################################
# write your code below (just define function[s])
# function is hidden when begin with '_'
###############################################################################
# TODO

mark=255
dekodemoPort=12345
tableName=V2_TRANSPARENT

iptables=
if command -v iptables >/dev/null 2>&1;then
    iptables="iptables"
fi
# if command -v iptables-legacy >/dev/null 2>&1;then
#     iptables="iptables-legacy"
# fi

start(){
    # _set
    # ../Linux/v2ray -c ./transparent.json

    _runAsRoot "systemctl start v2transparent"
}

stop(){
    _runAsRoot "systemctl stop v2transparent"
}

restart(){
    stop
    start
}

log(){
    cd ${this}
    local accessFile=$(perl -lne 'print $1 if /"access":\s*"([^"]+)"/' ../v2transparent.json)
    _runAsRoot "tail -f ${accessFile}"
}


_set(){
    _root
    local next_file=${this}/../next_file
    local next_address="$(awk -F: '{print $1}' ${next_file})"
    local next_port="$(awk -F: '{print $2}' ${next_file})"
    echo "next_address: ${next_address}"
    echo "next_port: ${next_port}"

    while true;do
        echo "Wait next address woring..."
        if curl -m 3 -x socks5://${next_address}:${next_port} google.com >/dev/null 2>&1;then
            break
        fi
        sleep 2
    done
    echo "Next address is working now..."

    # sysctl -w net.ipv4.ip_forward=1
    echo "Found ${iptables}"
    if [ -z "${iptables}" ];then
        _err "Not find iptables command."
        return 1
    fi

    if ! ${iptables} -t nat -L | grep -q "Chain ${v2transparent}";then
        echo "Already exist,skip." >&2
        return 0
    fi
    ${iptables} -t nat -N ${tableName}
    # Ignore your V2Ray outbound traffic
    # It's very IMPORTANT, just be careful.
    local markHex="$(printf "0x%x" ${mark})"
    ${iptables} -t nat -A ${tableName} -p tcp -j RETURN -m mark --mark ${markHex}
    # Ignore LANs and any other addresses you'd like to bypass the proxy
    # See Wikipedia and RFC5735 for full list of reserved networks.
    ${iptables} -t nat -A ${tableName} -d 0.0.0.0/8 -j RETURN
    ${iptables} -t nat -A ${tableName} -d 10.0.0.0/8 -j RETURN
    ${iptables} -t nat -A ${tableName} -d 127.0.0.0/8 -j RETURN
    ${iptables} -t nat -A ${tableName} -d 169.254.0.0/16 -j RETURN
    ${iptables} -t nat -A ${tableName} -d 172.16.0.0/12 -j RETURN
    ${iptables} -t nat -A ${tableName} -d 192.168.0.0/16 -j RETURN
    ${iptables} -t nat -A ${tableName} -d 224.0.0.0/4 -j RETURN
    ${iptables} -t nat -A ${tableName} -d 240.0.0.0/4 -j RETURN
    # Anything else should be redirected to Dokodemo-door's local port
    ${iptables} -t nat -A ${tableName} -p tcp -j REDIRECT --to-ports ${dekodemoPort}

    # apply redirect for traffic forworded by this proxy
    ${iptables} -t nat -A PREROUTING  -p tcp -j ${tableName}
    # apply redirect for proxy itself
    ${iptables} -t nat -A OUTPUT -p tcp -j ${tableName}
}

_clear(){
    _root
    # sysctl -w net.ipv4.ip_forward=0
    echo "Found ${iptables}"
    if [ -z "${iptables}" ];then
        _err "Not find iptables command."
        return 1
    fi

    # remove reference
    ${iptables} -t nat -D PREROUTING -p tcp -j ${tableName}
    # remove reference
    ${iptables} -t nat -D OUTPUT -p tcp -j ${tableName}

    ${iptables} -t nat -F ${tableName}
    ${iptables} -t nat -X ${tableName}


}

config(){
    local cfg=${this}/../v2transparent.json
    local before="$(stat ${cfg} | grep 'Modify')"
    ${editor} ${cfg}
    local after="$(stat ${cfg} | grep 'Modify')"

    if [ "${before}" != "${after}" ];then
        echo "Restart service..."
        restart
    else
        echo "Config file not changed,do nothing."
    fi

}

em(){
    $editor $0
}

###############################################################################
# write your code above
###############################################################################
function _help(){
    cat<<EOF2
Usage: $(basename $0) ${bold}CMD${reset}

${bold}CMD${reset}:
EOF2
    # perl -lne 'print "\t$1" if /^\s*(\w+)\(\)\{$/' $(basename ${BASH_SOURCE})
    # perl -lne 'print "\t$2" if /^\s*(function)?\s*(\w+)\(\)\{$/' $(basename ${BASH_SOURCE}) | grep -v '^\t_'
    perl -lne 'print "\t$2" if /^\s*(function)?\s*(\w+)\(\)\{$/' $(basename ${BASH_SOURCE}) | perl -lne "print if /^\t[^_]/"
}

function _loadENV(){
    if [ -z "$INIT_HTTP_PROXY" ];then
        echo "INIT_HTTP_PROXY is empty"
        echo -n "Enter http proxy: (if you need) "
        read INIT_HTTP_PROXY
    fi
    if [ -n "$INIT_HTTP_PROXY" ];then
        echo "set http proxy to $INIT_HTTP_PROXY"
        export http_proxy=$INIT_HTTP_PROXY
        export https_proxy=$INIT_HTTP_PROXY
        export HTTP_PROXY=$INIT_HTTP_PROXY
        export HTTPS_PROXY=$INIT_HTTP_PROXY
        git config --global http.proxy $INIT_HTTP_PROXY
        git config --global https.proxy $INIT_HTTP_PROXY
    else
        echo "No use http proxy"
    fi
}

function _unloadENV(){
    if [ -n "$https_proxy" ];then
        unset http_proxy
        unset https_proxy
        unset HTTP_PROXY
        unset HTTPS_PROXY
        git config --global --unset-all http.proxy
        git config --global --unset-all https.proxy
    fi
}


case "$1" in
     ""|-h|--help|help)
        _help
        ;;
    *)
        "$@"
esac
