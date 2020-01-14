#!/usr/bin/env bash

source get_program_accounts.sh

LAMPORTS_PER_SOL=1000000000 # 1 billion
all_stake_accounts_json_file=all_stake_accounts_data.json
all_stake_accounts_csv_file=all_stake_accounts_data.csv

usage() {
  exitcode=0
  if [[ -n "$1" ]]; then
    exitcode=1
    echo "Error: $*"
  fi
  cat <<EOF
usage: $0 [cluster_rpc_url] [identity_pubkey]

 Report the account addresses, balances and lockups of all stake accounts
 for which a given key is the authorized staker.
 Also report the system account balance for that same key.

 Required arguments:
   cluster_rpc_url  - RPC URL and port for a running Solana cluster (ex: http://34.83.146.144:8899)
   identity_pubkey  - Base58 pubkey that is an authorized staker for at least one stake account on the cluster.
EOF
  exit $exitcode
}

url=$1
[[ -n $url ]] || usage
shift
filter_pubkey=$1
[[ -n $filter_pubkey ]] || usage
shift

function parse_stake_account_data_to_file {
  account_key=$(echo "$1" | tr -d '"')
  filter_key="$2"
  csvfile="$3"

  account_data="$(solana --url $url show-stake-account $account_key)"
  staker="$(echo "$account_data" | grep -i 'authorized staker' | cut -f3 -d " ")"
  lockup_epoch="$(echo "$account_data" | grep -i 'lockup epoch' | cut -f3 -d " ")"
  if [[ "$staker" == "$filter_key" ]] ; then
    echo STAKE,$account_key,$lamports,$lockup_epoch >> $csvfile
  fi
}

function display_results_summary {
  stake_account_balance_total=0
  num_stake_accounts=0
  {
  read
  while IFS=, read -r program account_pubkey lamports lockup_epoch; do
    case $program in
      SYSTEM)
        system_account_balance=$lamports
        ;;
      STAKE)
        stake_account_balance_total=$((stake_account_balance_total + $lamports))
        num_stake_accounts=$((num_stake_accounts + 1))
        ;;
      *)
        echo "Unknown program: $program"
        exit 1
        ;;
    esac
  done
  } < "$results_file"

  stake_account_balance_total_sol="$(bc <<< "scale=3; $stake_account_balance_total/$LAMPORTS_PER_SOL")"
  system_account_balance_sol="$(bc <<< "scale=3; $system_account_balance/$LAMPORTS_PER_SOL")"

  all_account_total_balance="$(bc <<< "scale=3; $system_account_balance+$stake_account_balance_total")"
  all_account_total_balance_sol="$(bc <<< "scale=3; ($system_account_balance+$stake_account_balance_total)/$LAMPORTS_PER_SOL")"

  echo "--------------------------------------------------------------------------------------"
  echo "Results written to: $results_file"
  echo "--------------------------------------------------------------------------------------"
  echo "Summary of accounts owned by $filter_pubkey"
  echo ""
  printf "Number of STAKE accounts: %'d\n" $num_stake_accounts
  printf "Balance of all STAKE accounts: %'d lamports\n" $stake_account_balance_total
  printf "Balance of all STAKE accounts: %'.3f SOL\n" $stake_account_balance_total_sol
  printf "\n"
  printf "Balance of SYSTEM account: %'d lamports\n" $system_account_balance
  printf "Balance of SYSTEM account: %'.3f SOL\n" $system_account_balance_sol
  printf "\n"
  printf "Total Balance of ALL accounts: %'d lamports\n" $all_account_total_balance
  printf "Total Balance of ALL accounts: %'.3f SOL\n" $all_account_total_balance_sol
  echo "--------------------------------------------------------------------------------------"
}

[[ -n $filter_pubkey ]] || usage
results_file=accounts_owned_by_${filter_pubkey}.csv
system_account_json_file=system_account_${filter_pubkey}.json

echo "Getting all stake program accounts"
get_program_accounts STAKE $STAKE_PROGRAM_PUBKEY $url $all_stake_accounts_json_file
write_program_account_data_csv STAKE $all_stake_accounts_json_file $all_stake_accounts_csv_file

echo "Program,Account_Pubkey,Lamports,Lockup_Epoch" > $results_file

echo "Getting system account data"
get_account_info $filter_pubkey $url $system_account_json_file
system_account_balance="$(cat "$system_account_json_file" | jq -r '(.result | .value | .lamports)')"
echo SYSTEM, $filter_pubkey, $system_account_balance, N/A >> $results_file

echo "Querying cluster at $url for stake accounts with authorized staker: $filter_pubkey"
last_tick=$SECONDS
{
read
while IFS=, read -r account_pubkey lamports; do
  parse_stake_account_data_to_file $account_pubkey $filter_pubkey $results_file &
  sleep 0.01
  if [[ $(($SECONDS - $last_tick)) == 1 ]]; then
    last_tick=$SECONDS
    printf "."
  fi
done
} < "$all_stake_accounts_csv_file"
wait
printf "\n"

display_results_summary
