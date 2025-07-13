#!/bin/bash

# Update system
sudo yum update -y

# Install Java
sudo amazon-linux-extras enable corretto11
sudo yum install -y java-11-amazon-corretto

# Create tomcat user
sudo groupadd tomcat
sudo useradd -M -s /bin/nologin -g tomcat -d /opt/tomcat tomcat

# Download Tomcat
cd /opt
sudo curl -O https://downloads.apache.org/tomcat/tomcat-9/v9.0.86/bin/apache-tomcat-9.0.86.tar.gz
sudo tar -xvzf apache-tomcat-9.0.86.tar.gz
sudo mv apache-tomcat-9.0.86 tomcat
sudo chown -R tomcat:tomcat /opt/tomcat

# Set permissions
sudo chmod +x /opt/tomcat/bin/*.sh

# Setup systemd service for Tomcat
cat <<EOF | sudo tee /etc/systemd/system/tomcat.service
[Unit]
Description=Apache Tomcat Web Application Container
After=network.target

[Service]
Type=forking

User=tomcat
Group=tomcat

Environment="JAVA_HOME=/usr/lib/jvm/java-11-amazon-corretto"
Environment="CATALINA_PID=/opt/tomcat/temp/tomcat.pid"
Environment="CATALINA_HOME=/opt/tomcat"
Environment="CATALINA_BASE=/opt/tomcat"
Environment="CATALINA_OPTS=-Xms512M -Xmx1024M -server -XX:+UseParallelGC"
Environment="JAVA_OPTS=-Djava.security.egd=file:///dev/urandom"

ExecStart=/opt/tomcat/bin/startup.sh
ExecStop=/opt/tomcat/bin/shutdown.sh

Restart=always

[Install]
WantedBy=multi-user.target
EOF

# Reload and start Tomcat
sudo systemctl daemon-reexec
sudo systemctl daemon-reload
sudo systemctl enable tomcat
sudo systemctl start tomcat

# Configure Tomcat users
sudo tee /opt/tomcat/conf/tomcat-users.xml > /dev/null <<EOF
<tomcat-users>
  <role rolename="manager-gui"/>
  <role rolename="admin-gui"/>
  <user username="admin" password="admin123" roles="manager-gui,admin-gui"/>
</tomcat-users>
EOF

# Allow access from anywhere (disable IP restrictions)
sudo sed -i 's/<Context>/<Context antiResourceLocking="false" privileged="true">/' /opt/tomcat/webapps/manager/META-INF/context.xml
sudo sed -i 's/<Context>/<Context antiResourceLocking="false" privileged="true">/' /opt/tomcat/webapps/host-manager/META-INF/context.xml

# Re-download manager and host-manager if broken
cd /opt/tomcat/webapps
sudo rm -rf manager host-manager
sudo curl -O https://downloads.apache.org/tomcat/tomcat-9/v9.0.86/bin/extras/catalina-manager.tar.gz
sudo tar -xzf catalina-manager.tar.gz
sudo rm catalina-manager.tar.gz
sudo chown -R tomcat:tomcat /opt/tomcat/webapps

# Deploy Ecomm.war
sudo cp /home/ec2-user/Ecomm.war /opt/tomcat/webapps/
sudo chown tomcat:tomcat /opt/tomcat/webapps/Ecomm.war

# Restart Tomcat
sudo systemctl restart tomcat

# Install CodeDeploy agent
cd /home/ec2-user
sudo yum install -y ruby wget
wget https://aws-codedeploy-us-west-2.s3.amazonaws.com/latest/install
chmod +x ./install
sudo ./install auto
sudo systemctl start codedeploy-agent
sudo systemctl enable codedeploy-agent

# Confirm running
echo "Tomcat and CodeDeploy setup complete."
