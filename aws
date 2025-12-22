#!/bin/bash
set -e

### CONFIG ###
WORKDIR="/home/proxy-installer"
WORKDATA="${WORKDIR}/data.txt"
PROXY_BIN="/usr/local/etc/3proxy/bin/3proxy"
PROXY_CFG="/usr/local/etc/3proxy/3proxy.cfg"

### RANDOM ###
random() {
    tr </dev/urandom -dc A-Za-z0-9 | head -c5
    echo
}

array=(1 2 3 4 5 6 7 8 9 0 a b c d e f)

gen64() {
    ip64() {
        echo "${array[$RANDOM % 16]}${array[$RANDOM % 16]}${array[$RANDOM % 16]}${array[$RANDOM % 16]}"
    }
    echo "$1:$(ip64):$(ip64):$(ip64):$(ip64)"
}

### CHECK ROOT ###
if [ "$EUID" -ne 0 ]; then
    echo "❌ Run as root"
    exit 1
fi

### INSTALL DEPENDENCY ###
echo "📦 Installing packages..."
yum -y install gcc net-tools iproute bsdtar zip curl make >/dev/null

### INSTALL 3PROXY ###
install_3proxy() {
    echo "⚙️ Installing 3proxy..."
    cd /usr/local/src
    curl -sL https://raw.githubusercontent.com/thien154/proxyubuntu/master/3proxy-3proxy-0.8.6.tar.gz | tar xz
    cd 3proxy-3proxy-0.8.6
    make -f Makefile.Linux

    mkdir -p /usr/local/etc/3proxy/{bin,logs,stat}
    cp src/3proxy ${PROXY_BIN}
    chmod +x ${PROXY_BIN}
}

install_3proxy

### PREPARE WORKDIR ###
mkdir -p ${WORKDIR}
cd ${WORKDIR}

### DETECT IP ###
IP4=$(curl -4 -s icanhazip.com)
IP6_SUB=$(curl -6 -s icanhazip.com | cut -d: -f1-4)
NETIF=$(ip route get 8.8.8.8 | awk '{print $5; exit}')

echo "🌐 IPv4: ${IP4}"
echo "🌐 IPv6 prefix: ${IP6_SUB}"
echo "🌐 Network interface: ${NETIF}"

### INPUT ###
read -p "How many proxy do you want to create? " COUNT

FIRST_PORT=10000
LAST_PORT=$((FIRST_PORT + COUNT - 1))

### GENERATE DATA ###
gen_data() {
    for port in $(seq $FIRST_PORT $LAST_PORT); do
        echo "usr$(random)/pass$(random)/${IP4}/${port}/$(gen64 ${IP6_SUB})"
    done
}

gen_data > ${WORKDATA}

### IPTABLES ###
cat >${WORKDIR}/boot_iptables.sh <<EOF
#!/bin/bash
$(awk -F "/" '{print "iptables -I INPUT -p tcp --dport " $4 " -j ACCEPT"}' ${WORKDATA})
EOF
chmod +x ${WORKDIR}/boot_iptables.sh

### IPV6 ASSIGN ###
cat >${WORKDIR}/boot_ifconfig.sh <<EOF
#!/bin/bash
$(awk -F "/" -v IFACE="${NETIF}" '{print "ip -6 addr add " $5 "/64 dev " IFACE}' ${WORKDATA})
EOF
chmod +x ${WORKDIR}/boot_ifconfig.sh

### 3PROXY CONFIG ###
cat >${PROXY_CFG} <<EOF
daemon
maxconn 1000
nscache 65536
timeouts 1 5 30 60 180 1800 15 60
setgid 65534
setuid 65534
flush
auth strong

users $(awk -F "/" 'BEGIN{ORS="";} {print $1 ":CL:" $2 " "}' ${WORKDATA})

$(awk -F "/" '{
print "auth strong"
print "allow " $1
print "proxy -6 -n -a -p" $4 " -i" $3 " -e" $5
print "flush"
}' ${WORKDATA})
EOF

### SYSTEMD SERVICE ###
cat >/etc/systemd/system/3proxy.service <<EOF
[Unit]
Description=3Proxy IPv6 Service
After=network.target

[Service]
Type=forking
ExecStartPre=/bin/bash ${WORKDIR}/boot_iptables.sh
ExecStartPre=/bin/bash ${WORKDIR}/boot_ifconfig.sh
ExecStart=${PROXY_BIN} ${PROXY_CFG}
ExecReload=/bin/kill -HUP \$MAINPID
LimitNOFILE=10048
Restart=always

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable 3proxy
systemctl restart 3proxy

### EXPORT PROXY FILE ###
cat >${WORKDIR}/proxy.txt <<EOF
$(awk -F "/" '{print $3 ":" $4 ":" $1 ":" $2}' ${WORKDATA})
EOF

### ZIP & UPLOAD ###
PASS=$(random)
cd ${WORKDIR}
zip --password ${PASS} proxy.zip proxy.txt >/dev/null
URL=$(curl -s --upload-file proxy.zip https://transfer.sh/proxy.zip)

echo ""
echo "✅ DONE"
echo "📁 Proxy file: ${WORKDIR}/proxy.txt"
echo "📦 Zip: ${URL}"
echo "🔐 Zip password: ${PASS}"
echo "📌 Format: IP:PORT:USER:PASS"
