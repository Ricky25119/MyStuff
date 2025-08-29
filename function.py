from datetime import datetime, timezone, timedelta
import logging
import azure.functions as func
from azure.storage.blob import generate_blob_sas, BlobServiceClient,BlobSasPermissions
from azure.core.exceptions import ResourceNotFoundError, ResourceExistsError
import re
import os, json

app = func.FunctionApp()

@app.function_name(name="mytimer")
@app.timer_trigger(schedule="0 */5 * * * *", 
              arg_name="mytimer",
              run_on_startup=False) 
def test_function(mytimer: func.TimerRequest) -> None:
    utc_timestamp = datetime.utcnow().replace(
        tzinfo=timezone.utc).isoformat()
    if mytimer.past_due:
        logging.info('The timer is past due!')
    logging.info('Python timer trigger function ran at %s', utc_timestamp)
    # Replace with your actual connection string
    function_app_sa_connection_string = os.environ.get('AzureWebJobsStorage')
    source_sa_connection_string = os.environ.get('SOURCE_SA_CS') 


    # Fetch destination storage accounts as a dict from environment variable
    
    destination_sa_connection_strings = os.environ.get('DESTINATIONS')

    if destination_sa_connection_strings:
        destination_sa_connection_strings = json.loads(destination_sa_connection_strings)
    else:
        destination_sa_connection_strings = {}

    # Container and blob names
    container_name = "function-state"
    blob_name = "timestamp.txt"

    containers = ["source1","source2","source3","source4","source5"]
    ## Remove the old list format, now using dict above

    # Initialize client
    blob_service_client = BlobServiceClient.from_connection_string(function_app_sa_connection_string)

    # Create container if it doesn't exist
    try:
        blob_service_client.create_container(container_name)
        print(f" Created container: {container_name}")
    except Exception as e:
        print(f" Container may already exist: {e}")

    # Create blob with current UTC timestamp
    blob_client = blob_service_client.get_blob_client(container=container_name, blob=blob_name)
    timestamp = datetime.now(timezone.utc).isoformat()


    # Read timestamp from blob
    try:
        downloaded_blob = blob_client.download_blob().readall()
        timestamp_str = downloaded_blob.decode('utf-8')
        print(f"Blob content: {timestamp_str}")
        timestamp_dt = datetime.fromisoformat(timestamp_str)
    except Exception as e:
        print(f"Failed to read blob: {e}")
        timestamp_dt = None


    # Fetch all blobs from the given containers in the source storage account and print their last modified date
    blob_source = BlobServiceClient.from_connection_string(source_sa_connection_string)


    # Print only blobs modified after the timestamp in timestamp.txt
    if timestamp_dt:
        for container in containers:
            print(f"\nContainer: {container}")
            try:
                container_client = blob_source.get_container_client(container)
                blobs_list = container_client.list_blobs()
                for blob in blobs_list:
                    if blob.last_modified and blob.last_modified > timestamp_dt:
                        last_modified = blob.last_modified.strftime('%Y-%m-%d %H:%M:%S')
                        print(f"Blob: {blob.name}, Last Modified: {last_modified}")

                        # Copy blob to all destination storage accounts
                        source_blob_client = container_client.get_blob_client(blob.name)
                        # Generate SAS token for the source blob
                        
                        def extract_account_info(conn_str):
                            name_match = re.search(r'AccountName=([^;]+)', conn_str)
                            key_match = re.search(r'AccountKey=([^;]+)', conn_str)
                            account_name = name_match.group(1) if name_match else None
                            account_key = key_match.group(1) if key_match else None
                            return account_name, account_key
                        source_account_name, source_account_key = extract_account_info(source_sa_connection_string)
                        sas_token = generate_blob_sas(
                            account_name=source_account_name,
                            container_name=container,
                            blob_name=blob.name,
                            account_key=source_account_key,
                            permission=BlobSasPermissions(read=True),
                            expiry=datetime.utcnow() + timedelta(hours=1)
                        )
                        source_blob_url = f"{source_blob_client.url}?{sas_token}"
                        for dest_account_name, dest_conn_str in destination_sa_connection_strings.items():
                            dest_service_client = BlobServiceClient.from_connection_string(dest_conn_str)
                            dest_container_client = dest_service_client.get_container_client(container)
                            try:
                                dest_container_client.create_container()
                            except Exception:
                                pass  # Container may already exist
                            dest_blob_client = dest_container_client.get_blob_client(blob.name)
                            try:
                                dest_blob_client.start_copy_from_url(source_blob_url)
                                print(f"  Copied '{blob.name}' to destination container '{container}' in account '{dest_account_name}'")
                            except Exception as e:
                                print(f"  Failed to copy '{blob.name}' to destination '{dest_account_name}': {e}")
            except Exception as e:
                print(f"Failed to fetch blobs from container '{container}': {e}")

    ## Remove old blob_destination initialization, not needed with dict format




    try:
        blob_client.upload_blob(timestamp, overwrite=True)
        print(f" Uploaded blob '{blob_name}' with timestamp: {timestamp}")
    except Exception as e:
        print(f" Failed to upload blob: {e}")


    # # Read the content of the blob and print it

    # fun_app_storage = os.environ.get("AzureWebJobsStorage")
    # if not fun_app_storage:
    #     logging.error("AzureWebJobsStorage environment variable is not set.")
    #     return
    # blob_container = BlobServiceClient.from_connection_string(fun_app_storage)
    # container_name = 'functionstorage'
    # blob_name = 'timestamp.txt'
    # try:
    #     blob_container.create_container(container_name)
    # except ResourceExistsError:
    #     pass
    # blob_file = blob_container.get_blob_client(container_name, blob_name)
    # try:
    #     content = blob_file.download_blob().readall().decode("utf-8").strip()
    #     logging.info(f"Existing timestamp: {content}")
    # except ResourceNotFoundError:
    #     logging.info("Timestamp file not found. It will be created.")
    
    # now_utc = datetime.now(timezone.utc).isoformat()
    # blob_file.upload_blob(now_utc, overwrite=True)
    # logging.info(f"Updated timestamp to: {now_utc}")
