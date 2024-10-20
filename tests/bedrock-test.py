#!/usr/bin/env python3

import json, os, configparser
import boto3
from botocore.exceptions import ClientError

def write_aws_credentials(region, access_key, secret_key):
    aws_directory = os.path.expanduser("~/.aws")
    credentials_file = os.path.join(aws_directory, "credentials")
    config_file = os.path.join(aws_directory, "config")

    if not os.path.exists(aws_directory):
        os.makedirs(aws_directory)
        print(f"Created directory: {aws_directory}")

    credentials_config = configparser.ConfigParser()
    if os.path.exists(credentials_file):
        credentials_config.read(credentials_file)

    config_config = configparser.ConfigParser()
    if os.path.exists(config_file):
        config_config.read(config_file)

    if 'default' not in credentials_config:
        credentials_config['default'] = {
            'aws_access_key_id': access_key,
            'aws_secret_access_key': secret_key
        }
        with open(credentials_file, 'w') as f:
            credentials_config.write(f)
        print(f"Written to {credentials_file}: AWS credentials for [default]")

    if 'default' not in config_config:
        config_config['default'] = {
            'region': region
        }
        with open(config_file, 'w') as f:
            config_config.write(f)
        print(f"Written to {config_file}: AWS region configuration for [default]")

# Use environment variables for region, access key, and secret key
aws_region = os.getenv('AWS_DEFAULT_REGION') or os.getenv('AWS_REGION')
aws_access_key_id = os.getenv('AWS_ACCESS_KEY_ID')
aws_secret_access_key = os.getenv('AWS_SECRET_ACCESS_KEY')

# Ensure all necessary environment variables are set
if aws_region and aws_access_key_id and aws_secret_access_key:
    write_aws_credentials(aws_region, aws_access_key_id, aws_secret_access_key)
else:
    print("Cannot write credentials to ~/.aws. Environment variables for AWS credentials and region are not set.")
    print("Please run:")
    print("export AWS_DEFAULT_REGION=your_region")
    print("export AWS_ACCESS_KEY_ID=your_access_key")
    print("export AWS_SECRET_ACCESS_KEY=your_secret_key")
    print("...and try this script again.")
    exit(1)

# Initialize Bedrock clients
bedrock = boto3.client(service_name="bedrock")
bedrock_runtime = boto3.client(service_name="bedrock-runtime")

# Get list of available models
try:
    available_models = bedrock.list_foundation_models()
except ClientError as e:
    print(f"Error listing foundation models: {e}")
    exit(1)

print('\nChecking access for available models on AWS Bedrock:\n')

anthropic_model_tested = False

for model in available_models['modelSummaries']:
    model_id = model['modelId']
    print(f"Checking model: {model_id}")
    
    try:
        # Check model access
        response = bedrock.get_model_access(modelId=model_id)
        access_status = response.get('status', 'Unknown')
        print(f"Access status for model {model_id}: {access_status}")
        
        if access_status != 'Allowed':
            print("Requesting access...")
            try:
                bedrock.create_model_access_request(modelId=model_id)
                print(f"Access request submitted for model: {model_id}")
            except ClientError as request_error:
                print(f"Failed to request access for model {model_id}: {request_error}")
        elif 'anthropic' in model_id.lower() and not anthropic_model_tested:
            print(f"Testing 'Hello, world' on Anthropic model: {model_id}")
            try:
                body = json.dumps({
                    "max_tokens": 256,
                    "messages": [{"role": "user", "content": "Hello, world"}],
                    "anthropic_version": "bedrock-2023-05-31",
                })
                response = bedrock_runtime.invoke_model(body=body, modelId=model_id)
                response_body = json.loads(response.get("body").read())
                print(f"Response: {response_body.get('content')[0]['text']}")
                anthropic_model_tested = True
            except Exception as e:
                print(f"Error testing Anthropic model: {e}")
    except ClientError as e:
        if e.response['Error']['Code'] == 'AccessDeniedException':
            print(f"Access denied for model: {model_id}")
            print("Requesting access...")
            try:
                bedrock.create_model_access_request(modelId=model_id)
                print(f"Access request submitted for model: {model_id}")
            except ClientError as request_error:
                print(f"Failed to request access for model {model_id}: {request_error}")
        else:
            print(f"An error occurred while checking access for model {model_id}: {e}")
    except Exception as e:
        print(f"An unexpected error occurred with model {model_id}: {e}")
    print()

print("Access check and request process completed.")