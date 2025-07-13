#!/bin/bash

# Define variables
TOMCAT_DIR="/opt/tomcat"
TOMCAT_USER_CONF="$TOMCAT_DIR/conf/tomcat-users.xml"
MANAGER_CONTEXT="$TOMCAT_DIR/webapps/manager/META-INF/context.xml"
HOSTMANAGER_CONTEXT="$TOMCAT_DIR/webapps/host-manager/META-INF/context.xml"

# Function to install Tomcat if not found
install_tomcat() {
  echo "⚙️ Tomcat not found. Installing Tomcat 9..."
  sudo yum update -y
  sudo yum install -y java-11-amazon-corretto wget unzip
  cd /opt
  sudo wget https://downloads.apache.org/tomcat/tomcat-9/v9.0.86/bin/apache-tomcat-9.0.86.tar.gz
  sudo tar -xvzf apache-tomcat-9.0.86.tar.gz
  sudo mv apache-tomcat-9.0.86 tomcat
  sudo chmod -R 755 $TOMCAT_DIR
  sudo sh $TOMCAT_DIR/bin/startup.sh
}

# Install Tomcat if missing
if [ ! -d "$TOMCAT_DIR" ]; then
  install_tomcat
fi

# Step 1: Add manager user to tomcat-users.xml
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

# Step 2: Allow remote access to manager and host-manager
echo "🔧 Updating context.xml for remote access..."
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

# Step 3: Restart Tomcat
echo "♻️ Restarting Tomcat..."
if command -v systemctl >/dev/null 2>&1; then
  sudo systemctl restart tomcat || {
    echo "Tomcat service not found. Restarting using shell scripts..."
    sudo $TOMCAT_DIR/bin/shutdown.sh
    sleep 3
    sudo $TOMCAT_DIR/bin/startup.sh
  }
else
  sudo $TOMCAT_DIR/bin/shutdown.sh
  sleep 3
  sudo $TOMCAT_DIR/bin/startup.sh
fi

# Step 4: Show result
echo "✅ Tomcat setup complete!"
echo "➡️ Manager:       http://<your-public-ip>:8080/manager/html"
echo "➡️ Host Manager:  http://<your-public-ip>:8080/host-manager/html"
echo "🔐 Username: admin  | Password: admin"
