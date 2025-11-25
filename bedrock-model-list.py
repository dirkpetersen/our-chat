#!/usr/bin/env python3

"""
Generate BEDROCK_AWS_MODELS string for LibreChat by testing model availability
with different prefixes (us., global., or no prefix).
"""

import sys
import json
import argparse
import boto3
from botocore.exceptions import ClientError

def test_model_with_prefix(bedrock_client, model_id, prefix="", strict=False, debug=False):
    """
    Test if a model works with the given prefix.
    Returns the working model ID or None if it doesn't work.
    """
    # Check if model_id already has a prefix (us. or global.)
    if model_id.startswith('us.') or model_id.startswith('global.'):
        # Already has a prefix, use as-is
        test_model_id = model_id
        # Extract base model ID for provider detection
        base_model_id = model_id.split('.', 1)[1] if '.' in model_id else model_id
    else:
        # No prefix, add the requested one
        test_model_id = f"{prefix}{model_id}" if prefix else model_id
        base_model_id = model_id

    # Prepare a minimal test payload based on model provider
    provider = base_model_id.split('.')[0].lower()

    if debug:
        print(f"  [DEBUG] Testing {test_model_id} (provider: {provider}, strict: {strict})", file=sys.stderr)

    try:
        # Prepare test body based on provider
        if provider == 'anthropic':
            body = json.dumps({
                "max_tokens": 10,
                "messages": [{"role": "user", "content": "Hi"}],
                "anthropic_version": "bedrock-2023-05-31",
            })
        elif provider == 'meta':
            body = json.dumps({
                "prompt": "Hi",
                "max_gen_len": 10,
            })
        elif provider == 'amazon':
            if 'embed' in base_model_id or 'titan-embed' in base_model_id:
                # Skip embedding models - they require different testing
                return None
            elif 'image' in base_model_id:
                # Skip image generation models
                return None
            body = json.dumps({
                "inputText": "Hi",
                "textGenerationConfig": {
                    "maxTokenCount": 10,
                }
            })
        elif provider == 'ai21':
            body = json.dumps({
                "prompt": "Hi",
                "maxTokens": 10,
            })
        elif provider == 'cohere':
            if 'embed' in base_model_id:
                # Skip embedding models
                return None
            body = json.dumps({
                "prompt": "Hi",
                "max_tokens": 10,
            })
        elif provider == 'mistral':
            body = json.dumps({
                "prompt": "Hi",
                "max_tokens": 10,
            })
        elif provider == 'stability':
            # Skip image generation models
            return None
        elif provider == 'openai':
            body = json.dumps({
                "messages": [{"role": "user", "content": "Hi"}],
                "max_tokens": 10,
            })
        else:
            # Generic attempt with messages format (most common)
            body = json.dumps({
                "messages": [{"role": "user", "content": "Hi"}],
                "max_tokens": 10,
            })

        # Try to invoke the model
        if strict:
            # In strict mode, try streaming which is what LibreChat actually uses
            response = bedrock_client.invoke_model_with_response_stream(
                body=body,
                modelId=test_model_id,
                accept="application/json",
                contentType="application/json"
            )
            # Try to read at least one event from the stream
            event_stream = response.get('body')
            for event in event_stream:
                if 'chunk' in event:
                    # Got a response chunk, model works
                    if debug:
                        print(f"    [RESULT] Got streaming response - model works!", file=sys.stderr)
                    return test_model_id
            # If no chunks, still check if we got past the initial request
            if debug:
                print(f"    [RESULT] Streaming invocation succeeded (no chunks yet, but request went through)", file=sys.stderr)
            return test_model_id
        else:
            # Regular invoke (faster)
            response = bedrock_client.invoke_model(
                body=body,
                modelId=test_model_id,
                accept="application/json",
                contentType="application/json"
            )
            # If we got here, the model invocation succeeded
            if debug:
                print(f"    [RESULT] Regular invocation succeeded - model works!", file=sys.stderr)
            return test_model_id

    except ClientError as e:
        error_code = e.response['Error']['Code']
        error_message = e.response['Error'].get('Message', '')
        error_message_lower = error_message.lower()

        if debug:
            print(f"    [ERROR] {error_code}: {error_message}", file=sys.stderr)

        if error_code == 'ResourceNotFoundException':
            # Model doesn't exist with this prefix - try next prefix
            if debug:
                print(f"    [RESULT] ResourceNotFoundException - model not found, trying next prefix", file=sys.stderr)
            return None
        elif error_code == 'ValidationException':
            # Check if it's a "model not found" type validation error
            # Look for specific patterns that indicate wrong prefix/model not available
            not_found_patterns = [
                'model not found',
                'does not exist',
                'not available',
                'cannot find',
                'unknown model',
                'unsupported model',
                'invalid model',
                'no model named',
                'model \'',  # Often followed by model name
            ]
            if any(pattern in error_message_lower for pattern in not_found_patterns):
                if debug:
                    print(f"    [RESULT] ValidationException with 'not found' pattern - rejecting prefix", file=sys.stderr)
                return None
            # In strict mode, ValidationException is more suspect - could be wrong prefix
            if strict:
                if debug:
                    print(f"    [RESULT] ValidationException in strict mode (streaming) - might be wrong prefix, skipping", file=sys.stderr)
                return None
            # Otherwise it's probably just our test payload format - model exists
            if debug:
                print(f"    [RESULT] ValidationException (non-strict) - assuming model exists", file=sys.stderr)
            return test_model_id
        elif error_code == 'AccessDeniedException':
            # Model exists but no access - count it as working for config
            if debug:
                print(f"    [RESULT] AccessDeniedException - model exists but no access (OK for config)", file=sys.stderr)
            return test_model_id
        elif error_code == 'ThrottlingException':
            # Throttled but model exists
            if debug:
                print(f"    [RESULT] ThrottlingException - model exists but throttled (OK)", file=sys.stderr)
            return test_model_id
        elif error_code == 'ModelStreamingNotSupportedException':
            # Model exists but doesn't support streaming - still valid
            if debug:
                print(f"    [RESULT] ModelStreamingNotSupportedException - model exists but no streaming", file=sys.stderr)
            return test_model_id
        else:
            # Other errors - be more strict in strict mode
            if 'not found' in error_message_lower or 'does not exist' in error_message_lower:
                if debug:
                    print(f"    [RESULT] Other error with 'not found' pattern - rejecting", file=sys.stderr)
                return None
            if strict:
                # In strict mode, unknown errors = model probably doesn't work
                if debug:
                    print(f"    [RESULT] Other error in strict mode - rejecting to be safe", file=sys.stderr)
                return None
            # In normal mode, be lenient
            if debug:
                print(f"    [RESULT] Other error (non-strict) - assuming model exists but request failed", file=sys.stderr)
            return test_model_id
    except Exception as e:
        # Any other error - skip
        if debug:
            print(f"    [EXCEPTION] {type(e).__name__}: {e}", file=sys.stderr)
        return None


