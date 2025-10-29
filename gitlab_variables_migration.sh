#!/bin/bash

TOKEN="glpat-xxxxxxxxxxx"
SOURCE_ID="xxxx"
DESTINATION_ID="xxxx"
SOURCE_TYPE="project" # Can be "project" or "group"
DESTINATION_TYPE="project" # Can be "project" or "group"
GITLAB_URL="https://git.test.com"
API_URL="${GITLAB_URL}/api/v4"
OUTPUT_FILE="gitlab_cicd_variables_${SOURCE_TYPE}_${SOURCE_ID}.json"
FIXED_OUTPUT_FILE="gitlab_cicd_variables_${SOURCE_TYPE}_${SOURCE_ID}_fixed.json"
TEMP_OUTPUT_FILE=$(mktemp)
FAILED_VARS_FILE=$(mktemp)

# Creating a file to store failed variables
echo "[]" > "$FAILED_VARS_FILE"

# Function to get the API endpoint based on entity type (project or group)
get_api_endpoint() {
    local entity_type="$1"
    local entity_id="$2"
    local endpoint=""
    
    if [ "$entity_type" = "project" ]; then
        endpoint="projects/${entity_id}"
    elif [ "$entity_type" = "group" ]; then
        endpoint="groups/${entity_id}"
    else
        echo "Error: Invalid entity type. Must be 'project' or 'group'."
        exit 1
    fi
    
    echo "$endpoint"
}

# Checking dependencies
for cmd in curl jq; do
    if ! command -v $cmd &> /dev/null; then
        echo "Error: $cmd is not installed. Please install it to continue."
        exit 1
    fi
done

SOURCE_ENDPOINT=$(get_api_endpoint "$SOURCE_TYPE" "$SOURCE_ID")
DESTINATION_ENDPOINT=$(get_api_endpoint "$DESTINATION_TYPE" "$DESTINATION_ID")

echo "Exporting CI/CD variables from ${SOURCE_TYPE} $SOURCE_ID from $GITLAB_URL..."

# Initializing an empty array in the temporary file
echo "[]" > "$TEMP_OUTPUT_FILE"

# Retrieving CI/CD variables from the source project/group with pagination
page=1
per_page=100
total_variables=0

while true; do
    echo "Retrieving page $page (100 variables per page)..."
    
    # Creating a temporary file for this page
    page_file=$(mktemp)
    
    # Retrieving a page of variables
    HTTP_CODE=$(curl --header "PRIVATE-TOKEN: $TOKEN" \
         --silent \
         --write-out "%{http_code}" \
         --output "$page_file" \
         "${API_URL}/${SOURCE_ENDPOINT}/variables?page=${page}&per_page=${per_page}")
    
    # Checking HTTP code
    if [ "$HTTP_CODE" -ne 200 ]; then
        echo "HTTP Error $HTTP_CODE while retrieving page $page"
        cat "$page_file"
        rm "$page_file"
        break
    fi
    
    # Checking if the file is empty or contains an empty list
    if [ ! -s "$page_file" ] || [ "$(cat "$page_file" | jq 'length')" -eq 0 ]; then
        echo "No more variables to retrieve."
        rm "$page_file"
        break
    fi
    
    # Adding variables from this page to the final array
    jq -s '.[0] + .[1]' "$TEMP_OUTPUT_FILE" "$page_file" > "${TEMP_OUTPUT_FILE}.new"
    mv "${TEMP_OUTPUT_FILE}.new" "$TEMP_OUTPUT_FILE"
    
    # Counting the number of variables in this page
    page_count=$(jq 'length' "$page_file")
    total_variables=$((total_variables + page_count))
    echo "Retrieved $page_count variables in this page. Total: $total_variables variables."
    
    # Cleanup
    rm "$page_file"
    
    # If we received fewer than per_page results, it's the last page
    if [ "$page_count" -lt "$per_page" ]; then
        break
    fi
    
    # Move to the next page
    page=$((page + 1))
done

# Copy the final result to the output file
cp "$TEMP_OUTPUT_FILE" "$OUTPUT_FILE"
rm "$TEMP_OUTPUT_FILE"

echo "Total CI/CD variables exported: $total_variables"

