#! /usr/bin/env python3

import os, boto3, json

#reg = os.getenv('AWS_REGION_NAME','us-west-2')
#br = boto3.client(service_name="bedrock", region_name=reg)
br = boto3.client(service_name="bedrock")

# Let's see all available Anthropic Models
available_models = br.list_foundation_models()

amodel = None
for model in available_models['modelSummaries']:
    if 'anthropic' in model['modelId']:
        amodel = model['modelId']
    print(model['modelId'])

bedrock = boto3.client(service_name="bedrock-runtime")
body = json.dumps({
  "max_tokens": 256,
  "messages": [{"role": "user", "content": "Hello, world"}],
})
response = bedrock.invoke_model(body=body, modelId=amodel)
response_body = json.loads(response.get("body").read())
print("Response to 'Hello, world':",response_body.get("content"), flush=True)
