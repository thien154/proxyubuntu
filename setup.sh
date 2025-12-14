#!/bin/bash

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

install_3proxy() {
    echo "Installing 3proxy (latest version 0.9.5 via .deb package)..."
    
    sudo apt update -y
    sudo apt install -y curl zip wget iptables
    
    # Download và install deb package mới nhất
    wget https://github.com/3proxy/3proxy/releases/download/0.9.5/3proxy-0.9.5.x86_64.deb
    sudo dpkg -i 3proxy-0.9.5.x86_64.deb
    
    if [ $? -ne 0 ]; then
        echo "Error installing 3proxy deb package! Trying to fix dependencies..."
        sudo apt --fix-broken install -y
    fi
    
    # Tạo thư mục cần thiết (nếu chưa có)
    sudo mkdir -p /usr/local/etc/3proxy/{logs,stat}
}

gen_3proxy() {
    cat <<EOF
daemon
maxconn 1000
nscache 65536
timeouts 1 5 30 60 180 1800 15 60
setgid 65535
setuid 65535
flush
auth strong

users $(awk -F "/" 'BEGIN{ORS="";} {print $1 ":CL:" $2 " "}' ${WORKDATA})

$(awk -F "/" '{print "auth strong\n" \
"allow " $1 "\n" \
"proxy -6 -n -a -p" $4 " -i" $3 " -e"$5"\n" \
"flush\n"}' ${WORKDATA})
EOF
}

gen_proxy_file_for_user() {
    cat > proxy.txt <<EOF
$(awk -F "/" '{print $3 ":" $4 ":" $1 ":" $2 }' ${WORKDATA})
EOF
}

upload_proxy() {
    local PASS=$(random)
    zip --password $PASS proxy.zip proxy.txt
    URL=$(curl -s --upload-file proxy.zip https://transfer.sh/proxy.zip)

    echo "Proxy is ready! Format IP:PORT:LOGIN:PASS"
    echo "Download zip archive from: ${URL}"
    echo "Password: ${PASS}"
}

gen_data() {
    seq $FIRST_PORT $LAST_PORT | while read port; do
        echo "usr$(random)/pass$(random)/$IP4/$port/$(gen64 $IP6)"
    done
}

gen_iptables() {
    awk -F "/" '{print "iptables -I INPUT -p tcp --dport " $4 " -m state --state NEW -j ACCEPT"}' ${WORKDATA}
}

gen_ifconfig() {
    awk -F "/" '{print "ip -6 addr add " $5 "/64 dev ens5"}' ${WORKDATA}  # ĐÃ SỬA THÀNH ens5
}

echo "Working folder = /home/proxy-installer"
WORKDIR="/home/proxy-installer"
WORKDATA="${WORKDIR}/data.txt"
sudo mkdir -p $WORKDIR && cd $WORKDIR

IP4=$(curl -4 -s icanhazip.com)
if [ -z "$IP4" ]; then
    echo "Error: Cannot get IPv4!"
    exit 1
fi

IP6=$(curl -6 -s icanhazip.com | cut -f1-4 -d':')
if [ -z "$IP6" ]; then
    echo "Warning: No IPv6 prefix detected. IPv6 rotating may not work."
    IP6="fc00"  # fallback (không khuyến khích)
fi

echo "Internal IPv4 = ${IP4}. IPv6 prefix = ${IP6}"

echo "How many proxies do you want to create? (Example: 500)"
read COUNT

if ! [[ "$COUNT" =~ ^[0-9]+$ ]] || [ "$COUNT" -le 0 ]; then
    echo "Invalid number!"
    exit 1
fi

FIRST_PORT=10000
LAST_PORT=$(($FIRST_PORT + $COUNT - 1))

# Generate data và scripts
gen_data > $WORKDATA
gen_iptables > $WORKDIR/boot_iptables.sh
gen_ifconfig > $WORKDIR/boot_ifconfig.sh
chmod +x $WORKDIR/boot_*.sh

# Install 3proxy
install_3proxy

# Tạo systemd service cho 3proxy
sudo bash -c 'cat > /etc/systemd/system/3proxy.service <<EOF
[Unit]
Description=3Proxy Server
After=network.target

[Service]
Type=simple
ExecStartPre=/bin/bash /home/proxy-installer/boot_iptables.sh
ExecStartPre=/bin/bash /home/proxy-installer/boot_ifconfig.sh
ExecStart=/usr/bin/3proxy /usr/local/etc/3proxy/3proxy.cfg
Restart=on-failure
User=root

[Install]
WantedBy=multi-user.target
EOF'

sudo systemctl daemon-reload
sudo systemctl enable 3proxy.service

# Apply iptables và IPv6 ngay lập tức
sudo bash $WORKDIR/boot_iptables.sh
sudo bash $WORKDIR/boot_ifconfig.sh

# Generate config và start
gen_3proxy > /usr/local/etc/3proxy/3proxy.cfg
gen_proxy_file_for_user
upload_proxy

sudo systemctl start 3proxy.service

echo "Done! Proxies are up and running."
echo "Check status: sudo systemctl status 3proxy.service"
