#!/usr/bin/env bash
set -e

# ===============================
# REQUIRE ROOT
# ===============================
if [ "$EUID" -ne 0 ]; then
  echo "❌ Run as root"
  exit 1
fi

# ===============================
# AUTO DETECT INTERFACE
# ===============================
IFACE=$(ip -o -4 route show to default | awk '{print $5}' | head -n1)
if [ -z "$IFACE" ]; then
  echo "❌ Cannot detect network interface"
  exit 1
fi
echo "[+] Interface: $IFACE"

# ===============================
# INSTALL DEPENDENCIES
# ===============================
apt update -y
apt install -y \
  build-essential \
  wget \
  curl \
  tar \
  zip \
  iproute2 \
  libcap2-bin \
  libssl-dev \
  libpam0g-dev \
  netfilter-persistent \
  iptables-persistent

# ===============================
# UTILS
# ===============================
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

# ===============================
# BUILD & PATCH 3PROXY
# ===============================
install_3proxy() {
  echo "[+] Building 3proxy (auto patch GCC bug)"

  BUILD_DIR="/opt/3proxy-build"
  mkdir -p "$BUILD_DIR"
  cd "$BUILD_DIR"

  # 🔹 Tải source chính thức 3proxy 0.8.6
  URL="https://github.com/z3APA3A/3proxy/archive/0.8.6.tar.gz"
  wget -qO- "$URL" | tar -xz

  cd 3proxy-0.8.6

  # 🔥 FIX GCC >=10 multiple definition bug
  sed -i 's/^CFLAGS =/CFLAGS = -fcommon /' Makefile.Linux

  # Build từ thư mục gốc (không vào src/)
  make -f Makefile.Linux clean
  make -f Makefile.Linux

  mkdir -p /usr/local/etc/3proxy/{bin,logs,stat}
  cp src/3proxy /usr/local/etc/3proxy/bin/
  setcap cap_net_bind_service=+ep /usr/local/etc/3proxy/bin/3proxy
}

# ===============================
# GENERATORS
# ===============================
gen_data() {
  seq "$FIRST_PORT" "$LAST_PORT" | while read -r port; do
    echo "usr$(random)/pass$(random)/$IP4/$port/$(gen64 $IP6)"
  done
}

gen_iptables() {
  awk -F "/" '{print "iptables -I INPUT -p tcp --dport " $4 " -j ACCEPT"}' "$WORKDATA"
}

gen_ip6() {
  awk -F "/" -v iface="$IFACE" '{print "ip -6 addr add " $5 "/64 dev " iface}' "$WORKDATA"
}

gen_3proxy() {
cat <<EOF
maxconn 1000
nscache 65536
timeouts 1 5 30 60 180 1800 15 60
setgid nogroup
setuid nobody
flush
auth strong

users $(awk -F "/" 'BEGIN{ORS="";} {print $1 ":CL:" $2 " "}' "$WORKDATA")

$(awk -F "/" '{print "auth strong\nallow " $1 "\nproxy -6 -n -a -p" $4 " -i" $3 " -e"$5"\n"}' "$WORKDATA")
EOF
}

gen_proxy_file_for_user() {
  awk -F "/" '{print $3 ":" $4 ":" $1 ":" $2 }' "$WORKDATA" > proxy.txt
}

# ===============================
# SYSTEMD SERVICE
# ===============================
create_service() {
cat >/etc/systemd/system/3proxy.service <<EOF
[Unit]
Description=3Proxy Service
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/etc/3proxy/bin/3proxy /usr/local/etc/3proxy/3proxy.cfg
Restart=always
RestartSec=2
LimitNOFILE=10048

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable 3proxy
}

# ===============================
# MAIN
# ===============================
install_3proxy

WORKDIR="/home/proxy-installer"
WORKDATA="$WORKDIR/data.txt"
mkdir -p "$WORKDIR"
cd "$WORKDIR"

IP4=$(curl -4 -s icanhazip.com)
IP6=$(curl -6 -s icanhazip.com | cut -d: -f1-4)

echo "[+] IPv4: $IP4"
echo "[+] IPv6 prefix: $IP6"

read -p "How many proxy do you want to create? " COUNT

FIRST_PORT=10000
LAST_PORT=$((FIRST_PORT + COUNT - 1))

gen_data > "$WORKDATA"

gen_iptables > iptables.rules
gen_ip6 > ipv6.rules

bash iptables.rules
bash ipv6.rules
netfilter-persistent save

gen_3proxy > /usr/local/etc/3proxy/3proxy.cfg
create_service
systemctl start 3proxy

gen_proxy_file_for_user

PASS=$(random)
zip --password "$PASS" proxy.zip proxy.txt
URL=$(curl -s --upload-file proxy.zip https://transfer.sh/proxy.zip)

echo "================================="
echo "✅ DONE"
echo "Download: $URL"
echo "Password: $PASS"
echo "Format: IP:PORT:LOGIN:PASS"
echo "================================="