# Function to validate and fix JSON
validate_and_fix_json() {
    local input_file="$1"
    local output_file="$2"
    
    echo "Checking JSON validity..."
    
    # Testing JSON validity
    if jq empty "$input_file" 2>/dev/null; then
        echo "JSON is valid."
        cp "$input_file" "$output_file"
        return 0
    else
        echo "JSON contains errors, attempting to fix..."
        
        # Attempt 1: Fix escape characters
        sed 's/\\/\\\\/g' "$input_file" | sed 's/\r//g' > "$output_file"
        
        if jq empty "$output_file" 2>/dev/null; then
            echo "JSON successfully fixed (escape problem)."
            return 0
        fi
        
        # Attempt 2: Try to convert to an array if it's not already
        echo "[" > "$output_file"
        cat "$input_file" | sed 's/}{/},{/g' | sed 's/^{/{/g' | sed 's/}$/},/g' >> "$output_file"
        # Replace the last comma with nothing
        sed -i '$ s/,$//' "$output_file"
        echo "]" >> "$output_file"
        
        if jq empty "$output_file" 2>/dev/null; then
            echo "JSON successfully fixed (array conversion)."
            return 0
        fi
        
        # Attempt 3: Use Python for more advanced correction
        if command -v python3 &> /dev/null; then
            echo "Attempting to fix with Python..."
            python3 -c "
import json, sys
try:
    with open('$input_file', 'r') as f:
        content = f.read()
    # Try different fixes
    try:
        # Try 1: Direct parsing
        data = json.loads(content)
    except json.JSONDecodeError:
        # Try 2: Remove non-printable characters
        import re
        content_clean = re.sub(r'[^\x20-\x7E]', '', content)
        try:
            data = json.loads(content_clean)
        except json.JSONDecodeError:
            # Try 3: Assume it's a malformatted list of objects
            content_clean = '[' + content_clean.replace('}{', '},{') + ']'
            data = json.loads(content_clean)
    
    # If we get here, one of the methods worked
    with open('$output_file', 'w') as f:
        json.dump(data, f)
    sys.exit(0)
except Exception as e:
    print(f'Python Error: {str(e)}')
    sys.exit(1)
" 2>/dev/null
            
            if [ $? -eq 0 ] && jq empty "$output_file" 2>/dev/null; then
                echo "JSON successfully fixed by Python."
                return 0
            fi
        fi
        
        # If all attempts fail
        echo "Unable to automatically fix the JSON."
        echo "Problematic file content:"
        cat "$input_file"
        return 1
    fi
}

# Validate and fix the JSON
if ! validate_and_fix_json "$OUTPUT_FILE" "$FIXED_OUTPUT_FILE"; then
    echo "Error: Unable to process the exported JSON file."
    exit 1
fi

count=$(jq '. | length' "$FIXED_OUTPUT_FILE")
echo "CI/CD variables exported to $FIXED_OUTPUT_FILE ($count variables found)"

echo "Importing CI/CD variables into ${DESTINATION_TYPE} $DESTINATION_ID..."

# Checking access to the destination project/group
if ! curl --header "PRIVATE-TOKEN: $TOKEN" --silent "${API_URL}/${DESTINATION_ENDPOINT}" | grep -q "id"; then
    echo "Error: Unable to access the destination ${DESTINATION_TYPE}. Check the ID and your permissions."
    exit 1
fi

# Counters for statistics
counter=0
success=0
failed=0