def get_foundation_models(region='us-west-2'):
    """Get list of foundation models from Bedrock."""
    try:
        bedrock = boto3.client(service_name='bedrock', region_name=region)
        response = bedrock.list_foundation_models()
        return response.get('modelSummaries', [])
    except Exception as e:
        print(f"Error listing models: {e}", file=sys.stderr)
        sys.exit(1)


def filter_models(models, ignore_list):
    """Filter out models that start with any string in ignore_list."""
    if not ignore_list:
        return models

    filtered = []
    for model in models:
        model_id = model.get('modelId', '')
        should_ignore = False
        for ignore_prefix in ignore_list:
            if model_id.startswith(ignore_prefix.strip()):
                should_ignore = True
                break
        if not should_ignore:
            filtered.append(model)

    return filtered


def find_working_models(models, bedrock_runtime_client, verbose=False, strict=False, debug=False):
    """
    Test each model with different prefixes and return list of working model IDs.
    If strict=True, use streaming to validate (like LibreChat does).
    """
    working_models = []

    for model_summary in models:
        model_id = model_summary.get('modelId', '')

        if verbose:
            print(f"Testing {model_id}...", file=sys.stderr)

        # Try prefixes in order: us., global., no prefix
        for prefix in ['us.', 'global.', '']:
            working_id = test_model_with_prefix(bedrock_runtime_client, model_id, prefix, strict=strict, debug=debug)
            if working_id:
                if verbose:
                    prefix_str = f"with prefix '{prefix}'" if prefix else "without prefix"
                    print(f"  ✓ {model_id} works {prefix_str} -> {working_id}", file=sys.stderr)
                working_models.append(working_id)
                break
        else:
            if verbose:
                print(f"  ✗ {model_id} doesn't work with any prefix", file=sys.stderr)

    return working_models


