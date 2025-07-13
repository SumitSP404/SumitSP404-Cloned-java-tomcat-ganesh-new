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

echo "======== Installing Java 11 if not present ========="
if ! java -version &>/dev/null; then
  sudo yum install -y java-11-amazon-corretto
else
  echo "✅ Java already installed"
fi

echo "======== Installing Tomcat 9 ========="
TOMCAT_VERSION="9.0.86"
TOMCAT_DIR="/opt/tomcat"

cd /opt
if [ ! -d "$TOMCAT_DIR" ]; then
  sudo curl -O https://archive.apache.org/dist/tomcat/tomcat-9/v${TOMCAT_VERSION}/bin/apache-tomcat-${TOMCAT_VERSION}.tar.gz
  sudo tar -xzf apache-tomcat-${TOMCAT_VERSION}.tar.gz
  sudo mv apache-tomcat-${TOMCAT_VERSION} "$TOMCAT_DIR"
  sudo chown -R ec2-user:ec2-user "$TOMCAT_DIR"
  sudo chmod +x "$TOMCAT_DIR"/bin/*.sh
fi

echo "======== Creating systemd service for Tomcat ========="
JAVA_HOME_PATH="/usr/lib/jvm/java-11-amazon-corretto"
TOMCAT_SERVICE="/etc/systemd/system/tomcat.service"

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

echo "======== Verifying JAVA_HOME ========="
if [ ! -d "$JAVA_HOME_PATH" ]; then
  echo "❌ JAVA_HOME path not found: $JAVA_HOME_PATH"
  exit 1
fi

echo "======== Stopping any running Tomcat process ========="
sudo systemctl stop tomcat || true
sudo pkill -f 'org.apache.catalina.startup.Bootstrap' || true

echo "======== Deploying WAR file ========="
WAR_NAME="Ecomm.war"
SOURCE_WAR="/home/ec2-user/${WAR_NAME}"
TARGET_WAR="${TOMCAT_DIR}/webapps/${WAR_NAME}"
APP_DIR="${TOMCAT_DIR}/webapps/Ecomm"

# Clean previous app
sudo rm -rf "$APP_DIR"
sudo rm -f "$TARGET_WAR"

if [ -f "$SOURCE_WAR" ]; then
  sudo cp "$SOURCE_WAR" "$TARGET_WAR"
  echo "✅ WAR file deployed to Tomcat"
else
  echo "❌ WAR file not found at $SOURCE_WAR"
  exit 1
fi

echo "======== Configuring tomcat-users.xml with manager credentials ========="
TOMCAT_USER_CONF="$TOMCAT_DIR/conf/tomcat-users.xml"
sudo tee "$TOMCAT_USER_CONF" > /dev/null <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<tomcat-users>
  <role rolename="manager-gui"/>
  <role rolename="admin-gui"/>
  <user username="admin" password="admin" roles="manager-gui,admin-gui"/>
</tomcat-users>
EOF

echo "======== Allowing remote access to manager and host-manager ========="
MANAGER_CONTEXT="$TOMCAT_DIR/webapps/manager/META-INF/context.xml"
HOSTMANAGER_CONTEXT="$TOMCAT_DIR/webapps/host-manager/META-INF/context.xml"

sudo tee "$MANAGER_CONTEXT" > /dev/null <<EOF
<Context antiResourceLocking="false" privileged="true" >
  <!-- Remote access allowed for manager app -->
</Context>
EOF

sudo tee "$HOSTMANAGER_CONTEXT" > /dev/null <<EOF
<Context antiResourceLocking="false" privileged="true" >
  <!-- Remote access allowed for host-manager app -->
</Context>
EOF

echo "======== Starting Tomcat via systemd ========="
sudo systemctl daemon-reload
sudo systemctl enable tomcat
sudo systemctl restart tomcat

if sudo systemctl is-active --quiet tomcat; then
  echo "✅ Tomcat started successfully."
else
  echo "❌ Tomcat failed to start. Use 'sudo journalctl -xeu tomcat' to debug."
  exit 1
fi

echo "======== ✅ All Setup Complete ========="
echo "➡️ Access Manager App: http://<your-ec2-ip>:8080/manager/html"
echo "➡️ Login: admin / admin"
