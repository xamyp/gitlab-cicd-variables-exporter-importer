# GitLab CI/CD Variables Exporter-Importer

A bash script to easily export and import CI/CD variables between GitLab projects. This tool helps you transfer all your CI/CD variables from one GitLab project to another with proper error handling and detailed reporting.

## Features

- Export all CI/CD variables from a source GitLab project
- Import variables to a destination GitLab project
- Handle large numbers of variables with pagination
- Preserve variable attributes (protected, masked, environment scope)
- Detailed reporting of successes and failures
- Automatic JSON validation and correction

## Prerequisites

- Bash shell (version 4.0+)
- curl (version 7.0+)
- jq (version 1.5+)
- Python 3 (optional, for advanced JSON fixing)
- GitLab access token with API scope
- API access to both source and destination GitLab projects

### GitLab Access Token Requirements

You need a GitLab Personal Access Token with the following permissions:
- `api` scope - Required to access the GitLab API
- Read access to the source project
- Write access to the destination project

To create a token:
1. Go to your GitLab profile (click your avatar → Settings)
2. Navigate to Access Tokens
3. Create a new personal access token with the "api" scope
4. Save the token securely - you will need to add it to the script

## Installation

1. Clone this repository:
git clone https://github.com/xamyp/gitlab-cicd-variables-exporter-importer.git cd gitlab-cicd-variables-exporter-importer

2. Make the script executable:
chmod +x gitlab_variables_migration.sh

3. Edit the script to set your GitLab URL, token, and project IDs:
TOKEN="glpat-your-token-here" SOURCE_PROJECT_ID="source-project-id" DESTINATION_PROJECT_ID="destination-project-id" GITLAB_URL="https://your-gitlab-instance.com"

## Usage

Just run the script after configuration:

./gitlab_variables_migration.sh

The script will:
1. Export all CI/CD variables from the source project
2. Save them to a JSON file
3. Import them to the destination project
4. Generate a report of successes and failures

## Output Files

The script generates several files:
- `gitlab_cicd_variables_SOURCE_ID.json`: Raw export of variables
- `gitlab_cicd_variables_SOURCE_ID_fixed.json`: Validated and fixed JSON
- `gitlab_cicd_failed_vars_SOURCE_ID_to_DEST_ID.txt`: Report of any failed variables

## Troubleshooting

### API Access Issues
- Ensure your token has the correct permissions
- Verify that the project IDs are correct
- Check that you have appropriate access to both projects

### JSON Parsing Errors
The script attempts to automatically fix JSON issues, but if problems persist:
- Manually inspect the output JSON files
- Check for unusual characters in your variable values
- Try running the script with a subset of variables

### Rate Limiting
If you encounter rate limiting from GitLab's API:
- Add delays between API calls by modifying the script
- Split large migrations into smaller batches

## Contributing

Contributions, issues, and feature requests are welcome! Feel free to check the issues page.
