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
sudo systemctl status codedeploy-agent || true

echo "======== Checking and Installing Java 11 ========="
if ! java -version &>/dev/null; then
  echo "Installing Java 11..."
  sudo yum install -y java-11-amazon-corretto
else
  echo "Java is already installed."
fi

echo "======== Installing Tomcat ========="
TOMCAT_VERSION=9.0.86
sudo mkdir -p /opt
cd /opt/

if [ ! -d "/opt/tomcat" ]; then
  echo "Downloading and installing Tomcat..."
  sudo curl -O https://archive.apache.org/dist/tomcat/tomcat-9/v${TOMCAT_VERSION}/bin/apache-tomcat-${TOMCAT_VERSION}.tar.gz
  sudo tar -xzf apache-tomcat-${TOMCAT_VERSION}.tar.gz
  sudo mv apache-tomcat-${TOMCAT_VERSION} tomcat
  sudo chmod +x /opt/tomcat/bin/*.sh
  sudo chown -R ec2-user:ec2-user /opt/tomcat
else
  echo "Tomcat is already installed. Skipping installation."
fi

echo "======== Creating tomcat-users.xml with BASIC auth and admin users ========="
sudo tee /opt/tomcat/conf/tomcat-users.xml > /dev/null <<EOF
<?xml version='1.0' encoding='utf-8'?>
<tomcat-users xmlns="http://tomcat.apache.org/xml"
              xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
              xsi:schemaLocation="http://tomcat.apache.org/xml tomcat-users.xsd"
              version="1.0">

  <!-- Admin user for Tomcat Manager -->
  <role rolename="manager-gui"/>
  <role rolename="manager-script"/>
  <role rolename="manager-jmx"/>
  <role rolename="manager-status"/>
  <user username="admin" password="admin" roles="manager-gui,manager-script,manager-jmx,manager-status"/>
</tomcat-users>
EOF

echo "======== Creating Tomcat systemd service ========="
if [ ! -f "/etc/systemd/system/tomcat.service" ]; then
  sudo tee /etc/systemd/system/tomcat.service > /dev/null <<EOF
[Unit]
Description=Apache Tomcat Web Application Container
After=network.target

[Service]
Type=forking
User=ec2-user
Group=ec2-user
Environment=JAVA_HOME=/usr/lib/jvm/java-11-amazon-corretto
Environment=CATALINA_HOME=/opt/tomcat
Environment=CATALINA_BASE=/opt/tomcat
ExecStart=/opt/tomcat/bin/startup.sh
ExecStop=/opt/tomcat/bin/shutdown.sh
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
else
  echo "Tomcat systemd service already exists. Skipping creation."
fi

echo "======== Stopping Tomcat to deploy WAR file ========="
sudo systemctl stop tomcat || true

echo "======== Deploying WAR file to Tomcat ========="
WAR_NAME="Ecomm.war"
SOURCE_WAR="/home/ec2-user/${WAR_NAME}"
TARGET_WAR="/opt/tomcat/webapps/${WAR_NAME}"
APP_DIR="/opt/tomcat/webapps/Ecomm"

sudo rm -rf "$APP_DIR"
sudo rm -f "$TARGET_WAR"

if [ -f "$SOURCE_WAR" ]; then
  sudo cp "$SOURCE_WAR" "$TARGET_WAR"
  echo "✅ WAR file copied to Tomcat webapps."
else
  echo "❌ WAR file not found at $SOURCE_WAR"
  exit 1
fi

echo "======== Starting and Enabling Tomcat service ========="
sudo systemctl daemon-reload
sudo systemctl enable tomcat
sudo systemctl restart tomcat

echo "======== ✅ Deployment Complete ========="
echo "🌐 Access Tomcat at: http://<EC2_PUBLIC_IP>:8080"
echo "🔐 Manager App credentials → username: admin / password: admin"
