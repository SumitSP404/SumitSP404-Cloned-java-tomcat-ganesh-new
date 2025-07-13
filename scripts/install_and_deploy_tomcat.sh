#!/bin/bash

# Define variables
TOMCAT_DIR="/opt/tomcat"
TOMCAT_USER_CONF="$TOMCAT_DIR/conf/tomcat-users.xml"
MANAGER_CONTEXT="$TOMCAT_DIR/webapps/manager/META-INF/context.xml"
HOSTMANAGER_CONTEXT="$TOMCAT_DIR/webapps/host-manager/META-INF/context.xml"

# Install Java, Tomcat, and unzip if not present
if [ ! -d "$TOMCAT_DIR" ]; then
  echo "⚙️ Installing Tomcat 9..."
  sudo yum update -y
  sudo yum install -y java-11-openjdk wget unzip
  cd /opt
  sudo wget https://downloads.apache.org/tomcat/tomcat-9/v9.0.86/bin/apache-tomcat-9.0.86.tar.gz
  sudo tar -xvzf apache-tomcat-9.0.86.tar.gz
  sudo mv apache-tomcat-9.0.86 tomcat
  sudo chmod -R 755 $TOMCAT_DIR
fi

# Add manager user
echo "🔧 Updating tomcat-users.xml..."
sudo tee "$TOMCAT_USER_CONF" > /dev/null <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<tomcat-users>
  <role rolename="manager-gui"/>
  <role rolename="admin-gui"/>
  <role rolename="manager-script"/>
  <role rolename="manager-jmx"/>
  <role rolename="manager-status"/>
  <user username="admin" password="admin" roles="manager-gui,admin-gui,manager-script,manager-jmx,manager-status"/>
</tomcat-users>
EOF

# Allow remote access to manager and host-manager
echo "🔧 Enabling remote access for manager and host-manager..."
sudo tee "$MANAGER_CONTEXT" > /dev/null <<EOF
<Context antiResourceLocking="false" privileged="true" >
  <!-- Remote access allowed -->
</Context>
EOF

sudo tee "$HOSTMANAGER_CONTEXT" > /dev/null <<EOF
<Context antiResourceLocking="false" privileged="true" >
  <!-- Remote access allowed -->
</Context>
EOF

# Install and start CodeDeploy Agent
echo "🚀 Installing AWS CodeDeploy Agent..."
cd /home/ec2-user
sudo yum install -y ruby wget
wget https://aws-codedeploy-us-west-2.s3.amazonaws.com/latest/install
chmod +x ./install
sudo ./install auto
sudo systemctl start codedeploy-agent
sudo systemctl enable codedeploy-agent

# Restart Tomcat
echo "♻️ Restarting Tomcat..."
if pgrep -f tomcat > /dev/null; then
  sudo $TOMCAT_DIR/bin/shutdown.sh
  sleep 5
fi
sudo $TOMCAT_DIR/bin/startup.sh

# Display status
echo "✅ Tomcat setup complete!"
echo "➡️ Tomcat Manager: http://<your-public-ip>:8080/manager/html"
echo "➡️ Host Manager:   http://<your-public-ip>:8080/host-manager/html"
echo "🔐 Username: admin | Password: admin"
