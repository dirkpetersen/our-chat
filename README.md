# Our Chat !

**An easy to install Enterprise LLM chat system using LibreChat with AWS Bedrock and LDAP/AD authentication.** 

Why is this needed? Can't users just access AWS Bedrock directly? They might, however, in most organizations the AWS Console is reserved for power users, as it typically takes some time until you are familiar with it (to put it mildly). [LibreChat](https://www.librechat.ai/) on the other hand, takes zero on-boarding time, users just login with their enterprise credentials and enter their prompts. Another reason is LibreChat's superior user interface. It has gained extreme popularity and is among the top 10 projects on Github.

![image](https://github.com/user-attachments/assets/85422848-7875-4c87-8f62-2582e8e07775)


## Prerequisites 

- Get a RHEL virtual server (this process was tested with RHEL 9.4) with at least 8GB RAM and 50GB free disk space of which about half should be under /home . 
- That machine must be able to talk to the `ldaps port 636` of your enterprise LDAP server (for example Active Directory). 
- An LDAP/AD security group that contains the users who are allowed to use the chat system. For now we call this group `our-chat-users`.
- An SSL certificate, unless you use Let's encrypt
- AWS credentials (AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY) for an AWS service account (perhaps called librechat or ochat) that has no permissions except for the AmazonBedrockFullAccess policy attached to it. 
- You don't require root access if your sysadmins can run the `prepare-server.sh` script for you, but they should allow you to switch to the ochat user, e.g. `sudo su - ochat`

## Prepare Server 

Run the [prepare-server.sh](https://raw.githubusercontent.com/dirkpetersen/our-chat/refs/heads/main/prepare-server.sh) script as root user to install docker and prepare the ochat user account. You can also start it as a normal user if you have requested the correct [sudo config](#i-dont-have-root-permissions)

```
curl https://raw.githubusercontent.com/dirkpetersen/our-chat/refs/heads/main/prepare-server.sh?token=$(date +%s) | bash
```

Now switch to the ochat user `sudo su - ochat` and continue with configuration.

## AWS connectivity

After you have switched ochat user using `sudo su - ochat`, first configure AWS credentials: run `aws configure` and enter AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY and your region (e.g. us-west-2) for the AWS service account that has only the  AmazonBedrockFullAccess policy attached. You can also edit `~/.aws/credentials` and `~/.aws/config` directly, if you prefer.  

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

If you don't get that or the script shows an error, go back to your AWS Administrator for troubleshooting before you continue.

As LibreChat does not support API access you can give API users Bedrock API access in their AWS account and bedrock-test.py may serve as a good initial example. 

You can find more details about AWS in the AWS budget section below. 

## SSL certificates 

Here we cover the standard case, which is you receiving SSL certs from your enterrprise team. In many cases your team will send you a PKCS12 archive which comes as a *.pfx file along with a password. At the end of this process you should have `~/our-chat.pem` and `~/our-chat.pw` at the root of the ochat home directory. (Please note: If you leave a space at the beginning of the echo "yourpassword" line, the password will not end up in your bash history)

```
 echo "yourpassword" > ~/our-chat.pw
chmod 600 ~/our-chat.pw
openssl rsa -in original-cert.pfx -out > ~/our-chat.pem
```

## LibreChat install and Configuration

Instead of installing LibreChat directly, please clone the our-chat repository from GitHub and copy the .env.ochat, librechat.yml and nginx.conf files to the root of the home directory of the ochat user:

```
cd ~
git clone https://github.com/dirkpetersen/our-chat/
cp ~/our-chat/.env.ochat ~/.env
cp ~/our-chat/librechat.yaml ~/librechat.yaml
cp ~/our-chat/nginx.conf ~/nginx.conf
```

You will likelty need to edit each of these config files at some point, but for now you only need to edit the `~/.env` file to enable LDAP authentication and to update a few security tokens

### .env

Please find these settings in .env

```
LDAP_URL=ldaps://ldap.domain.edu:636
LDAP_USER_SEARCH_BASE=OU=User Accounts,dc=domain,dc=edu
LDAP_BIND_DN=CN=myserviceaccount,OU=Service Accounts,OU=User Accounts,DC=domain,DC=edu
LDAP_BIND_CREDENTIALS="ad-password"
LDAP_LOGIN_USES_USERNAME=true
LDAP_SEARCH_FILTER=(&(sAMAccountName={{username}})(memberOf=CN=our-chat-users,OU=Groups,DC=domain,DC=edu))
LDAP_FULL_NAME=displayName
```

They should be pretty self explanatory, for example `LDAP_LOGIN_USES_USERNAME` means that you can login with your username instead of typing your entire email address. The LDAP_SEARCH_FILTER is a bit of a crutch that we use to restrict LibreChat to members of an AD/LDAP security group. The filter was not intended for authorization and if a new user is not member of that group, they will be a 401 error (AuthN) instead of 403 (AuthZ). This can be a bit confusing. On some LDAP systems the LDAP_BIND_DN can be the email address (aka service principal) of the service accout, e.g. `myserviceaccount@domain.edu` but it is safest to use the DN (distinguished name).


After you have configured all these 7 settings, please use the LDAP test script to verify these settings. To check the LDAP_SEARCH_FILTER you have to pass the username of a test user who is member of that security group (e.g. our-chat-users)

```
~/our-chat/tests/ldap-test.py peterdir

/ldap-test.py
Successfully read environment variables: ['LDAP_URL', 'LDAP_USER_SEARCH_BASE', 'LDAP_BIND_DN', 'LDAP_BIND_CREDENTIALS', 'LDAP_LOGIN_USES_USERNAME', 'LDAP_SEARCH_FILTER', 'LDAP_FULL_NAME']

Connected as: CN=myserviceaccount,OU=Service Accounts,OU=User Accounts,DC=domain,DC=edu

Evaluating LDAP_SEARCH_FILTER with testuser peterdir:

Evaluating search filter: (&(sAMAccountName=peterdir)(memberOf=CN=our-chat-users,OU=Groups,DC=domain,DC=edu))
Found 1 matching entries:
DN: CN=peterdir,OU=User Accounts,DC=ohsum01,DC=ohsu,DC=edu
Attributes:
  displayName: Dirk Petersen
  memberOf: ['CN=unix_ochat,OU=Groups,DC=domain,DC=edu', ......
```

And as a final step we want to setup unique tokens for 

CREDS_KEY, CREDS_IV, JWT_SECRET, JWT_REFRESH_SECRET and MEILI_MASTER_KEY

Go to https://www.librechat.ai/toolkit/creds_generator, generate keys and put them in ~/.env 

```
vi ~/.env
```

You can 

### librechat.yml (optional)

For example, use `vi ~/librechat.yml && cp ~/librechat.yml ~/LibreChat/librechat.yml` to change the terms of service, modify the site footer and change a few advanced bedrock settings, for example allowed AWS regions,

### nginx.conf (optional)

The only change `~/nginx.conf` likely requires, is setting the filenames for the  SSL certiticates for httpsi if you choose a different cerificate name than our-chat.pem .

```
   ssl_certificate /etc/librechat/ssl/our-chat.pem;
   ssl_certificate_key /etc/librechat/ssl/our-chat.pem;
   ssl_password_file /etc/librechat/ssl/our-chat.pw;
```

# Install LibreChat

If all the prep work is done correctly we should be able to run `install-librechat.sh` and have a running system in a few seconds 

```
~/our-chat/install-librechat.sh

Cloning into 'LibreChat'...
remote: Enumerating objects: 33792, done.
remote: Counting objects: 100% (5880/5880), done.
remote: Compressing objects: 100% (1247/1247), done.
remote: Total 33792 (delta 5103), reused 4786 (delta 4622), pack-reused 27912 (from 1)
Receiving objects: 100% (33792/33792), 43.72 MiB | 44.24 MiB/s, done.
Resolving deltas: 100% (24182/24182), done.
Copying /home/ochat/LibreChat/deploy-compose.yml to /home/ochat/LibreChat/deploy-compose-ourchat.yml
~/.awsrc has been added to .bashrc
Copying /home/ochat/.env to /home/ochat/LibreChat/.env and expanding env vars
Copying /home/ochat/librechat.yaml to /home/ochat/LibreChat/librechat.yaml
Copying /home/ochat/nginx.conf to /home/ochat/LibreChat/client/nginx.conf
Generating DH parameters, 2048 bit long safe prime
.
.
[+] Running 8/8
 ✔ Network librechat_default       Created
 ✔ Volume "librechat_pgdata2"      Created 
 ✔ Container chat-mongodb          Started 
 ✔ Container chat-meilisearch      Started 
 ✔ Container librechat-vectordb-1  Started 
 ✔ Container librechat-rag_api-1   Started 
 ✔ Container LibreChat-API         Started 
 ✔ Container LibreChat-NGINX       Started 

no crontab for ochat
Cron job added to run /home/ochat/purge_old_messages.py daily at 2:22 AM

stopping: docker compose -f /home/ochat/LibreChat/deploy-compose-ourchat.yml down
starting: docker compose -f /home/ochat/LibreChat/deploy-compose-ourchat.yml up -d
```

Now try to access your chat system, e.g. `https://ourchat.domain.edu`. If you encounter issues, please see the [troubleshooting](#troubleshooting) section below.


## Longer term vision 

In the future. 

![our-chat-dark](https://github.com/dirkpetersen/our-chat/assets/1427719/6fbbc55d-8bf3-4c7f-8d09-990c3ee3c2e6)


## Troubleshooting 

### Get debug output

If something is not working, the first step is to enable debugging and bringing up the docker containers in non-daemon mode so that they are printing all logs to the console. Setup debug output, open ~/.env in editor 

```
vi ~/.env && cp ~/.env ~/LibreChat/
```

and set `DEBUG_LOGGING=true` 

Open up a second terminal, shutdown the containers and bring them up again, this time  (`up without a -d`)

```
docker compose -f ~/LibreChat/deploy-compose-ourchat.yml down
docker compose -f ~/LibreChat/deploy-compose-ourchat.yml up
```

Check for error messages. When you are done, execute the `down` and then the `up -d`. command 

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