def main():
    parser = argparse.ArgumentParser(
        description='Generate BEDROCK_AWS_MODELS string for LibreChat configuration'
    )
    parser.add_argument(
        '--first',
        type=str,
        default='',
        help='Comma-separated model IDs to place first in the list (e.g., us.anthropic.claude-3-5-sonnet-20241022-v2:0,meta.llama3-70b-instruct-v1:0)'
    )
    parser.add_argument(
        '--ignore',
        type=str,
        default='',
        help='Comma-separated list of model prefixes to ignore (e.g., "amazon.titan-embed,cohere.embed")'
    )
    parser.add_argument(
        '--region',
        type=str,
        default='us-west-2',
        help='AWS region to test models in (default: us-west-2)'
    )
    parser.add_argument(
        '--verbose', '-v',
        action='store_true',
        help='Print verbose testing information to stderr'
    )
    parser.add_argument(
        '--loose',
        action='store_true',
        help='Use lenient testing mode (faster but less accurate) - by default strict streaming mode is used'
    )
    parser.add_argument(
        '--debug',
        action='store_true',
        help='Show detailed error messages and testing information for each model'
    )
    parser.add_argument(
        '--format',
        choices=['env', 'list', 'yaml'],
        default='env',
        help='Output format: env (BEDROCK_AWS_MODELS=...), list (one per line), or yaml'
    )

    args = parser.parse_args()

    # Strict mode is default, --loose disables it
    strict_mode = not args.loose

    # Parse ignore list
    ignore_list = [s.strip() for s in args.ignore.split(',') if s.strip()]

    if args.verbose:
        mode = "LOOSE (lenient)" if args.loose else "STRICT (streaming validation)"
        print(f"Testing mode: {mode}", file=sys.stderr)
        print(f"Fetching models from region: {args.region}", file=sys.stderr)
        if ignore_list:
            print(f"Ignoring models starting with: {ignore_list}", file=sys.stderr)
        if args.first:
            print(f"Will place first: {args.first}", file=sys.stderr)
        print("", file=sys.stderr)

    # Get all foundation models
    models = get_foundation_models(args.region)

    if args.verbose:
        print(f"Found {len(models)} total models", file=sys.stderr)

    # Filter models
    filtered_models = filter_models(models, ignore_list)

    if args.verbose:
        print(f"Testing {len(filtered_models)} models after filtering", file=sys.stderr)
        print("", file=sys.stderr)

    # Create bedrock-runtime client for testing
    bedrock_runtime = boto3.client(
        service_name='bedrock-runtime',
        region_name=args.region
    )

    # Find working models
    working_models = find_working_models(filtered_models, bedrock_runtime, args.verbose, strict_mode, args.debug)

    if args.verbose:
        print("", file=sys.stderr)
        print(f"Found {len(working_models)} working models", file=sys.stderr)
        print("", file=sys.stderr)

    # Put --first models at the beginning if specified
    if args.first:
        first_models = [m.strip() for m in args.first.split(',') if m.strip()]
        first_working_models = []

        for first_model in first_models:
            # User has already validated --first models, just add them directly without testing
            # --ignore patterns do NOT apply to --first models (user explicitly wants these)
            first_working_models.append(first_model)
            if args.verbose:
                print(f"Using pre-validated --first model: {first_model}", file=sys.stderr)

        # Remove first models from working_models if they're already there
        # Use a set for faster deduplication
        first_model_set = set(first_working_models)
        working_models = [m for m in working_models if m not in first_model_set]

        # Add first models to the front in order
        working_models = first_working_models + working_models

        if args.verbose:
            print(f"After deduplication: {len(first_working_models)} from --first, {len(working_models) - len(first_working_models)} additional models", file=sys.stderr)
            print("", file=sys.stderr)

    # Final deduplication to ensure no duplicates in output (in case of any edge cases)
    seen = set()
    final_models = []
    for model in working_models:
        if model not in seen:
            seen.add(model)
            final_models.append(model)
    working_models = final_models

    # Output in requested format
    if args.format == 'env':
        print(f"BEDROCK_AWS_MODELS={','.join(working_models)}")
    elif args.format == 'list':
        for model in working_models:
            print(model)
    elif args.format == 'yaml':
        print("BEDROCK_AWS_MODELS:")
        for model in working_models:
            print(f"  - {model}")


if __name__ == '__main__':
    main()
