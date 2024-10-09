#! /usr/bin/env python3

import sys, datetime
try:
    import pymongo
except:
    print('pymongo missing, to install run:\n python3 -m pip install --upgrade pymongo')
    sys.exit(1)

""" 
 # Some organizations want to purge older messages 
 # to stay compliant with their regulatory framework
"""  

DAYSAGO=60
PORT='27018'

client = pymongo.MongoClient(f"mongodb://127.0.0.1:{PORT}")
# print(client.server_info())
db = client['LibreChat']
messages = db['messages']
files = db['files']

# Calculate the date X days ago from today
time_ago = datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(days=DAYSAGO)

# Delete all messages and files where 'createdAt' is older than X days
messages_result = messages.delete_many({"createdAt": {"$lt": time_ago}})
files_result = files.delete_many({"createdAt": {"$lt": time_ago}})

# Output the result of the deletion
print(f"Deleted {messages_result.deleted_count} messages.")
print(f"Deleted {files_result.deleted_count} files.")

