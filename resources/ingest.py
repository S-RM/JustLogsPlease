import json
import urllib3
import time
import os

def submit_to_LAW(endpoint_uri, dcr_id, access_token, log_type, log):
    headers = {
        "Authorization": f"Bearer {access_token}",
        "Content-Type": "application/json",
    }

    uri = f"{endpoint_uri}/dataCollectionRules/{dcr_id}/streams/Custom-{log_type}_CL?api-version=2021-11-01-preview"
    max_retries = 3
    retry_count = 0

    while retry_count < max_retries:
        try:
            http = urllib3.PoolManager()
            response = http.request("POST", uri, headers=headers, body=json.dumps(log).encode("utf-8"))
            if response.status == 204:
                return response
            else:
                retry_count += 1
                time.sleep(1)
        except Exception as e:
            retry_count += 1
            time.sleep(1)

    raise Exception(f"Failed to submit log after {max_retries} retries. {e}")

tenant_id = os.environ["tenantId"]
app_id = os.environ["appId"]
app_secret = os.environ["appSecret"]

scope = "https://monitor.azure.com//.default"
body = f"client_id={app_id}&scope={scope}&client_secret={app_secret}&grant_type=client_credentials"
headers = {
    "Content-Type": "application/x-www-form-urlencoded"
}

uri = f"https://login.microsoftonline.com/{tenant_id}/oauth2/v2.0/token"

http = urllib3.PoolManager()
response = http.request("POST", uri, headers=headers, body=body.encode("utf-8"))

if response.status == 200:
    response_body = json.loads(response.data.decode("utf-8"))
    access_token = response_body["access_token"]
else:
    raise Exception(f"Failed to get access token. Response code: {response.status}")
