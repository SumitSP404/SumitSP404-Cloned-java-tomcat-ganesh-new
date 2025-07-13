#!/bin/bash
set -e
set -x

# ====== 1. Install AWS CodeDeploy Agent ======
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

# ====== 2. Install Java 11 ======
echo "======== Checking and Installing Java 11 ========="
if ! java -version &>/dev/null; then
  echo "Installing Java 11..."
  sudo yum install -y java-11-amazon-corretto
else
  echo "✅ Java is already installed."
fi

# ====== 3. Install Tomcat 9 ======
echo "======== Installing Tomcat ========="
TOMCAT_VERSION=9.0.86
TOMCAT_DIR="/opt/tomcat"
TOMCAT_USER="ec2-user"

if [ ! -d "$TOMCAT_DIR" ]; then
  echo "➡️ Downloading Tomcat $TOMCAT_VERSION..."
  cd /tmp
  curl -O https://archive.apache.org/dist/tomcat/tomcat-9/v${TOMCAT_VERSION}/bin/apache-tomcat-${TOMCAT_VERSION}.tar.gz
  tar -xzf apache-tomcat-${TOMCAT_VERSION}.tar.gz
  sudo mkdir -p /opt/
  sudo mv apache-tomcat-${TOMCAT_VERSION} $TOMCAT_DIR
  sudo chown -R $TOMCAT_USER:$TOMCAT_USER $TOMCAT_DIR
  sudo chmod +x $TOMCAT_DIR/bin/*.sh
else
  echo "✅ Tomcat already installed. Skipping."
fi

# ====== 4. Deploy missing manager apps ======
echo "======== Copying Tomcat Manager Apps ========="
cd /tmp
curl -O https://archive.apache.org/dist/tomcat/tomcat-9/v${TOMCAT_VERSION}/bin/apache-tomcat-${TOMCAT_VERSION}.tar.gz
tar -xzf apache-tomcat-${TOMCAT_VERSION}.tar.gz
sudo cp -r apache-tomcat-${TOMCAT_VERSION}/webapps/manager $TOMCAT_DIR/webapps/
sudo cp -r apache-tomcat-${TOMCAT_VERSION}/webapps/host-manager $TOMCAT_DIR/webapps/

# ====== 5. Configure tomcat-users.xml ======
echo "======== Configuring tomcat-users.xml ========="
sudo tee $TOMCAT_DIR/conf/tomcat-users.xml > /dev/null <<EOF
<?xml version='1.0' encoding='utf-8'?>
<tomcat-users>
  <role rolename="manager-gui"/>
  <role rolename="admin-gui"/>
  <user username="admin" password="admin" roles="manager-gui,admin-gui"/>
</tomcat-users>
EOF

# ====== 6. Set up systemd service (if not present) ======
echo "======== Creating Tomcat systemd service ========="
if [ ! -f "/etc/systemd/system/tomcat.service" ]; then
  sudo tee /etc/systemd/system/tomcat.service > /dev/null <<EOF
[Unit]
Description=Apache Tomcat Web Application Container
After=network.target

[Service]
Type=forking
User=$TOMCAT_USER
Group=$TOMCAT_USER
Environment=JAVA_HOME=/usr/lib/jvm/java-11-amazon-corretto
Environment=CATALINA_HOME=$TOMCAT_DIR
Environment=CATALINA_BASE=$TOMCAT_DIR
ExecStart=$TOMCAT_DIR/bin/startup.sh
ExecStop=$TOMCAT_DIR/bin/shutdown.sh
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
else
  echo "✅ tomcat.service already exists. Skipping creation."
fi

# ====== 7. Deploy WAR file (if available) ======
echo "======== Deploying WAR file to Tomcat ========="
WAR_NAME="Ecomm.war"
SOURCE_WAR="/home/ec2-user/${WAR_NAME}"
TARGET_WAR="$TOMCAT_DIR/webapps/${WAR_NAME}"
APP_DIR="$TOMCAT_DIR/webapps/Ecomm"

sudo rm -rf "$APP_DIR"
sudo rm -f "$TARGET_WAR"

if [ -f "$SOURCE_WAR" ]; then
  sudo cp "$SOURCE_WAR" "$TARGET_WAR"
  sudo chown $TOMCAT_USER:$TOMCAT_USER "$TARGET_WAR"
  echo "✅ WAR file copied to Tomcat webapps."
else
  echo "❌ WAR file not found at $SOURCE_WAR"
fi

# ====== 8. Restart Tomcat (only if not running) ======
echo "======== Ensuring Tomcat is running ========="
if ! pgrep -f 'org.apache.catalina.startup.Bootstrap' > /dev/null; then
  echo "🔄 Starting Tomcat manually..."
  sudo $TOMCAT_DIR/bin/startup.sh
else
  echo "✅ Tomcat is already running. Skipping restart."
fi

# ====== 9. Finish ======
echo "======== ✅ Script Execution Complete ========="
echo "🌐 Access Tomcat: http://<EC2_PUBLIC_IP>:8080"
echo "🔐 Login (Tomcat Manager): admin / admin"
