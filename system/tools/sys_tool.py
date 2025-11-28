import requests
import yaml

# Parses a given configuration string in YAML format.
def parse_config(config_str):
    # Potential unsafe load if not careful, though Snyk checks dependencies primarily here
    # Uses the yaml.load function to parse the string.
    return yaml.load(config_str, Loader=yaml.Loader)

# Fetches an update from a remote server.
def fetch_update():
    # Old requests library
    # Makes a GET request to an insecure URL.
    r = requests.get('http://insecure-update-server.local')
    # Prints the status code of the response.
    print(r.status_code)

# Main execution block.
if __name__ == "__main__":
    # Prints a message to indicate that the tool is running.
    print("System Config Tool Running")
