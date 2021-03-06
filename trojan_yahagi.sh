#!/usr/bin/env bash
echo=echo
for cmd in echo /bin/echo; do
    $cmd > /dev/null 2>&1 || continue

    if ! $cmd -e "" | grep -qE '^-e'; then
        echo=$cmd
        break
    fi
done

CSI=$($echo -e "\033[")
CEND="${CSI}0m"
CDGREEN="${CSI}32m"
CRED="${CSI}1;31m"
CGREEN="${CSI}1;32m"
CYELLOW="${CSI}1;33m"
CBLUE="${CSI}1;34m"
CMAGENTA="${CSI}1;35m"
CCYAN="${CSI}1;36m"
CSUCCESS="$CDGREEN"
CFAILURE="$CRED"
CQUESTION="$CMAGENTA"
CWARNING="$CYELLOW"
CMSG="$CCYAN"

get_latest_release() {
    curl --silent "https://api.github.com/repos/$1/releases/latest" | # Get latest release from GitHub api
        grep '"tag_name":' | # Get tag line
        sed -E 's/.*"([^"]+)".*/\1/' # Pluck JSON value
}

if [[ -f /etc/redhat-release ]]; then
    release="centos"
elif cat /etc/issue | grep -q -E -i "raspbian|debian"; then
    release="debian"
elif cat /etc/issue | grep -q -E -i "ubuntu"; then
    release="ubuntu"
elif cat /etc/issue | grep -q -E -i "centos|red hat|redhat"; then
    release="centos"
elif cat /proc/version | grep -q -E -i "raspbian|debian"; then
    release="debian"
elif cat /proc/version | grep -q -E -i "ubuntu"; then
    release="ubuntu"
elif cat /proc/version | grep -q -E -i "centos|red hat|redhat"; then
    release="centos"
else
    echo -e "${CRED}[错误] 不支持的操作系统！${CEND}"
    exit 1
fi

echo -e "${CYELLOW}[信息] 正在更新系统中！${CEND}"
if [[ ${release} == "centos" ]]; then
    yum update -y
else
    apt update -y
fi

echo -e "${CYELLOW}[信息] 正在安装依赖中！${CEND}"
if [[ ${release} == "centos" ]]; then
    yum install -y http://rpms.famillecollet.com/enterprise/remi-release-7.rpm
    yum --enablerepo=remi install redis -y
    systemctl start redis
    yum install nano git wget curl unzip xz -y
    curl --silent --location https://rpm.nodesource.com/setup_12.x | bash -
    yum install nodejs -y
else
    apt install nano redis-server git wget curl unzip xz-utils -y
    curl -sL https://deb.nodesource.com/setup_12.x | bash -
    apt-get install nodejs -y
fi

systemctl enable redis
systemctl enable nodejs

rm -rf /opt/trojan-server
rm -f /etc/systemd/system/trojan.service
rm -f /etc/systemd/system/yahagi.service
mkdir /opt/trojan-server
mkdir /opt/trojan-server/ssl

echo -e "${CYELLOW}[信息] 正在安装Trojan-cluster中！${CEND}"
# Trojan-cluster
trojan_pkg_version=$(get_latest_release "trojan-cluster/trojan-cluster")
wget -N -O /opt/LinuxRelease.zip https://github.com/trojan-cluster/trojan-cluster/releases/download/$trojan_pkg_version/LinuxRelease.zip
unzip -o -d /opt/ /opt/LinuxRelease.zip
tar -xvf /opt/LinuxRelease/trojan-linux-amd64.tar.xz -C /opt/trojan-server
rm -f /opt/LinuxRelease.zip
rm -rf /opt/LinuxRelease

echo -e "${CYELLOW}[信息] 正在写入服务配置中！${CEND}"
echo "[Unit]" > /etc/systemd/system/trojan.service
echo "Description=Trojan" >> /etc/systemd/system/trojan.service
echo "After=network.target" >> /etc/systemd/system/trojan.service
echo "" >> /etc/systemd/system/trojan.service
echo "[Service]" >> /etc/systemd/system/trojan.service
echo "Type=simple" >> /etc/systemd/system/trojan.service
echo "PIDFile=/usr/src/trojan/trojan/trojan.pid" >> /etc/systemd/system/trojan.service
echo "ExecStart=/opt/trojan-server/trojan/trojan -c /opt/trojan-server/trojan/config.json" >> /etc/systemd/system/trojan.service
echo "Restart=on-failure" >> /etc/systemd/system/trojan.service
echo "RestartSec=1s" >> /etc/systemd/system/trojan.service
echo "" >> /etc/systemd/system/trojan.service
echo "[Install]" >> /etc/systemd/system/trojan.service
echo "WantedBy=multi-user.target" >> /etc/systemd/system/trojan.service

echo "[Unit]" > /etc/systemd/system/yahagi.service
echo "Description=Yahagi" >> /etc/systemd/system/yahagi.service
echo "After=network.target" >> /etc/systemd/system/yahagi.service
echo "" >> /etc/systemd/system/yahagi.service
echo "[Service]" >> /etc/systemd/system/yahagi.service
echo "Type=simple" >> /etc/systemd/system/yahagi.service
echo "ExecStart=node /opt/trojan-server/yahagi.js/index.js" >> /etc/systemd/system/yahagi.service
echo "Restart=on-failure" >> /etc/systemd/system/yahagi.service
echo "RestartSec=1s" >> /etc/systemd/system/yahagi.service
echo "" >> /etc/systemd/system/yahagi.service
echo "[Install]" >> /etc/systemd/system/yahagi.service
echo "WantedBy=multi-user.target" >> /etc/systemd/system/yahagi.service

echo -e "${CYELLOW}[信息] 正在安装yahagi.js中！${CEND}"
git clone https://github.com/trojan-cluster/yahagi.js.git /opt/trojan-server/yahagi.js
cd /opt/trojan-server
npm install yahagi.js

sed -i "s|/path/to/certificate.crt|/opt/trojan-server/ssl/certificate.crt|"        /opt/trojan-server/trojan/config.json
sed -i "s|/path/to/private.key|/opt/trojan-server/ssl/private.key|"                /opt/trojan-server/trojan/config.json

chmod -R 755 /opt/trojan-server
systemctl daemon-reload

echo -e "${CYELLOW}[信息] 安装完毕！${CEND}"
echo -e "${CYELLOW}[信息] 填写对接信息：/opt/trojan-server/yahagi.js/index.js${CEND}"
echo -e "${CYELLOW}[信息] 导入证书到：/opt/trojan-server/ssl/certificate.crt${CEND}"
echo -e "${CYELLOW}[信息] 导入私钥到：/opt/trojan-server/ssl/private.key${CEND}"
echo -e "${CYELLOW}[信息] 启动Trojan：service trojan start${CEND}"
echo -e "${CYELLOW}[信息] 启动yahagi：service yahagi start${CEND}"
exit 0
