#! /usr/bin/env python3

import json
import boto3

br = boto3.client(service_name="bedrock")
available_models = br.list_foundation_models()
print('\nList of available models on AWS Bedrock:\n')
amodel = None
for model in available_models['modelSummaries']:
    if 'anthropic' in model['modelId']:
        amodel = model['modelId']
    print(model['modelId'])


bedrock = boto3.client(service_name="bedrock-runtime")
body = json.dumps({
  "max_tokens": 256,
  "messages": [{"role": "user", "content": "Hello, world"}],
  "anthropic_version": "bedrock-2023-05-31",
})
response = bedrock.invoke_model(body=body, modelId=amodel)
response_body = json.loads(response.get("body").read())
print("\nResponse to 'Hello, world':",response_body.get("content")[0]['text'], flush=True)
