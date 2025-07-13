# scripts/before_install.sh
#!/bin/bash
set -e

echo "==== Installing CodeDeploy Agent ===="
sudo yum update -y
sudo yum install -y ruby wget
cd /home/ec2-user
wget https://aws-codedeploy-us-west-2.s3.amazonaws.com/latest/install
chmod +x ./install
sudo ./install auto
sudo systemctl start codedeploy-agent
sudo systemctl enable codedeploy-agent

# Java 11
if ! java -version &>/dev/null; then
  sudo yum install -y java-11-amazon-corretto
fi

# Tomcat install
TOMCAT_VERSION=9.0.86
TOMCAT_DIR=/opt/tomcat
if [ ! -d "$TOMCAT_DIR" ]; then
  cd /tmp
  curl -O https://archive.apache.org/dist/tomcat/tomcat-9/v${TOMCAT_VERSION}/bin/apache-tomcat-${TOMCAT_VERSION}.tar.gz
  sudo mkdir -p /opt
  sudo tar -xzf apache-tomcat-${TOMCAT_VERSION}.tar.gz -C /opt/
  sudo mv /opt/apache-tomcat-${TOMCAT_VERSION} $TOMCAT_DIR
  sudo chmod +x $TOMCAT_DIR/bin/*.sh
  sudo chown -R ec2-user:ec2-user $TOMCAT_DIR
fi

# tomcat-users.xml config
sudo tee $TOMCAT_DIR/conf/tomcat-users.xml > /dev/null <<EOF
<?xml version='1.0' encoding='utf-8'?>
<tomcat-users>
  <role rolename="manager-gui"/>
  <user username="admin" password="admin" roles="manager-gui"/>
</tomcat-users>
EOF

# systemd service
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
Environment=CATALINA_HOME=$TOMCAT_DIR
Environment=CATALINA_BASE=$TOMCAT_DIR
ExecStart=$TOMCAT_DIR/bin/startup.sh
ExecStop=$TOMCAT_DIR/bin/shutdown.sh
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
fi

sudo systemctl daemon-reload
sudo systemctl enable tomcat

# scripts/deploy_app.sh
#!/bin/bash
set -e

WAR_NAME=Ecomm.war
TOMCAT_DIR=/opt/tomcat
TARGET_WAR=$TOMCAT_DIR/webapps/$WAR_NAME
APP_DIR=$TOMCAT_DIR/webapps/Ecomm

sudo rm -rf "$APP_DIR"
sudo rm -f "$TARGET_WAR"

if [ -f "/home/ec2-user/$WAR_NAME" ]; then
  sudo cp "/home/ec2-user/$WAR_NAME" "$TARGET_WAR"
  sudo chown ec2-user:ec2-user "$TARGET_WAR"i

# scripts/start_tomcat.sh
#!/bin/bash
set -e

if ! pgrep -f "org.apache.catalina.startup.Bootstrap start" > /dev/null; then
  echo "Tomcat is not running, starting it..."
  sudo systemctl start tomcat
else
  echo "Tomcat is already running, skipping start."
fi

# scripts/stop_tomcat.sh
#!/bin/bash
set -e

if pgrep -f "org.apache.catalina.startup.Bootstrap start" > /dev/null; then
  echo "Stopping Tomcat before deployment..."
  sudo systemctl stop tomcat
fi

# scripts/validate_service.sh
#!/bin/bash
set -e

URL="http://localhost:8080/Ecomm"
RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" "$URL")

if [ "$RESPONSE" -eq 200 ]; then
  echo "App is up. Validation successful."
else
  echo "App failed validation. HTTP $RESPONSE"
  exit 1
fi
