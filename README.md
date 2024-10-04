# Our Chat !

An easy to install Enterprise LLM chat system using LibreChat with AWS Bedrock and LDAP/AD authentication. If you have access to AWS Bedrock, why don't you use that? The problem is that AWS Console is reserved for power users in most organizations, also it will take some time until you are familiar with it (to put it mildly). 

![image](https://github.com/user-attachments/assets/85422848-7875-4c87-8f62-2582e8e07775)


## Prerequisites 

Get a RHEL virtual server with at least 8GB RAM and 50GB free disk space of which half should be under /home . That machine must be able to talk to the ldaps port 636 of your enterprise LDAP server (for example Active Directory). You don't require root access if your sysadmins can run the prepare server script for you. 

## Prepare Server 



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
