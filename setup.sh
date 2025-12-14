#!/bin/bash

# Function to generate random string
random() {
    tr </dev/urandom -dc A-Za-z0-9 | head -c5
    echo
}

# Define an array for hex characters
array=(1 2 3 4 5 6 7 8 9 0 a b c d e f)

# Function to generate a 64-bit address
gen64() {
    ip64() {
        echo "${array[$RANDOM % 16]}${array[$RANDOM % 16]}${array[$RANDOM % 16]}${array[$RANDOM % 16]}"
    }
    echo "$1:$(ip64):$(ip64):$(ip64):$(ip64)"
}

# Install 3proxy and required packages
install_3proxy() {
    echo "Installing 3proxy and required packages..."
    
    sudo apt-get update -y
    sudo apt-get install -y build-essential gcc make libssl-dev zlib1g-dev curl iptables zip wget
    
    if [ $? -ne 0 ]; then
        echo "Error: Failed to install dependencies!"
        exit 1
    fi

    # Download latest 3proxy (0.9.5)
    URL="https://github.com/3proxy/3proxy/archive/refs/tags/0.9.5.tar.gz"
    wget -qO- $URL | tar -xzvf -
    
    if [ $? -ne 0 ]; then
        echo "Error: Failed to download 3proxy!"
        exit 1
    fi
    
    cd 3proxy-0.9.5 || exit 1

    echo "Compiling 3proxy..."
    make -f Makefile.Linux
    
    if [ ! -f src/3proxy ]; then
        echo "Error: 3proxy binary not found. Compilation failed!"
        exit 1
    fi

    # Install binaries and directories
    sudo mkdir -p /usr/local/etc/3proxy/{bin,logs,stat}
    sudo cp src/3proxy /usr/local/etc/3proxy/bin/
    cd $WORKDIR || exit 1
}

# Generate 3proxy configuration
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

# Generate proxy file for users
gen_proxy_file_for_user() {
    cat > proxy.txt <<EOF
$(awk -F "/" '{print $3 ":" $4 ":" $1 ":" $2 }' ${WORKDATA})
EOF
}

# Upload proxy file
upload_proxy() {
    local PASS=$(random)
    zip --password $PASS proxy.zip proxy.txt
    URL=$(curl -s --upload-file proxy.zip https://transfer.sh/proxy.zip)

    echo "Proxy is ready! Format IP:PORT:LOGIN:PASS"
    echo "Download zip archive from: ${URL}"
    echo "Password: ${PASS}"
}

# Generate data for proxies
gen_data() {
    seq $FIRST_PORT $LAST_PORT | while read port; do
        echo "usr$(random)/pass$(random)/$IP4/$port/$(gen64 $IP6)"
    done
}

# Generate iptables rules
gen_iptables() {
    awk -F "/" '{print "iptables -I INPUT -p tcp --dport " $4 " -m state --state NEW -j ACCEPT"}' ${WORKDATA}
}

# Generate ifconfig configuration (changed to ens3)
gen_ifconfig() {
    awk -F "/" '{print "ip -6 addr add " $5 "/64 dev ens3"}' ${WORKDATA}
}

# Working directory
echo "Working folder = /home/proxy-installer"
WORKDIR="/home/proxy-installer"
WORKDATA="${WORKDIR}/data.txt"
mkdir -p $WORKDIR && cd $WORKDIR || exit 1

# Get public IPs
IP4=$(curl -4 -s icanhazip.com)
if [ -z "$IP4" ]; then
    echo "Error: Cannot get IPv4 address!"
    exit 1
fi

IP6=$(curl -6 -s icanhazip.com | cut -f1-4 -d':')
if [ -z "$IP6" ]; then
    echo "Warning: Cannot get IPv6 prefix, IPv6 proxies may not work properly."
    IP6="fc00"  # fallback, but likely won't work
fi

echo "Internal IPv4 = ${IP4}. External IPv6 prefix = ${IP6}"

# Ask for number of proxies
echo "How many proxies do you want to create? (Example: 500)"
read COUNT

if ! [[ "$COUNT" =~ ^[0-9]+$ ]] || [ "$COUNT" -le 0 ]; then
    echo "Invalid number!"
    exit 1
fi

FIRST_PORT=10000
LAST_PORT=$(($FIRST_PORT + $COUNT - 1))

# Generate files
gen_data > $WORKDATA
gen_iptables > $WORKDIR/boot_iptables.sh
gen_ifconfig > $WORKDIR/boot_ifconfig.sh
chmod +x $WORKDIR/boot_*.sh

# Install 3proxy
install_3proxy

# Create systemd service
cat > /etc/systemd/system/proxy-setup.service <<EOF
[Unit]
Description=Proxy Setup Service
After=network.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/bash /home/proxy-installer/boot_iptables.sh
ExecStart=/bin/bash /home/proxy-installer/boot_ifconfig.sh
ExecStart=/usr/local/etc/3proxy/bin/3proxy /usr/local/etc/3proxy/3proxy.cfg

[Install]
WantedBy=multi-user.target
EOF

# Better: separate service for 3proxy
cat > /etc/systemd/system/3proxy.service <<EOF
[Unit]
Description=3proxy Proxy Server
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/etc/3proxy/bin/3proxy /usr/local/etc/3proxy/3proxy.cfg
Restart=on-failure
User=root
WorkingDirectory=/usr/local/etc/3proxy

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable 3proxy.service

# Apply iptables and IPv6 now
sudo bash $WORKDIR/boot_iptables.sh
sudo bash $WORKDIR/boot_ifconfig.sh

# Generate config and start
gen_3proxy > /usr/local/etc/3proxy/3proxy.cfg
gen_proxy_file_for_user
upload_proxy

sudo systemctl start 3proxy.service

echo "Installation completed! Proxies are running."
