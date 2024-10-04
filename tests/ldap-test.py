#! /usr/bin/env python3

import sys
import os
try:
    import ldap3
    import dotenv
except:
    print('ldap3/dotenv missing, to install run:\n python3 -m pip install --upgrade ldap3 python-dotenv')
    sys.exit(1)

testuser = 'peterdir'

def load_env_file(env_file_path):
    if not os.path.exists(env_file_path):
        print(f"Error: .env file not found at {env_file_path}")
        print("Please provide the path to the .env file as a command-line argument.")
        sys.exit(1)
    
    dotenv.load_dotenv(env_file_path)
    required_vars = ['LDAP_URL', 'LDAP_USER_SEARCH_BASE', 'LDAP_BIND_DN', 'LDAP_BIND_CREDENTIALS', 'LDAP_LOGIN_USES_USERNAME', 'LDAP_SEARCH_FILTER', 'LDAP_FULL_NAME']
    missing_vars = [var for var in required_vars if not os.getenv(var)]
    
    if missing_vars:
        print(f"Error: The following required variables are missing from the .env file: {', '.join(missing_vars)}")
        sys.exit(1)
    
    print(f'Successfully read environment variables: {required_vars}\n')

def parse_ldap_url(url):
    parts = url.split('://')
    if len(parts) != 2:
        print(f"Error: Invalid LDAP_URL format: {url}")
        sys.exit(1)
    
    protocol, server_port = parts
    server_parts = server_port.split(':')
    
    if len(server_parts) == 2:
        server, port = server_parts
        port = int(port)
    else:
        server = server_parts[0]
        port = 636 if protocol == 'ldaps' else 389
    
    use_ssl = protocol == 'ldaps'
    return server, port, use_ssl

def ldap_authn(server, bind_dn, bind_credentials):
    try:
        return ldap3.Connection(server, user=bind_dn, password=bind_credentials, auto_bind=True)
    except ldap3.core.exceptions.LDAPBindError as e:
        print(f"Authentication failed: {str(e)}")
    except ldap3.core.exceptions.LDAPSocketOpenError as e:
        print(f"Cannot connect to server {server}: {str(e)}")
    except Exception as e:
        print(f"Error: {str(e)}")
    return None

def get_short_username(dn):
    # Extract the short username from a DN    
    cn = ldap3.utils.dn.parse_dn(dn)[0][1]
    return cn

def eval_search_filter(conn, search_base, search_filter, username):
    # Validate LDAP_SEARCH_FILTER, Replace {{username}} with the actual username
    actual_filter = search_filter.replace('{{username}}', username)
    print(f"Evaluating search filter: {actual_filter}")

    # Perform the search
    conn.search(
        search_base=search_base,
        search_filter=actual_filter,
        attributes=[os.getenv('LDAP_FULL_NAME', 'displayName'), 'memberOf']
    )

    if len(conn.entries) == 0:
        print("No entries found matching the search filter.")
        return None

    print(f"Found {len(conn.entries)} matching entries:")
    for entry in conn.entries:
        print(f"DN: {entry.entry_dn}")
        print("Attributes:")
        for attr in entry.entry_attributes:
            print(f"  {attr}: {entry[attr].value}")
        print()

    return conn.entries

if __name__ == "__main__":
    
    env_file_path = '.env'    
    if not os.path.isfile(env_file_path):
        if len(sys.argv) != 2:
            print("Usage: python script.py </folder/.env>")
            sys.exit(1)
        env_file_path = sys.argv[1]

    if not env_file_path.endswith('.env'):
        env_file_path = os.path.join(env_file_path,'.env')

    load_env_file(env_file_path)

    ldap_url = os.getenv('LDAP_URL')
    server, port, use_ssl = parse_ldap_url(ldap_url)

    server = ldap3.Server(server, port=port, use_ssl=use_ssl, get_info=ldap3.ALL)

    bind_dn = os.getenv('LDAP_BIND_DN')
    bind_credentials = os.getenv('LDAP_BIND_CREDENTIALS')
    search_base = os.getenv('LDAP_USER_SEARCH_BASE')
    search_filter = os.getenv('LDAP_SEARCH_FILTER')

    conn = ldap_authn(server, bind_dn, bind_credentials)
    if not conn:
        sys.exit(1)

    print("Connected as:", conn.user)

    # Evaluate the search filter
    print(f"\nEvaluating LDAP_SEARCH_FILTER with testuser {testuser}:\n ")
    eval_search_filter(conn, search_base, search_filter, testuser)