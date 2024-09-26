#! /usr/bin/env python3

import datetime
import pymongo

""" 
 # Some organizations want to purge older messages 
 # to stay compliant with their regulatory framework
"""  

DAYSAGO=30

client = pymongo.MongoClient("mongodb://127.0.0.1:27017")
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

