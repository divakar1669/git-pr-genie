AZURE_ORG="office"
AZURE_PROJECT="Office"
REPO_NAME="1JS"
TARGET_BRANCH="main"  
RENAME_LIMIT=100

# SHUBANSHU MODEL
# OPEN_AI_URL="https://testaimodel11.openai.azure.com/openai/deployments/gpt-4o/chat/completions?api-version=2025-01-01-preview"
# OPEN_AI_KEY=Cv271tgrnnqq5y42R5YbZFo23udE7Z2dOW7l2gVDvjjj71VDAVE4JQQJ99BCACYeBjFXJ3w3AAABACOGHRhy

# DIVA MODEL 4-0
OPEN_AI_URL="https://ai-openai40diva816896743293.openai.azure.com/openai/deployments/gpt-4o/chat/completions?api-version=2025-01-01-preview"
OPEN_AI_KEY=3kmfEDLcfnvpH4HWzOF95MVHbC5Xci8utkdE9fcAd6AJ5GVufSBrJQQJ99ALACHYHv6XJ3w3AAAAACOGxSVm

# DIVA MODEL 3.5
# OPEN_AI_URL="https://ai-openai40diva816896743293.openai.azure.com/openai/deployments/gpt-35-turbo-16k/chat/completions?api-version=2025-01-01-preview"
# OPEN_AI_KEY=3kmfEDLcfnvpH4HWzOF95MVHbC5Xci8utkdE9fcAd6AJ5GVufSBrJQQJ99ALACHYHv6XJ3w3AAAAACOGxSVm


# echo() {
#     local color="\e[32m"  # Change this to Red: \e[31m, Blue: \e[34m, etc.
#     local reset="\e[0m"

#     while IFS= read -r line; do
#         for word in $line; do
#             printf "${color}%s ${reset}" "$word"
#             sleep 0.3  # Adjust speed here
#         done
#         printf "\n"
#     done
# }

check_changed_packages() {
    local changed_packages=$(git diff --name-only main...HEAD | grep '/packages/' | cut -d'/' -f3 | sort -u)
    local output=""

    if [[ -n "$changed_packages" ]]; then
        output+="📦 The following packages have changed:\n\n"

        for package in $changed_packages; do
            output+="  • $package\n"
        done

        output+="\n"
        echo -e "$output"

        read -p "Have you tested changes in all the above packages? (YES/NO): " response
        output+="Have you tested changes in all the above packages? (YES/NO): $response\n"
        output+="Response: $response\n"
    else
        output="No package changes detected."
        echo "$output"
    fi
    captured_output="$output" 
} 

check_changed_packages

git config --global diff.renameLimit $RENAME_LIMIT

# Locate the script inside VS Code Spaces
SCRIPT_PATH=$(find / -type f -name "git-pr-copilot.sh" 2>/dev/null | head -n 1)

if [ -n "$SCRIPT_PATH" ]; then
    echo "🔹 Configuring 'git pr-genie' alias..."

    # Define the function to override 'git' command
    GIT_FUNCTION='
git() {
    if [ "$1" = "pr-genie" ]; then
        shift
        bash "'"$SCRIPT_PATH"'" "$@"
    else
        command git "$@"
    fi
}'

    # Add the function to ~/.bashrc if not already present
    if ! grep -q "git() {" ~/.bashrc; then
        echo "$GIT_FUNCTION" >> ~/.bashrc
        echo "✅ 'git pr-genie' command added to ~/.bashrc"
    else
        echo "✅ 'git pr-genie' is already configured."
    fi

    # Source ~/.bashrc to apply changes immediately
    source ~/.bashrc
    # echo "🔹 Run 'git pr-genie' to use your script!"
else
    echo "❌ Could not find git-pr-copilot.sh inside /workspaces."
fi

check_az_auth() {
    az account show &>/dev/null
    return $?
}

# Function to install and log in to Azure
azure_login() {
    echo "🔹 Checking Azure authentication..."
    
    if check_az_auth; then
        echo "✅ Azure authentication successful."
    else
        echo "🔹 Installing Azure CLI..."
        curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash

        # Ensure az is in the PATH
        export PATH=$PATH:/usr/bin:/usr/local/bin
        
        # Verify installation
        if ! command -v az &> /dev/null; then
            echo "❌ Azure CLI installation failed. Please check your setup."
            exit 1
        fi

        az version
        echo "🔹 Logging in to Azure CLI..."
        
        # az login
        # echo "🔹 Logging in to Azure DevOps..."

        # 🔹 Method 1: Interactive Login (if you have Azure AD access)
        az login --use-device-code
        az account set --subscription "$(az account show --query id --output tsv)"

        # 🔹 Method 2: PAT-based Login (Uncomment below for automation)
        # export AZURE_DEVOPS_EXT_PAT="your_personal_access_token"
        # az devops login --organization "https://dev.azure.com/$AZURE_ORG" --pat "$AZURE_DEVOPS_EXT_PAT"

        if check_az_auth; then
            echo "✅ Azure authentication successful."
        else
            echo "❌ Azure authentication failed. Check your credentials."
            exit 1
        fi
    fi
}

azure_login


az config set extension.dynamic_install_allow_preview=true


SOURCE_BRANCH=$(git rev-parse --abbrev-ref HEAD)

GIT_DIFF=$(git diff --stat origin/$TARGET_BRANCH | head -n $RENAME_LIMIT)  

COMMIT_MSGS=$(git log origin/$TARGET_BRANCH..HEAD --pretty=format:"%s" | tr '\n' ' ')

