#! /usr/bin/env python3

import os, boto3, json

reg = os.getenv('AWS_REGION_NAME','us-west-2')

model='anthropic.claude-3-opus-20240229-v1:0'
#model='anthropic.claude-3-sonnet-20240229-v1:0'

br = boto3.client(service_name="bedrock", region_name=reg)

# Let's see all available Anthropic Models
available_models = br.list_foundation_models()

for model in available_models['modelSummaries']:
    #if 'anthropic' in model['modelId']:
    print(model['modelId'])

bedrock = boto3.client(service_name="bedrock-runtime", region_name=reg)
body = json.dumps({
  "max_tokens": 256,
  "messages": [{"role": "user", "content": "Hello, world"}],
  "anthropic_version": "bedrock-2023-05-31"
})

response = bedrock.invoke_model(body=body, modelId=model)

response_body = json.loads(response.get("body").read())
print(response_body.get("content"), flush=True)
