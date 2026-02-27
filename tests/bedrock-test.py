#! /usr/bin/env python3

import json, os, configparser
import boto3
from botocore.exceptions import ClientError

def write_aws_credentials(region, access_key, secret_key):
    # Define the directory and file paths
    aws_directory = os.path.expanduser("~/.aws")
    credentials_file = os.path.join(aws_directory, "credentials")
    config_file = os.path.join(aws_directory, "config")

    # Create the ~/.aws directory if it does not exist
    if not os.path.exists(aws_directory):
        os.makedirs(aws_directory)
        print(f"Created directory: {aws_directory}")

    # Load existing configurations or initialize new config parsers
    credentials_config = configparser.ConfigParser()
    if os.path.exists(credentials_file):
        credentials_config.read(credentials_file)

    config_config = configparser.ConfigParser()
    if os.path.exists(config_file):
        config_config.read(config_file)

    # Check if [bedrock] already exists in credentials
    if 'bedrock' not in credentials_config:
        credentials_config['bedrock'] = {
            'aws_access_key_id': access_key,
            'aws_secret_access_key': secret_key
        }
        with open(credentials_file, 'w') as f:
            credentials_config.write(f)
        print(f"Written to {credentials_file}: AWS credentials for [bedrock]")

    # Check if [profile bedrock] already exists in config
    if 'profile bedrock' not in config_config:
        config_config['profile bedrock'] = {
            'region': region
        }
        with open(config_file, 'w') as f:
            config_config.write(f)
        print(f"Written to {config_file}: AWS region configuration for [profile bedrock]")

# Use environment variables for region, access key, and secret key
aws_region = os.getenv('AWS_DEFAULT_REGION') or os.getenv('AWS_REGION')
aws_access_key_id = os.getenv('AWS_ACCESS_KEY_ID')
aws_secret_access_key = os.getenv('AWS_SECRET_ACCESS_KEY')

# Ensure all necessary environment variables are set
if aws_region and aws_access_key_id and aws_secret_access_key:
    write_aws_credentials(aws_region, aws_access_key_id, aws_secret_access_key)
else:
    print("Cannot write credentials to ~/.aws. Environment variables for AWS credentials and region are not set.")
    print("Please run:\n export AWS_ACCESS_KEY_ID=abcdefghijklmnopqrstuvwxyz")
    print("export AWS_ACCESS_KEY_ID=abcdefghijklmnopqrstuvwxyz")
    print("export AWS_SECRET_ACCESS_KEY=abcdefghijklmnopqrstuvwxyz\n...and try this script again.")

# After creds are verified we are ready test Bedrock

session = boto3.Session(profile_name='bedrock')
br = session.client(service_name="bedrock")
available_models = br.list_foundation_models()
print('\nList of available models on AWS Bedrock:\n')
amodel = None
for model in available_models['modelSummaries']:
    if 'anthropic' in model['modelId'].lower():
        if not amodel:
            amodel = model['modelId']
    print(model['modelId'])

if not amodel:
    print("\nNo Anthropic models found. Exiting.")
    exit(1)

bedrock = session.client(service_name="bedrock-runtime")
body = json.dumps({
  "max_tokens": 256,
  "messages": [{"role": "user", "content": "Hello, world"}],
  "anthropic_version": "bedrock-2023-05-31",
})

def invoke_test(model_id):
    response = bedrock.invoke_model(body=body, modelId=model_id)
    response_body = json.loads(response.get("body").read())
    print(f"\nResponse to 'Hello, world' with model {model_id}:\n", response_body.get("content")[0]['text'], flush=True)

try:
    invoke_test(amodel)
except ClientError as e:
    if e.response['Error']['Code'] == 'ValidationException' and 'inference profile' in str(e):
        print(f"Model {amodel} requires an inference profile, retrying with us.{amodel}")
        try:
            invoke_test(f'us.{amodel}')
        except ClientError as e2:
            print(f"An error occurred with us.{amodel}: {e2}")
    elif e.response['Error']['Code'] == 'AccessDeniedException':
        print(f"Access denied for model: {amodel}")
        print("You must request access to this model through the AWS console before you can use it.")
    else:
        print(f"An error occurred while checking access for model {amodel}: {e}")
except Exception as e:
    print(f"An unexpected error occurred with model {amodel}: {e}")

