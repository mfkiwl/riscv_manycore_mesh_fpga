import os
from termcolor import colored, cprint
import subprocess
import argparse
import difflib
import sys
import ref_orderer

parser = argparse.ArgumentParser(description= 'get test name from build')
parser.add_argument('test_name', help='The name of the test to run pp on')
args = parser.parse_args()

def print_message(msg):
    msg_type = msg.split()[0]
    try:
        color = {
            '[PP_ERROR]'   : 'red',
            '[PP_WARNING]' : 'yellow',
            '[PP_INFO]'    : 'green',
            '[PP_COMMAND]' : 'cyan',
        }[msg_type]
    except:
        color = 'blue'
    print(colored(msg,color,attrs=['bold']))        

MODEL_ROOT = subprocess.check_output('git rev-parse --show-toplevel', shell=True).decode().split('\n')[0]
os.chdir(MODEL_ROOT)


print_message('--------------------------------------------------------')
print_message("     Cache Post-Process  : "+args.test_name )
print_message('--------------------------------------------------------')
# Path to the directory containing the tests
base_path = "target/cache/tests"
# Construct the path to the transcript file
transcript = args.test_name+"_transcript"
file_transcript = os.path.join(base_path, args.test_name, transcript).replace("\\", "/")

# Construct the paths to the two files to compare
file1_path = os.path.join(base_path, args.test_name, "cache_ref_trk.log").replace("\\", "/")
file2_path = os.path.join(base_path, args.test_name, "cache_ref_gold_trk.log").replace("\\", "/")
# add error handling for missing files
if not os.path.exists(file1_path):
    print_message("[PP_ERROR] File not found: "+file1_path)
    sys.exit(1)
if not os.path.exists(file2_path):
    print_message("[PP_ERROR] File not found: "+file2_path)
    sys.exit(1)
if not os.path.exists(file_transcript):
    print_message("[PP_ERROR] File not found: "+file_transcript)
    sys.exit(1)

#Reorder the ref_trk files by pairs of Req/rsp
ref_orderer.orderer_func(file1_path)
ref_orderer.orderer_func(file2_path)


if os.path.exists(file2_path):
    # Open the two files
    with open(file1_path, "r") as file1, open(file2_path, "r") as file2:
        # Read the contents of the two files
        file1_contents = file1.readlines()
        file2_contents = file2.readlines()
        # Initialize variables to keep track of diffs
        num_diffs = 0
        diff_lines = []
    # Construct the path to the output file
    output_path = os.path.join(base_path, args.test_name, "test_golden_checker.log")
    output_path = os.path.normpath(output_path)
    output_path = output_path.replace("\\","/")
    
    # Read the contents of both files
    with open(file1_path, 'r') as file1, open(file2_path, 'r') as file2:
        file1_contents = file1.readlines()
        file2_contents = file2.readlines()
        print(f"Current test file: ",colored(file1_path,'yellow', attrs=['bold']))
        print(f"Golden file:       ",colored(file2_path,'yellow', attrs=['bold']))

    # Find the differences between the files
    differ  = difflib.Differ()
    diff    = list(differ.compare(file1_contents, file2_contents))
    # print the diff to the output file
    diff_file = open(output_path, 'w')
    diff_file.write("review the diff between the current test and the golden tracker\n\n")
    diff_file.write("The + : line is present in golden but not in the test \n")
    diff_file.write("The - : line is present in test but not in the golden\n")
    diff_file.write("The ? : both line exist, with a diff mark with ^^^^^^ \n")
    for line in diff:
        diff_file.write(line)

    # Count the number of differences
    num_diffs = len([line for line in diff if line.startswith('+') or line.startswith('-')])

    # Print the differences
    for line in diff:
        if line.startswith('+'):
            print(f"{colored(line, 'green')}")
        elif line.startswith('-'):
            print(f"{colored(line, 'red')}")


    # Print the path to the output file
    if num_diffs > 0:
        #print(f"There are {num_diffs} differences between the two files:")
        #print(f"Please refer to" ,colored(output_path,'white',attrs=['bold']), "to see the full diff\n")
        print_message(f"[PP_WARNING] There are {num_diffs} differences between the two files:")
        print_message(f"[PP_INFO] Please refer to {output_path} to see the full diff\n")

    #check if the test have failed: 
    # 1) the test has the string "ERROR" in the transcript
    # 2) number of diff > 0 
    if("ERROR" in open(file_transcript).read()):
        print_message(f"\n[PP_ERROR] {args.test_name} has failed - See Error in the test transcript\n"+file_transcript)
        sys.exit(1)
    if num_diffs == 0:
        print(colored("\n[PP_INFO] Post-Process finish successfully ",'green',attrs=['bold']))
        sys.exit(0)
    else:
        print_message(f"\n[PP_ERROR] {args.test_name} have failed Post-Process")
        sys.exit(1)