SYSTEM_PROMPT="You are a helpful assistant that generates PR titles and descriptions.
Make a robust PR_Description going through the commits and file diffs in detail , do not explicitly mention the File Changes and Commit Details, 
Make the Description a human like one for me , not AI generated 
Make all your description and answers in  bullet points making it sharp and concise for human readability 
User captured Input :: $captured_output

Q1. What problem does this address?

Q2. How does it solve the problem?

Q3. How has the change been tested?

Q4.  Has the change been tested for accessibility in all platforms?

Given a user prompt, return a structured JSON response in the following format:

{
  \"PR_title\": \"<Generated PR Title>\",
  \"PR_Description\": \"<Generated PR Description>\"
  \"Answer1\" : \"<Generated Answer for Q1>\"
  \"Answer2\" : \"<Generated Answer for Q2>\"
  \"Answer3\" : \"<Generated Answer for Q3>\"
  \"Answer4\" : \"<Generated Answer for Q4>\"
}

give json in this format only , not in any other format , so that I could extract Answers from it 
Replace <Generated PR Title> , <Generated PR Description> , <Generated Answer for Q1> , <Generated Answer for Q2> , <Generated Answer for Q3> and <Generated Answer for Q4> appropriately while ensuring valid JSON output."

# Input PR Data
PR_PROMPT="Generate a concise PR title and description based on the following diff summary and commit messages:

Diff:
$GIT_DIFF

Commits:
$COMMIT_MSGS"

# JSON Payload Construction
JSON_PAYLOAD=$(jq -n --arg system_prompt "$SYSTEM_PROMPT" --arg prompt "$PR_PROMPT" '{
    model: "gpt-4",
    messages: [
        {role: "system", content: $system_prompt},
        {role: "user", content: $prompt}
    ]
}')

# Output JSON
# echo "$JSON_PAYLOAD"

# echo "OPEN AI URL :: $OPEN_AI_URL"
# echo $JSON_PAYLOAD

PR_RESPONSE=$(curl -s -X POST $OPEN_AI_URL \
    -H "api-key: $OPEN_AI_KEY" \
    -H "Content-Type: application/json" \
    -d "$JSON_PAYLOAD")


# echo $PR_RESPONSE


# Extract JSON content
RAW_JSON=$(echo "$PR_RESPONSE" | jq -r '.choices[0].message.content')

# # Remove markdown-style code blocks if present
if [[ "$RAW_JSON" == *'```json'* ]]; then
    JSON_CONTENT=$(echo "$RAW_JSON" | sed -n '/```json/,/```/p' | sed '1d;$d')
else
    JSON_CONTENT="$RAW_JSON"
fi

# Validate JSON extraction
if [[ -z "$JSON_CONTENT" || "$JSON_CONTENT" == "null" ]]; then
    echo "❌ JSON content extraction failed."
    exit 1
fi

PR_TITLE=$(echo "$JSON_CONTENT" | jq -r '.PR_title')
PR_DESCRIPTION=$(echo "$JSON_CONTENT" | jq -r '.PR_Description')
Q1=$(echo "$JSON_CONTENT" | jq -r '.Answer1')
Q2=$(echo "$JSON_CONTENT" | jq -r '.Answer2')
Q3=$(echo "$JSON_CONTENT" | jq -r '.Answer3')
Q4=$(echo "$JSON_CONTENT" | jq -r '.Answer4')


if [[ -z "$PR_TITLE" || -z "$PR_DESCRIPTION" ]]; then
    echo "Error: Failed to extract PR title or description."
    exit 1
fi


# Store the template as a variable
Description_Template="
<!-- **Important:**  You should select a template that corresponds to the product you are modifying from the \"Add a template\" dropdown menu. For example, changes to \`office-start-*\` should use the \`office-start.md\` template.\" -->

$PR_DESCRIPTION

## What problem does this address?
$Q1
## How does it solve the problem?
$Q1
## How has the change been tested?
$Q3
## Has the change been tested for accessibility in all platforms?
$Q4

<!-- Refer to
[this wiki](https://dev.azure.com/office/Office/_wiki/wikis/1JS/33367/Accessibility-guidance-x-platform-in-Midgard)
for tools and guidance -->

## Work item link

[<Work item placeholder>]()

## Did you update the documentation?

## Before and after screenshots (if applicable)

|   Before   |   After    |
| :--------: | :--------: |
| Screenshot | Screenshot |

<!-- _Generate tables easily using
[this tool](https://www.tablesgenerator.com/markdown_tables)_

For guidance on creating good PRs, see
[1JS Pull Request Guidelines](https://dev.azure.com/Office/Office/_wiki/wikis/1JS/69754/PR-guidelines).
 -->
"


echo -e "PR_TITLE : $PR_TITLE"
# echo -e "\n\n PR_DESCRIPTION:: $Description_Template"
# echo " PR_DESCRIPTION :: $Description_Template"

PR_URL=$(az repos pr create \
    --org "https://dev.azure.com/$AZURE_ORG" \
    --project "$AZURE_PROJECT" \
    --repository "$REPO_NAME" \
    --source-branch "$SOURCE_BRANCH" \
    --target-branch "$TARGET_BRANCH" \
    --title "$PR_TITLE" \
    --description "$Description_Template" \
    --output tsv --query "url")

if [[ -n "$PR_URL" ]]; then
    PR_ID=$(echo "$PR_URL" | grep -oE 'pullRequests/[0-9]+' | cut -d'/' -f2)

    CORRECT_URL="https://dev.azure.com/office/Office/_git/1JS/pullrequest/$PR_ID"

    echo "✅ Pull request created successfully 🔗 : $CORRECT_URL"
else
    echo "❌ Failed to create pull request."
fi