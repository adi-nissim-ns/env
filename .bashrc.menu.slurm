#!/bin/bash
# https://wiki.nextsilicon.com/wiki/software/software-bringup/getting-access-to-a-card-using-slurm/ 

_ENV_PROJECT_DIR=$(dirname $(readlink -f ${BASH_SOURCE[0]}))

function allocate_hw() {
  local _PARTITION=$1
  local _HOURS=$2
  local _NODES=1

  echo_info "Allocating hardware in partition=${_PARTITION}, hours=${_HOURS}, nodes=${_NODES}"
  run_command salloc --partition=${_PARTITION} --nodes=${_NODES} --time=${_HOURS}:00:00 --exclusive --no-shell
}

function reserve_hw() {
  local _PARTITION=$1
  local _HOURS=$2

  echo_info "Allocating hardware in partition=${_PARTITION}, hours=${_HOURS}"
  run_command scontrol --uid=$USER create reservation StartTime=now Duration=${_HOURS}:00:00 Partition=${_PARTITION} users=$USER
}

function menu-slurm() {
  echo ""
  echo "====================menu-slurm===================="
  echo "0. Exit"
  echo "1. Main menu"
  echo "2. step1: ssh to slurm"
  echo "3. step2: get patritions info (sinfo)"
  echo "4. step3: see already allocated HW resources (squeue --me)"
  echo "5. step4: allocate a HW resource in partition=cloud, hours=9(salloc)"
  echo "6. step4: allocate bare metal HW resource in partition=BM-Maverick2-Single, hours=9(salloc)" 
  echo "7. step4: reserve a HW resource in partition=cloud, hours=9(salloc)"
  echo "8. step4: reserve bare metal HW resource in partition=BM-Maverick2-Single, hours=9(salloc)"
  echo "9. VM fix mount issue (known for missing space3 mount in VM) - run inside the VM"
  echo "=====================menu-slurm==================="
  
  read -p "Select an option: " option
  case $option in
    0)
      echo "Exiting..."
      return 0
      ;;
    1)
      menu 
      ;;
    2)
      run_command $SSH_SLURM
      menu-slurm
      ;;
    3)
      run_command sinfo
      menu-slurm
      ;;
    4)
      run_command "squeue --me"
      menu-slurm
      ;;
    5)
      # get number of hours from user
      read -p "Enter number of hours: " hours
      check if $hours has been passed
      if [ -z "$hours" ]; then
        echo "No argument supplied. Using default time of 9 hours"
        allocate_hw  cloud 9
      else
        allocate_hw  cloud $hours
      fi
      menu-slurm        
      ;;
    6)

      # get number of hours from user
      read -p "Enter number of hours: " hours
      check if $hours has been passed
      if [ -z "$hours" ]; then
        echo "No argument supplied. Using default time of 9 hours"
        allocate_hw   BM-Maverick2-Single 9
      else
        allocate_hw   BM-Maverick2-Single $hours
      fi
      menu-slurm
      ;;
    7)
          # get number of hours from user
      read -p "Enter number of hours: " hours
      check if $hours has been passed
      if [ -z "$hours" ]; then
        echo "No argument supplied. Using default time of 9 hours"
        reserve_hw   cloud 9
      else
        reserve_hw   cloud $hours
      fi
      menu-slurm
      ;;
    8)
      # get number of hours from user
      read -p "Enter number of hours: " hours
      check if $hours has been passed
      if [ -z "$hours" ]; then
        echo "No argument supplied. Using default time of 9 hours"
        reserve_hw BM-Maverick2-Single 9
      else
        reserve_hw BM-Maverick2-Single $hours
      fi
      menu-slurm
      ;;
    9)
      echo "Fixing VM mount issue..."
      # Add commands to fix the mount issue here
      run_command sudo lustre_rmmod
      run_command sudo modprobe lnet
      run_command sudo lnetctl lnet configure --all
      run_command sudo mount -a
      menu-slurm
      ;;
    *)
      echo "Invalid option. Please try again."
      menu_run
      ;;
  esac
}

echo_info "Loading menu-slurm ..."
