# Our Chat !

An easy to install Enterprise LLM chat system using LibreChat with AWS Bedrock and LDAP/AD authentication. If you have access to AWS Bedrock, why don't you use that? The problem is that the AWS Console is reserved for power users in most organizations, also it will take some time until you are familiar with it (to put it mildly). [LibreChat](https://www.librechat.ai/) on the other hand, takes zero on-boarding time, users just login with their enterprise credentials and enter their prompts:

![image](https://github.com/user-attachments/assets/85422848-7875-4c87-8f62-2582e8e07775)


## Prerequisites 

- Get a RHEL virtual server (this process was tested with RHEL 9.4) with at least 8GB RAM and 50GB free disk space of which about half should be under /home . 
- That machine must be able to talk to the `ldaps port 636` of your enterprise LDAP server (for example Active Directory). 
- You should also request some SSL certificates, unless you use Let's encrypt
- You don't require root access if your sysadmins can run the `prepare-server.sh` script for you, but they should allow you to switch to the ochat user, e.g. `sudo su - ochat`

## Prepare Server 

Run the [prepare-server.sh](https://raw.githubusercontent.com/dirkpetersen/our-chat/refs/heads/main/prepare-server.sh) script as sudo/root user to install docker and prepare the ochat user account

```
curl https://raw.githubusercontent.com/dirkpetersen/our-chat/refs/heads/main/prepare-server.sh?token=$(date +%s) | sudo bash
```

## Install and configure LibreChat

Switch to the ochat user `sudo su - ochat`, clone the LibreChat as well as the our-chat repositories from GitHub and switch to the LibreChat repository

```
cd ~
git clone https://github.com/dirkpetersen/our-chat/
git clone https://github.com/danny-avila/LibreChat/
cd LibreChat/
```

Now we want to configure AWS credentials, run `aws configure` and enter AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY and your region (e.g. us-west-2)

```
aws configure
```



## Longer term vision 

In the future. 

![our-chat-dark](https://github.com/dirkpetersen/our-chat/assets/1427719/6fbbc55d-8bf3-4c7f-8d09-990c3ee3c2e6)


## Troubleshooting 

### Cleaning up docker 

```
### cleanup as root
sudo systemctl stop docker
sudo rm -rf /var/lib/docker/*
sudo rm -rf /var/lib/containerd/*
sudo systemctl start docker
```