# Reading the JSON file and creating variables in the destination project/group
jq -c '.[]' "$FIXED_OUTPUT_FILE" | while read -r var_json; do
    counter=$((counter + 1))
    key=$(echo "$var_json" | jq -r '.key')
    echo "[$counter/$count] Processing variable $key..."
    
    # Creating temporary files for JSON data
    tmp_update=$(mktemp)
    tmp_create=$(mktemp)
    
    # Creating JSON for the API while preserving all characters
    echo "$var_json" | jq '{value, variable_type, protected, masked, environment_scope}' > "$tmp_update"
    echo "$var_json" | jq '{key, value, variable_type, protected, masked, environment_scope}' > "$tmp_create"
    
    # Checking if the variable already exists in the destination project/group
    if curl --header "PRIVATE-TOKEN: $TOKEN" --silent "${API_URL}/${DESTINATION_ENDPOINT}/variables/${key}" | grep -q "key"; then
        # Updating the existing variable
        echo "Updating variable $key..."
        response=$(curl --request PUT \
             --header "PRIVATE-TOKEN: $TOKEN" \
             --header "Content-Type: application/json" \
             --data @"$tmp_update" \
             --write-out "\n%{http_code}" \
             --silent \
             "${API_URL}/${DESTINATION_ENDPOINT}/variables/${key}")
        
        http_code=$(echo "$response" | tail -n1)
        if [[ "$http_code" =~ ^2[0-9][0-9]$ ]]; then
            echo "Variable $key successfully updated."
            success=$((success + 1))
        else
            echo "Error updating variable $key (HTTP $http_code)"
            failed=$((failed + 1))
            
            # Add this variable to the failure list
            error_response=$(echo "$response" | sed '$d')
            echo "{\"key\":\"$key\",\"operation\":\"update\",\"http_code\":\"$http_code\",\"error\":$(echo "$error_response" | jq -R -s '.')}" | jq '.' > "${FAILED_VARS_FILE}.entry"
            jq -s '.[0] + [.[1]]' "$FAILED_VARS_FILE" "${FAILED_VARS_FILE}.entry" > "${FAILED_VARS_FILE}.new"
            mv "${FAILED_VARS_FILE}.new" "$FAILED_VARS_FILE"
            rm "${FAILED_VARS_FILE}.entry"
        fi
    else
        # Creating a new variable
        echo "Creating variable $key..."
        response=$(curl --request POST \
             --header "PRIVATE-TOKEN: $TOKEN" \
             --header "Content-Type: application/json" \
             --data @"$tmp_create" \
             --write-out "\n%{http_code}" \
             --silent \
             "${API_URL}/${DESTINATION_ENDPOINT}/variables")
        
        http_code=$(echo "$response" | tail -n1)
        if [[ "$http_code" =~ ^2[0-9][0-9]$ ]]; then
            echo "Variable $key successfully created."
            success=$((success + 1))
        else
            echo "Error creating variable $key (HTTP $http_code)"
            failed=$((failed + 1))
            
            # Add this variable to the failure list
            error_response=$(echo "$response" | sed '$d')
            echo "{\"key\":\"$key\",\"operation\":\"create\",\"http_code\":\"$http_code\",\"error\":$(echo "$error_response" | jq -R -s '.')}" | jq '.' > "${FAILED_VARS_FILE}.entry"
            jq -s '.[0] + [.[1]]' "$FAILED_VARS_FILE" "${FAILED_VARS_FILE}.entry" > "${FAILED_VARS_FILE}.new"
            mv "${FAILED_VARS_FILE}.new" "$FAILED_VARS_FILE"
            rm "${FAILED_VARS_FILE}.entry"
        fi
    fi
    
    # Cleaning up temporary files
    rm "$tmp_update" "$tmp_create"
    
    echo "Variable $key processed."
done

echo "==================================================================="
echo "IMPORT SUMMARY"
echo "==================================================================="
echo "Total variables processed: $count"
echo "Variables successfully imported: $success"
echo "Failed variables: $failed"

# If any variables failed, display the list
if [ "$failed" -gt 0 ]; then
    echo ""
    echo "==================================================================="
    echo "LIST OF FAILED VARIABLES"
    echo "==================================================================="
    
    # Create a detailed report of failures
    jq -r '.[] | "Variable: \(.key)\nOperation: \(.operation)\nHTTP Code: \(.http_code)\nError: \(.error)\n-------------------"' "$FAILED_VARS_FILE"
    
    # Save this list to a file
    failed_report="gitlab_cicd_failed_vars_${SOURCE_TYPE}_${SOURCE_ID}_to_${DESTINATION_TYPE}_${DESTINATION_ID}.txt"
    jq -r '.[] | "Variable: \(.key)\nOperation: \(.operation)\nHTTP Code: \(.http_code)\nError: \(.error)\n-------------------"' "$FAILED_VARS_FILE" > "$failed_report"
    
    echo ""
    echo "The list of failed variables has also been saved to the file: $failed_report"
fi

# Cleaning up the temporary error file
rm "$FAILED_VARS_FILE"

echo ""
echo "The export files ($OUTPUT_FILE and $FIXED_OUTPUT_FILE) have been kept for reference."
