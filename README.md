# Our Chat !

An easy to install Enterprise LLM chat system using LibreChat with AWS Bedrock and LDAP/AD authentication. If you have access to AWS Bedrock, why don't you use that? The problem is that the AWS Console is reserved for power users in most organizations, also it will take some time until you are familiar with it (to put it mildly). [LibreChat](https://www.librechat.ai/) on the other hand, takes zero on-boarding time, users just login with their enterprise credentials and enter their prompts:

![image](https://github.com/user-attachments/assets/85422848-7875-4c87-8f62-2582e8e07775)


## Prerequisites 

- Get a RHEL virtual server (this process was tested with RHEL 9.4) with at least 8GB RAM and 50GB free disk space of which about half should be under /home . 
- That machine must be able to talk to the `ldaps port 636` of your enterprise LDAP server (for example Active Directory). 
- You should also request some SSL certificates, unless you use Let's encrypt
- AWS credentials (AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY) for an AWS service account (perhaps called librechat or ochat) that has no permissions except for the AmazonBedrockFullAccess policy attached to it. 
- You don't require root access if your sysadmins can run the `prepare-server.sh` script for you, but they should allow you to switch to the ochat user, e.g. `sudo su - ochat`

## Prepare Server 

Run the [prepare-server.sh](https://raw.githubusercontent.com/dirkpetersen/our-chat/refs/heads/main/prepare-server.sh) script as root user to install docker and prepare the ochat user account. You can also start it as a normal user if you have requested the corrent [sudo config](#i-dont-have-root-permissions)

```
curl https://raw.githubusercontent.com/dirkpetersen/our-chat/refs/heads/main/prepare-server.sh?token=$(date +%s) | bash
```

## Install and configure our-chat

Switch to the ochat user `sudo su - ochat` and continue with configuration. Clone the our-chat repository from GitHub and copy the .env.ochat and librechat.yml files to the root of the home directory:

```
cd ~
git clone https://github.com/dirkpetersen/our-chat/
cp ~/our-chat/.env.ochat ~/.env
cp ~/our-chat/librechat.yml ~/librechat.yml
cp ~/our-chat/nginx.conf ~/nginx.conf
```

### AWS connectivity

As a first step configure AWS credentials, run `aws configure` and enter AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY and your region (e.g. us-west-2) for the AWS service account that has only the  AmazonBedrockFullAccess policy attached or edit `~/.aws/credentials` directly.  

```
aws configure
```

Then test the connectivity to AWS Bedrock, by running:

```
~/our-chat/tests/bedrock-test.py
```

you should see a list of available models and an "Hello World" prompt:

```
List of available models on AWS Bedrock:

amazon.titan-tg1-large
amazon.titan-embed-g1-text-02
.
.
mistral.mistral-large-2407-v1:0

Response to 'Hello, world': Hello! How can I assist you today? Feel free to ask me anything or let me know if you need help with a specific topic.
```

As LibreChat does not support API access you can give API users bedrock API access in their AWS account and bedrock-test.py may serve as a good initial example. 

You can find more details about AWS in the AWS budget section below. 

## LibreChat install and Configuration

Before we install LibreChat we prepare the 3 configuration files we copied to the root of the home direcotry earlier. These are minimal configuration files to support the bedrock service 

### librechat.yml

For example, use `vi ~/librechat.yml` to change the terms of service, modify the site footer and change a few advanced bedrock settings, for example allowed AWS regions 

### nginx.conf 

The only change `~/nginx.conf` likely requires, is setting the filenames for the  SSL certiticates for https.  

```
   ssl_certificate /home/ochat/ohchat.domain.edu.pem;
   ssl_certificate_key /home/ochat/ohchat.domain.edu.pem;
   ssl_password_file /home/ochat/ohchat.domain.edu.pw;
```

### .env

`.env` contains most settings and these are exported as environment variables. First review the `BEDROCK_AWS_DEFAULT_REGION=us-west-2` and then focus on the LDAP settings: 

These settings should be pretty self explanatory, for example `LDAP_LOGIN_USES_USERNAME` means that you can login with your username instead of typing your entire email address. The LDAP_SEARCH_FILTER is a bit of a crutch that we use to restrict LibreChat to members of an AD/LDAP security group. The filter was not intended for authorization and if a new user is not member of that group, they will be a 401 error (AuthN) instead of 403 (AuthZ). This can be a bit confusing. On some LDAP systems the LDAP_BIND_DN can be the email address (aka service principal) of the service accout, e.g. `myserviceaccount@domain.edu`

```
LDAP_URL=ldaps://ldap.domain.edu:636
LDAP_USER_SEARCH_BASE=OU=User Accounts,dc=domain,dc=edu
LDAP_BIND_DN=CN=myserviceaccount,OU=Service Accounts,OU=User Accounts,DC=domain,DC=edu
LDAP_BIND_CREDENTIALS="ad-password"
LDAP_LOGIN_USES_USERNAME=true
LDAP_SEARCH_FILTER=(&(sAMAccountName={{username}})(memberOf=CN=MyGroup,OU=Groups,DC=domain,DC=edu))
LDAP_FULL_NAME=displayName
```

After you have configured all these 7 settings, please use the LDAP test script to verify these settings, you might have to change the user id of `testuser`

```
~/our-chat/test/ldap-test.py

/ldap-test.py
Successfully read environment variables: ['LDAP_URL', 'LDAP_USER_SEARCH_BASE', 'LDAP_BIND_DN', 'LDAP_BIND_CREDENTIALS', 'LDAP_LOGIN_USES_USERNAME', 'LDAP_SEARCH_FILTER', 'LDAP_FULL_NAME']

Connected as: CN=myserviceaccount,OU=Service Accounts,OU=User Accounts,DC=domain,DC=edu

Evaluating LDAP_SEARCH_FILTER with testuser peterdir:

Evaluating search filter: (&(sAMAccountName=peterdir)(memberOf=CN=APP oChat Users,OU=Groups,DC=domain,DC=edu))
Found 1 matching entries:
DN: CN=peterdir,OU=User Accounts,DC=ohsum01,DC=ohsu,DC=edu
Attributes:
  displayName: Dirk Petersen
  memberOf: ['CN=unix_ochat,OU=Groups,DC=domain,DC=edu', ......
```

And as a final step we want to setup unique tokens for 

CREDS_KEY, CREDS_IV, JWT_SECRET, JWT_REFRESH_SECRET and MEILI_MASTER_KEY

Go to https://www.librechat.ai/toolkit/creds_generator, generate keys and put them in .env 



# INSTALL 

## Longer term vision 

In the future. 

![our-chat-dark](https://github.com/dirkpetersen/our-chat/assets/1427719/6fbbc55d-8bf3-4c7f-8d09-990c3ee3c2e6)


## Troubleshooting 

### cannot create docker group

In some cases your docker installation may not create a `docker` group in /etc/group. This is often because your IT department may have created a global docker group in their IAM system in order to manage their systems centrally. In that case the `groupadd docker` command will fail. There are 2 workaounds for this:

1. You can try editing `/etc/group` directly and add a line `docker:x:986:ochat` to it. The downside of this approach is, that you then have 2 different docker groups with different gidNumbers. While it should work without issues, it can be confusing, expecially if you are troubleshooting 
1. You can create a new group (for example `ldocker`, e.g. for local docker), add the ochat user to it and ask docker to use it instead of the `docker` group. This requires these steps:

- edit /etc/docker/daemon.json 

```
sudo echo -e '{\n  "group": "ldocker"\n}' >> /etc/docker/daemon.json
```

- run `systemctl edit docker.socket` and set the SocketGroup=ldocker

```
### Editing /etc/systemd/system/docker.socket.d/override.conf
### Anything between here and the comment below will become the new contents of the file

[Socket]
SocketGroup=ldocker

### Lines below this comment will be discarded
```

- restart the docker socket (not the docker daemon) and check that the socket has the correct group ownership

```
systemctl restart docker.socket

ls -l /var/run/docker.sock
srw-rw----. 1 root ldocker 0 Oct  4 21:23 /var/run/docker.sock
```

If this is not working, please remove the docker packages using `dnf` and reinstall docker


### I don't have root permissions 

If your IT infrastructure team cannot give you `root` access to the virtual server you requested, you may still be able to get access to management features via sudo. Ask your sysadmin to run `visudo` and paste in the config below. Change yourusername to your actual user name:

```
yourusername (ALL) NOPASSWD: /usr/bin/dnf, /usr/bin/rpm, /usr/bin/systemctl, /usr/bin/loginctl enable-linger *, /usr/bin/docker, /usr/bin/vi /etc/nginx/nginx.conf, /usr/bin/vi /etc/nginx/sites-available/*, /usr/bin/nginx, /usr/sbin/useradd, /usr/sbin/userdel, /usr/sbin/usermod -aG docker *, /usr/sbin/reboot, /usr/bin/su - *
yourusername (ALL) !/usr/bin/su -
yourusername (ALL) !/usr/bin/su - root
```

### Cleaning up docker 

```
### cleanup as root
sudo systemctl stop docker
sudo rm -rf /var/lib/docker/*
sudo rm -rf /var/lib/containerd/*
sudo systemctl start docker
```
