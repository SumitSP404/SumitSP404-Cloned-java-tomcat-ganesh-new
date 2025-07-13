#!/bin/bash

# ==============================
# Tomcat 9 Automated Setup Script
# ==============================

# Define variables
TOMCAT_DIR="/opt/tomcat"
TOMCAT_USER_CONF="$TOMCAT_DIR/conf/tomcat-users.xml"
MANAGER_CONTEXT="$TOMCAT_DIR/webapps/manager/META-INF/context.xml"
HOSTMANAGER_CONTEXT="$TOMCAT_DIR/webapps/host-manager/META-INF/context.xml"

# Function to install Tomcat
install_tomcat() {
  echo "⚙️ Installing Tomcat 9..."
  sudo yum update -y
  sudo yum install -y java-11-amazon-corretto wget unzip

  cd /opt
  sudo wget https://downloads.apache.org/tomcat/tomcat-9/v9.0.86/bin/apache-tomcat-9.0.86.tar.gz
  sudo tar -xvzf apache-tomcat-9.0.86.tar.gz
  sudo mv apache-tomcat-9.0.86 tomcat
  sudo chmod -R 755 $TOMCAT_DIR
  sudo sh $TOMCAT_DIR/bin/startup.sh
}

# Step 0: Install Tomcat if not present
if [ ! -d "$TOMCAT_DIR" ]; then
  install_tomcat
fi

# Step 1: Add admin user to tomcat-users.xml
echo "🔧 Creating user 'admin' with full access in tomcat-users.xml..."
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

# Step 2: Allow remote access in context.xml (fix 403)
echo "🔓 Removing IP lock from manager and host-manager context.xml..."
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

# Step 3: Allow 8080 traffic if firewalld is running (optional)
if sudo systemctl is-active firewalld &> /dev/null; then
  echo "🔓 Opening port 8080 on firewalld..."
  sudo firewall-cmd --permanent --add-port=8080/tcp
  sudo firewall-cmd --reload
fi

# Step 4: Restart Tomcat
echo "♻️ Restarting Tomcat server..."
if command -v systemctl >/dev/null 2>&1 && sudo systemctl status tomcat &> /dev/null; then
  sudo systemctl restart tomcat
else
  sudo $TOMCAT_DIR/bin/shutdown.sh
  sleep 3
  sudo $TOMCAT_DIR/bin/startup.sh
fi

# Step 5: Output success message
echo "✅ Tomcat is installed and configured!"
echo "🌐 Access URLs:"
echo "   ➤ Manager:       http://<your-public-ip>:8080/manager/html"
echo "   ➤ Host Manager:  http://<your-public-ip>:8080/host-manager/html"
echo "🔐 Login:"
echo "   ➤ Username: admin"
echo "   ➤ Password: admin"
