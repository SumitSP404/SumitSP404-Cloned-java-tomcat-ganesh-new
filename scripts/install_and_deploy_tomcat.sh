#!/bin/bash
set -e
set -x

echo "======== Installing AWS CodeDeploy Agent ========="
sudo yum update -y
sudo yum install -y ruby wget

cd /home/ec2-user
wget https://aws-codedeploy-us-west-2.s3.amazonaws.com/latest/install
chmod +x ./install
sudo ./install auto

sudo systemctl start codedeploy-agent
sudo systemctl enable codedeploy-agent
sudo systemctl status codedeploy-agent

echo "======== Checking and Installing Java 11 ========="
if ! java -version &>/dev/null; then
echo "Installing Java 11..."
sudo yum install -y java-11-amazon-corretto
else
echo "Java is already installed."
fi

echo "======== Installing Tomcat ========="
TOMCAT_VERSION=9.0.86
TOMCAT_DIR="/opt/tomcat"
cd /opt/

if [ ! -d "$TOMCAT_DIR" ]; then
echo "Downloading and installing Tomcat..."
sudo curl -O https://archive.apache.org/dist/tomcat/tomcat-9/v${TOMCAT_VERSION}/bin/apache-tomcat-${TOMCAT_VERSION}.tar.gz
sudo tar -xzf apache-tomcat-${TOMCAT_VERSION}.tar.gz
sudo mv apache-tomcat-${TOMCAT_VERSION} "$TOMCAT_DIR"
else
echo "Tomcat is already installed. Skipping installation."
fi

✅ Ensure Tomcat ownership and permissions are correct every time
sudo chown -R ec2-user:ec2-user "$TOMCAT_DIR"
sudo chmod +x "$TOMCAT_DIR"/bin/*.sh

echo "======== Creating Tomcat systemd service ========="
TOMCAT_SERVICE="/etc/systemd/system/tomcat.service"
JAVA_HOME_PATH="/usr/lib/jvm/java-11-amazon-corretto"

if [ ! -f "$TOMCAT_SERVICE" ]; then
sudo tee "$TOMCAT_SERVICE" > /dev/null <<EOF
[Unit]
Description=Apache Tomcat Web Application Container
After=network.target

[Service]
Type=forking
User=ec2-user
Group=ec2-user
Environment=JAVA_HOME=${JAVA_HOME_PATH}
Environment=CATALINA_PID=${TOMCAT_DIR}/temp/tomcat.pid
Environment=CATALINA_HOME=${TOMCAT_DIR}
Environment=CATALINA_BASE=${TOMCAT_DIR}
ExecStart=${TOMCAT_DIR}/bin/startup.sh
ExecStop=${TOMCAT_DIR}/bin/shutdown.sh
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
else
echo "Tomcat systemd service already exists. Skipping creation."
fi

echo "======== Verifying JAVA_HOME path ========="
if [ ! -d "$JAVA_HOME_PATH" ]; then
echo "❌ JAVA_HOME path not found: $JAVA_HOME_PATH"
exit 1
else
echo "✅ JAVA_HOME path verified."
fi

echo "======== Stopping Tomcat to deploy WAR file ========="
sudo systemctl stop tomcat || true
sudo pkill -f 'org.apache.catalina.startup.Bootstrap' || true

echo "======== Deploying WAR file to Tomcat ========="
WAR_NAME="Ecomm.war"
SOURCE_WAR="/home/ec2-user/${WAR_NAME}"
TARGET_WAR="${TOMCAT_DIR}/webapps/${WAR_NAME}"
APP_DIR="${TOMCAT_DIR}/webapps/Ecomm"

Clean up previous deployment
sudo rm -rf "$APP_DIR"
sudo rm -f "$TARGET_WAR"

if [ -f "$SOURCE_WAR" ]; then
sudo cp "$SOURCE_WAR" "$TARGET_WAR"
echo "✅ WAR file copied to Tomcat webapps."
else
echo "❌ WAR file not found at $SOURCE_WAR"
exit 1
fi

echo "======== Configuring Tomcat Users and Access ========="

1. Add admin user with manager-gui role
TOMCAT_USERS_FILE="/opt/tomcat/conf/tomcat-users.xml"
if ! grep -q 'manager-gui' "$TOMCAT_USERS_FILE"; then
echo "🛠 Adding admin user to tomcat-users.xml"
sudo sed -i '/</tomcat-users>/i
<role rolename="manager-gui"/>\n
<user username="admin" password="admin123" roles="manager-gui"/>' "$TOMCAT_USERS_FILE"
else
echo "✅ Tomcat user already configured."
fi

2. Remove or comment the IP restriction in context.xml
CONTEXT_FILE="/opt/tomcat/webapps/manager/META-INF/context.xml"
if [ -f "$CONTEXT_FILE" ] && grep -q 'Valve className="org.apache.catalina.valves.RemoteAddrValve"' "$CONTEXT_FILE"; then
echo "🛠 Removing RemoteAddrValve IP restriction"
sudo sed -i 's/<Valve/<!-- <Valve/' "$CONTEXT_FILE"
sudo sed -i 's//>$//> -->/' "$CONTEXT_FILE"
else
echo "✅ context.xml already allows remote access or does not exist."
fi

echo "======== Starting and Enabling Tomcat service ========="
sudo systemctl daemon-reload
sudo systemctl enable tomcat
sudo systemctl restart tomcat

if sudo systemctl is-active --quiet tomcat; then
echo "✅ Tomcat started successfully."
else
echo "❌ Tomcat failed to start. Run 'sudo journalctl -xeu tomcat' for more info."
exit 1
fi

echo "======== Deployment Complete ========="
